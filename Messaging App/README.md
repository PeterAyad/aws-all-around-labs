# AWS Messaging Lab — SNS Fan-Out + SQS Queue Processing

A self-contained lab that teaches production-grade event-driven architecture. A single order event fans out to three independent downstream systems through SNS and SQS. Everything is configured through the AWS Console — no terminal required.

---

## Architecture Overview

```txt
                        Browser
                           │
                           ▼
                  ┌─────────────────┐
                  │   API Gateway   │  POST /orders
                  │   GET /status   │
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ order-receiver  │  Lambda — validates order,
                  │    Lambda       │  publishes to SNS
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   orders-topic  │  SNS — fan-out hub
                  └──┬──────┬───┬───┘
                     │      │   │
          ┌──────────┘      │   └───────────────┐
          │                 │                   │
          ▼                 ▼                   ▼
  ┌───────────────┐ ┌───────────────┐ ┌─────────────────┐
  │  orders-      │ │  orders-      │ │  orders-        │
  │  inventory-   │ │  notification-│ │  analytics-     │
  │  queue (SQS)  │ │  queue (SQS)  │ │  queue (SQS)    │
  └──────┬────────┘ └──────┬────────┘ └────────┬────────┘
         │                 │                   │
         ▼                 ▼                   ▼
  ┌─────────────┐   ┌─────────────┐   ┌──────────────┐
  │  inventory- │   │notification-│   │  analytics-  │
  │  consumer   │   │  consumer   │   │  consumer    │
  │  (Lambda)   │   │  (Lambda)   │   │  (Lambda)    │
  └──────┬──────┘   └──────┬──────┘   └──────┬───────┘
         │ on failure      │ on failure      │ on failure
         ▼                 ▼                 ▼
  ┌─────────────┐   ┌─────────────┐   ┌──────────────┐
  │  inventory- │   │notification-│   │  analytics-  │
  │    DLQ      │   │    DLQ      │   │    DLQ       │
  └─────────────┘   └─────────────┘   └──────────────┘

  ┌─────────────────────────────────────┐
  │  S3 Static Website (dashboard)      │  index.html — order form + queue monitor
  └─────────────────────────────────────┘
```

**How it works end-to-end:**

1. A student opens the S3-hosted dashboard and places an order through the form
2. The browser POSTs the order to **API Gateway**, which invokes the **order-receiver Lambda**
3. order-receiver validates the payload and publishes one message to the **SNS topic**
4. SNS simultaneously delivers a copy of that message to **all three SQS queues** — this is the fan-out
5. Each SQS queue independently triggers its own **consumer Lambda**
6. The **inventory-consumer** simulates reserving stock
7. The **notification-consumer** simulates sending a confirmation email
8. The **analytics-consumer** simulates writing to a data warehouse
9. If any consumer Lambda fails repeatedly, the message is moved to that queue's **Dead Letter Queue**
10. The dashboard polls the **queue-status Lambda** to display live queue depths and DLQ counts

> **Key insight:** SNS does not wait for consumers. Once it delivers to the queues, its job is done. Each downstream system processes at its own pace and fails independently — a bug in the notification system never affects inventory or analytics.

---

## What You Will Build

| Resource              | Count | Purpose                                                                                     |
| --------------------- | ----- | ------------------------------------------------------------------------------------------- |
| SNS Topic             | 1     | Fan-out hub — receives one publish, delivers to all 3 queues                                |
| SQS Queue             | 3     | One per domain: inventory, notification, analytics                                          |
| SQS Dead Letter Queue | 3     | Catches poison messages after max retries                                                   |
| Lambda Function       | 5     | order-receiver, inventory-consumer, notification-consumer, analytics-consumer, queue-status |
| API Gateway           | 1     | HTTP entry point — POST /orders and GET /status                                             |
| IAM Roles             | 3     | Lambda execution roles with least-privilege permissions                                     |
| S3 Bucket             | 1     | Hosts the static dashboard                                                                  |
| CloudWatch Log Groups | 5     | Auto-created per Lambda — used for execution logs                                           |

---

## Step 0 — Understand the Lab Files

This lab folder contains the following files. You will paste their contents into the AWS Console at the appropriate steps.

```txt
lab-sqs-sns/
├── lambdas/
│   ├── order-receiver.js        ← Paste into order-receiver Lambda
│   ├── inventory-consumer.js    ← Paste into inventory-consumer Lambda
│   ├── notification-consumer.js ← Paste into notification-consumer Lambda
│   ├── analytics-consumer.js    ← Paste into analytics-consumer Lambda
│   └── queue-status.js          ← Paste into queue-status Lambda
└── dashboard/
    └── index.html               ← Upload to S3
```

Do not edit the Lambda files yet. You will fill in environment variables through the Console after creating the SQS queues and SNS topic. The code references them as `process.env.ORDERS_TOPIC_ARN`, `process.env.INVENTORY_QUEUE_URL`, etc.

---

## Step 1 — Create the Dead Letter Queues

Dead Letter Queues must be created before the main queues because the main queues reference them.

Go to **SQS → Create queue** and create three DLQs. All use the same settings:

| Field                    | Value    |
| ------------------------ | -------- |
| Type                     | Standard |
| Message retention period | `4 days` |
| All other settings       | defaults |

Create them one at a time with these names:

- `orders-inventory-dlq`
- `orders-notification-dlq`
- `orders-analytics-dlq`

After creating each DLQ, copy its **ARN** — you will need it in the next step.

---

## Step 2 — Create the Main SQS Queues

Go to **SQS → Create queue** and create three queues. For each, configure:

| Field                    | Value        |
| ------------------------ | ------------ |
| Type                     | Standard     |
| Visibility timeout       | `30` seconds |
| Message retention period | `1 day`      |
| Delivery delay           | `0`          |

**Dead Letter Queue configuration** (expand the section at the bottom):

| Field                    | Value                                  |
| ------------------------ | -------------------------------------- |
| Enable dead-letter queue | ✓ Enabled                              |
| Dead-letter queue ARN    | Paste the ARN of the corresponding DLQ |
| Maximum receives         | `3`                                    |

> **Maximum receives = 3** means a message will be attempted 3 times before being moved to the DLQ. This is the retry count that makes poison message detection work.

Create the three queues with their corresponding DLQs:

| Queue Name                  | Dead-letter Queue         |
| --------------------------- | ------------------------- |
| `orders-inventory-queue`    | `orders-inventory-dlq`    |
| `orders-notification-queue` | `orders-notification-dlq` |
| `orders-analytics-queue`    | `orders-analytics-dlq`    |

After creating all three, copy their **URLs** — you will use them as environment variables in the Lambda functions.

---

## Step 3 — Create the SNS Topic

Go to **SNS → Topics → Create topic**.

| Field              | Value          |
| ------------------ | -------------- |
| Type               | Standard       |
| Name               | `orders-topic` |
| Display name       | `Orders Topic` |
| All other settings | defaults       |

Click **Create topic**. Copy the **Topic ARN** — you will use it as an environment variable in the order-receiver Lambda.

### Subscribe all three queues to the topic

On the `orders-topic` page, click **Create subscription** three times — once for each SQS queue:

| Field                       | Value                              |
| --------------------------- | ---------------------------------- |
| Protocol                    | Amazon SQS                         |
| Endpoint                    | ARN of the SQS queue (not the DLQ) |
| Enable raw message delivery | ✓ Enabled                          |

> **Raw message delivery** means SQS receives only the message body you published to SNS — not the SNS envelope JSON wrapped around it. This keeps the Lambda code simple.

Create three subscriptions:

- Endpoint: ARN of `orders-inventory-queue`
- Endpoint: ARN of `orders-notification-queue`
- Endpoint: ARN of `orders-analytics-queue`

All three subscriptions will show status **Confirmed** immediately for SQS endpoints.

### Allow SNS to send messages to the SQS queues

By default, SQS queues reject messages from SNS. You need to update each queue's access policy.

For each of the three main queues, go to **SQS → queue → Access policy → Edit** and replace the policy with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "REPLACE_WITH_THIS_QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "REPLACE_WITH_ORDERS_TOPIC_ARN"
        }
      }
    }
  ]
}
```

Replace `REPLACE_WITH_THIS_QUEUE_ARN` with the ARN of the specific queue you are editing, and `REPLACE_WITH_ORDERS_TOPIC_ARN` with the ARN of `orders-topic`. Repeat for all three queues.

---

## Step 4 — Create IAM Roles for Lambda

You will create three IAM roles — one for the order-receiver, one shared by the three consumer Lambdas, and one for the queue-status Lambda.

### Role 1 — order-receiver-role

Go to **IAM → Roles → Create role**.

**Step 1:** Trusted entity: **AWS service**, Use case: **Lambda**. Click **Next**.

**Step 2:** Attach these policies:

- `AWSLambdaBasicExecutionRole`

Click **Next**. Name the role `lab-order-receiver-role`. Click **Create role**.

Now add an inline policy to allow publishing to SNS. Go to the role → **Add permissions → Create inline policy → JSON** and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "REPLACE_WITH_ORDERS_TOPIC_ARN"
    }
  ]
}
```

Name the inline policy `allow-sns-publish`. Save.

### Role 2 — consumer-role (shared by all three consumers)

Go to **IAM → Roles → Create role**.

**Step 1:** Trusted entity: **AWS service**, Use case: **Lambda**. Click **Next**.

**Step 2:** Attach these policies:

- `AWSLambdaBasicExecutionRole`
- `AWSLambdaSQSQueueExecutionRole`

Click **Next**. Name the role `lab-consumer-role`. Click **Create role**.

### Role 3 — queue-status-role

Go to **IAM → Roles → Create role**.

**Step 1:** Trusted entity: **AWS service**, Use case: **Lambda**. Click **Next**.

**Step 2:** Attach these policies:

- `AWSLambdaBasicExecutionRole`

Click **Next**. Name the role `lab-queue-status-role`. Click **Create role**.

Now add an inline policy to allow reading SQS attributes and CloudWatch Logs. Go to the role → **Add permissions → Create inline policy → JSON** and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

Name the inline policy `allow-sqs-cloudwatch-read`. Save.

---

## Step 5 — Create the Lambda Functions

You will create five Lambda functions. All use the same base settings unless noted.

**Base settings for all functions:**

| Field        | Value                                                           |
| ------------ | --------------------------------------------------------------- |
| Runtime      | Node.js 22.x                                                    |
| Architecture | x86_64                                                          |
| Timeout      | 30 seconds (under Configuration → General configuration → Edit) |

Go to **Lambda → Create function → Author from scratch** for each.

---

### Lambda 1 — order-receiver

| Field          | Value                                         |
| -------------- | --------------------------------------------- |
| Function name  | `order-receiver`                              |
| Execution role | Use existing role → `lab-order-receiver-role` |

After creation, go to the **Code** tab. Delete the placeholder code and paste the full contents of `lambdas/order-receiver.js`.

Click **Deploy**.

Go to **Configuration → Environment variables → Edit** and add:

| Key                | Value                 |
| ------------------ | --------------------- |
| `ORDERS_TOPIC_ARN` | ARN of `orders-topic` |

Save.

---

### Lambda 2 — inventory-consumer

| Field          | Value                                   |
| -------------- | --------------------------------------- |
| Function name  | `inventory-consumer`                    |
| Execution role | Use existing role → `lab-consumer-role` |

Paste the contents of `lambdas/inventory-consumer.js` into the Code editor. Click **Deploy**.

**Add SQS trigger:**

Go to **Configuration → Triggers → Add trigger**.

| Field        | Value                    |
| ------------ | ------------------------ |
| Source       | SQS                      |
| SQS queue    | `orders-inventory-queue` |
| Batch size   | `1`                      |
| Batch window | `0`                      |

Click **Add**.

> **Batch size = 1** means the Lambda is called once per message. This makes it easy to see individual message processing in the logs. In production you would increase this for throughput.

---

### Lambda 3 — notification-consumer

| Field          | Value                                   |
| -------------- | --------------------------------------- |
| Function name  | `notification-consumer`                 |
| Execution role | Use existing role → `lab-consumer-role` |

Paste `lambdas/notification-consumer.js`. Deploy.

Add SQS trigger: queue = `orders-notification-queue`, batch size = `1`.

---

### Lambda 4 — analytics-consumer

| Field          | Value                                   |
| -------------- | --------------------------------------- |
| Function name  | `analytics-consumer`                    |
| Execution role | Use existing role → `lab-consumer-role` |

Paste `lambdas/analytics-consumer.js`. Deploy.

Add SQS trigger: queue = `orders-analytics-queue`, batch size = `1`.

---

### Lambda 5 — queue-status

| Field          | Value                                       |
| -------------- | ------------------------------------------- |
| Function name  | `queue-status`                              |
| Execution role | Use existing role → `lab-queue-status-role` |

Paste `lambdas/queue-status.js`. Deploy.

Go to **Configuration → Environment variables → Edit** and add all six queue URLs:

| Key                      | Value                              |
| ------------------------ | ---------------------------------- |
| `INVENTORY_QUEUE_URL`    | URL of `orders-inventory-queue`    |
| `INVENTORY_DLQ_URL`      | URL of `orders-inventory-dlq`      |
| `NOTIFICATION_QUEUE_URL` | URL of `orders-notification-queue` |
| `NOTIFICATION_DLQ_URL`   | URL of `orders-notification-dlq`   |
| `ANALYTICS_QUEUE_URL`    | URL of `orders-analytics-queue`    |
| `ANALYTICS_DLQ_URL`      | URL of `orders-analytics-dlq`      |

Save.

---

## Step 6 — Create the API Gateway

Go to **API Gateway → Create API → HTTP API → Build**.

### Configure routes and integrations

**Step 1 — Integrations:** Click **Add integration** twice.

First integration:

| Field            | Value            |
| ---------------- | ---------------- |
| Integration type | Lambda           |
| Lambda function  | `order-receiver` |

Second integration:

| Field            | Value          |
| ---------------- | -------------- |
| Integration type | Lambda         |
| Lambda function  | `queue-status` |

Click **Next**.

**Step 2 — Configure routes:**

Create two routes:

| Method | Resource path | Integration      |
| ------ | ------------- | ---------------- |
| POST   | `/orders`     | `order-receiver` |
| GET    | `/status`     | `queue-status`   |

Click **Next**.

**Step 3 — Define stages:**

| Field       | Value      |
| ----------- | ---------- |
| Stage name  | `prod`     |
| Auto-deploy | ✓ Enabled  |

Click **Next → Create**.

### Enable CORS

Go to your new API → **CORS → Configure**.

| Field                        | Value                |
| ---------------------------- | -------------------- |
| Access-Control-Allow-Origin  | `*`                  |
| Access-Control-Allow-Headers | `content-type`       |
| Access-Control-Allow-Methods | `POST, GET, OPTIONS` |

Save.

Copy the **Invoke URL** from the API overview page (e.g. `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod`). This is your API base URL.

---

## Step 7 — Host the Dashboard on S3

Go to **S3 → Create bucket**.

| Field                   | Value                                              |
| ----------------------- | -------------------------------------------------- |
| Bucket name             | `lab-sqs-sns-dashboard-<your-initials>`            |
| Region                  | Same region as your other resources                |
| Block all public access | **Uncheck** — you need public read for the website |

Acknowledge the public access warning. Click **Create bucket**.

### Enable static website hosting

Go to the bucket → **Properties → Static website hosting → Edit**.

| Field                  | Value                 |
| ---------------------- | --------------------- |
| Static website hosting | Enable                |
| Hosting type           | Host a static website |
| Index document         | `index.html`          |

Save.

### Add a bucket policy for public read

Go to **Permissions → Bucket policy → Edit** and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::REPLACE_WITH_YOUR_BUCKET_NAME/*"
    }
  ]
}
```

Replace `REPLACE_WITH_YOUR_BUCKET_NAME` with your actual bucket name. Save.

### Upload the dashboard

Go to **Objects → Upload** and upload `dashboard/index.html`.

Copy the **Bucket website endpoint** from the Properties → Static website hosting section (e.g. `http://lab-sqs-sns-dashboard-xx.s3-website-us-east-1.amazonaws.com`). This is your dashboard URL.

---

## Step 8 — Connect the Dashboard

Open the dashboard URL in your browser.

In the **Configuration** panel at the top:

| Field          | Value                                                                |
| -------------- | -------------------------------------------------------------------- |
| ORDER API URL  | `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/orders` |
| STATUS API URL | `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/status` |

Click **Save & Connect**. The status pill in the top right will turn green.

---

## Step 9 — Place Your First Order

Click **Load sample order** to populate the form, then click **⚡ Place Order**.

The order will appear in the **Dispatched Orders** log immediately.

After 2–3 seconds, click **↻ Refresh** on the Queue & DLQ Status section. The queue depths will show `0` — Lambda already processed the messages. The **Recent Executions** panel on each queue card shows the SUCCESS log lines from CloudWatch.

To see the full execution logs, go to **CloudWatch → Log groups → /aws/lambda/inventory-consumer** and inspect the latest log stream.

---

## Proving Fan-Out Works

### Verify all three queues received the message

Go to **CloudWatch → Log groups**.

Open each of the three consumer log groups:

- `/aws/lambda/inventory-consumer`
- `/aws/lambda/notification-consumer`
- `/aws/lambda/analytics-consumer`

Each should have a log stream from the last few minutes with a `SUCCESS` entry for the same `orderId`. This confirms that one SNS publish resulted in three independent Lambda executions.

### Verify SNS delivery metrics

Go to **SNS → Topics → orders-topic → Monitoring tab**.

The **NumberOfMessagesSent** and **NumberOfNotificationsDelivered** metrics should both show `1` (or more if you placed multiple orders). Delivered = 3× Sent because each message fans out to three subscriptions.

---

## Simulating Failures and DLQs

### Poison message — Inventory DLQ

Click **☠ Poison: Inventory DLQ** in the dashboard.

This places an order with item quantity = 100. The inventory-consumer Lambda throws an error when it sees this. SQS retries the message 3 times (because you set Maximum receives = 3), then moves it to `orders-inventory-dlq`.

**What to observe:**

1. In **CloudWatch → /aws/lambda/inventory-consumer**, you will see 3 error log entries for the same `orderId`
2. In **SQS → orders-inventory-dlq → Messages available**, the count will be `1`
3. In **SQS → orders-notification-queue** and **orders-analytics-queue**, the message was processed successfully — the inventory failure had zero effect on the other pipelines

> This is the core lesson: SQS + SNS fan-out gives you **fault isolation**. A broken consumer does not cascade.

### Poison message — Notification DLQ

Click **☠ Poison: Notification DLQ**.

This places a $10,000 order. The notification-consumer flags it as a potential fraud and throws. After 3 retries it lands in `orders-notification-dlq`. Inventory and analytics succeed normally.

### Burst load — SQS buffering

Click **⚡ Burst: 10 rapid orders**.

Ten orders are fired in 2 seconds. Lambda concurrency handles them but you may see brief queue depth spikes. Go to **CloudWatch → Metrics → SQS → orders-analytics-queue → ApproximateNumberOfMessagesVisible** to see the queue depth graph. This demonstrates that SQS acts as a buffer — the producer never waits for consumers.

### Malformed order — Input validation

Click **✗ Malformed order (400)**.

The order-receiver Lambda returns HTTP 400. SNS is never called. Go to **CloudWatch → /aws/lambda/order-receiver** and confirm the error was logged there — none of the consumer log groups have a new entry. This shows that the API layer validates before entering the queue system.

---

## Key Concepts Demonstrated

### Visibility timeout

When SQS delivers a message to a Lambda, the message becomes **invisible** to other consumers for the duration of the visibility timeout (30 seconds). If the Lambda succeeds, it deletes the message. If the Lambda fails or times out, the message becomes visible again and SQS retries.

To observe this:

1. Set the visibility timeout on `orders-inventory-queue` to 60 seconds
2. Place an order
3. Immediately check **Messages in flight** in the SQS console — you will see `1`
4. After the Lambda succeeds, the count returns to `0`

### At-least-once delivery

SNS and SQS both guarantee **at-least-once** delivery — not exactly-once. In rare cases the same message may be delivered twice. Check the analytics-consumer logs after a burst — if you see duplicate `orderId` entries, this is normal SQS behavior, not a bug. In production, consumers should be **idempotent** (processing the same message twice produces the same result).

### Queue depth as a backpressure signal

Go to **CloudWatch → Alarms → Create alarm**.

Metric: SQS → Per-Queue Metrics → `orders-analytics-queue` → `ApproximateNumberOfMessagesVisible`

Threshold: Greater than `10`

This alarm fires if analytics falls behind. In production this would trigger an auto-scaling action or page an on-call engineer.

---

## Checking Logs

All execution logs are in **CloudWatch → Log groups**.

| Log Group                           | What to look for                                     |
| ----------------------------------- | ---------------------------------------------------- |
| `/aws/lambda/order-receiver`        | Order ID, customer name, SNS publish confirmation    |
| `/aws/lambda/inventory-consumer`    | `[INVENTORY] SUCCESS` or `STOCK ERROR` for poison    |
| `/aws/lambda/notification-consumer` | `[NOTIFICATION] SUCCESS` or `EMAIL ERROR` for poison |
| `/aws/lambda/analytics-consumer`    | `[ANALYTICS] Writing to data warehouse`              |
| `/aws/lambda/queue-status`          | Queue depth values returned to the dashboard         |

---

## API Reference

All endpoints are available via the API Gateway invoke URL:

| Method | Path      | Description                                             |
| ------ | --------- | ------------------------------------------------------- |
| POST   | `/orders` | Place an order — fans out to all 3 queues via SNS       |
| GET    | `/status` | Returns queue depths and DLQ counts for all 3 pipelines |

**POST /orders — request body:**

```json
{
  "customerName": "Alice Smith",
  "items": [
    { "name": "Wireless Keyboard", "quantity": 1 },
    { "name": "USB-C Hub", "quantity": 2 }
  ],
  "total": 89.99
}
```

**POST /orders — response (202):**

```json
{
  "message": "Order accepted and dispatched for processing",
  "orderId": "ORD-1712345678901-A3F2K",
  "placedAt": "2024-04-05T14:23:45.678Z"
}
```

---

## Cleanup

Delete resources in this order to avoid dependency errors:

1. **Lambda functions** — delete all five: `order-receiver`, `inventory-consumer`, `notification-consumer`, `analytics-consumer`, `queue-status`
2. **API Gateway** — delete the HTTP API
3. **SNS Topic** — delete `orders-topic` (this also deletes its subscriptions)
4. **SQS Queues** — delete all six queues (3 main + 3 DLQs): `orders-inventory-queue`, `orders-notification-queue`, `orders-analytics-queue`, `orders-inventory-dlq`, `orders-notification-dlq`, `orders-analytics-dlq`
5. **S3 Bucket** — empty the bucket first, then delete it
6. **IAM Roles** — delete `lab-order-receiver-role`, `lab-consumer-role`, `lab-queue-status-role`
7. **CloudWatch Log Groups** — optionally delete the five `/aws/lambda/` log groups to avoid storage charges
