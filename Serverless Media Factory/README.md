# Serverless Media Factory

**Services:** S3 · EventBridge · Step Functions · Lambda  
**Concepts:** Fan-out, event-driven architecture, loop prevention, parallel workflows

---

## What You're Building

A static website where a user uploads one image and three independent background workflows automatically produce:

| Output       | Filename pattern     | Size             |
| ------------ | -------------------- | ---------------- |
| Thumbnail    | `vacation_thumb.jpg` | 150 × 150        |
| Grayscale    | `vacation_bw.jpg`    | same as original |
| Large resize | `vacation_large.jpg` | 1280 × 720       |

All three workflows run **at the same time** (parallel, not sequential).

---

## Architecture

```txt
Browser
  │  PUT uploads/vacation.jpg
  ▼
S3 Bucket ──────────────────────────────────────────────────
  │  S3 EventBridge notification (Object Created)
  ▼
EventBridge Rule  (filter: prefix = "uploads/")
  │
  ├──► Step Function A (thumbnail)  ──► Lambda ──► processed/vacation_thumb.jpg
  ├──► Step Function B (grayscale)  ──► Lambda ──► processed/vacation_bw.jpg
  └──► Step Function C (large)      ──► Lambda ──► processed/vacation_large.jpg
```

> **Loop prevention:** EventBridge only watches the `uploads/` prefix.
> Step Functions write to `processed/`. Those writes never trigger the rule again.

---

## Lab Files

```txt
serverless-media-factory/
├── frontend/
│   ├── index.html          ← static website
│   └── script.js           ← upload + polling logic
├── lambda/
│   └── image_processor.py  ← single Lambda function (3 modes)
├── statemachines/
│   ├── sf_thumbnail.json   ← State Machine A definition
│   ├── sf_grayscale.json   ← State Machine B definition
│   └── sf_large.json       ← State Machine C definition
├── iam/
│   ├── sf_lambda_invoke_policy.json  ← permission for SF → Lambda
│   └── bucket_policy.json            ← public read for website + processed/
└── eventbridge_pattern.json          ← event filter (copy-paste into console)
```

---

## Steps

### 1. Create the S3 Bucket

1. Go to **S3 → Create bucket**
2. Configure:
   - **Bucket name:** choose a globally unique name, e.g. `media-factory-yourname`  
     *(write it down — you'll need it in several places)*
   - **Region:** `us-east-1` (or your preferred region — stay consistent)
   - **Block all public access:** **uncheck** this (the website needs to be public)
   - Acknowledge the warning checkbox
3. Click **Create bucket**

---

### 2. Enable EventBridge Notifications on the Bucket

> S3 does **not** send events to EventBridge by default — you must turn it on.

1. Open your bucket → **Properties** tab
2. Scroll to **Amazon EventBridge**
3. Click **Edit** → turn **On** → **Save changes**

---

### 3. Apply the Bucket Policy

This allows the browser to PUT uploads and GET processed images.

1. Open your bucket → **Permissions** tab → **Bucket policy** → **Edit**
2. Open `iam/bucket_policy.json` from this lab folder
3. Replace `REPLACE_WITH_YOUR_BUCKET_NAME` with your actual bucket name
4. Paste the JSON → **Save changes**

---

### 4. Enable Static Website Hosting

1. Open your bucket → **Properties** tab → **Static website hosting** → **Edit**
2. Configure:
   - **Enable** static website hosting
   - **Index document:** `index.html`
3. **Save changes**
4. Note the **Bucket website endpoint** shown at the bottom — you'll open this in your browser at the end

---

### 5. Upload the Frontend Files

1. Open your bucket → **Objects** tab → **Upload**
2. Upload both files from the `frontend/` folder:
   - `index.html`
   - `script.js`
3. Click **Upload**

Now open `script.js` (or edit it locally first) and set the two constants at the top:

```js
const BUCKET_NAME   = "media-factory-yourname";   // your actual bucket name
const BUCKET_REGION = "us-east-1";                // your region
```

If you edited locally, re-upload `script.js`.

---

### 6. Add a CORS Rule to the Bucket

The browser needs to make cross-origin PUT requests to upload directly to S3.

1. Open your bucket → **Permissions** tab → **Cross-origin resource sharing (CORS)** → **Edit**
2. Paste the following JSON:

      ```json
      [
      {
         "AllowedHeaders": ["*"],
         "AllowedMethods": ["GET", "PUT", "HEAD"],
         "AllowedOrigins": ["*"],
         "ExposeHeaders": []
      }
      ]
      ```

3. **Save changes**

---

### 7. Create the Lambda Function

#### 7a. Create the Lambda Function

1. Go to **Lambda → Create function**
2. Configure:
   - **Function name:** `image-processor`
   - **Runtime:** `Python 3.12`
   - **Architecture:** `x86_64`
3. Click **Create function**

#### 7b. Paste the Code

1. In the **Code** tab, open the inline editor (usually `lambda_function.py`)
2. Delete the default code template
3. Copy the contents of `lambda/image_processor.py` from this lab folder and paste it
4. Click **Deploy**

#### 7c. Attach the Pillow Layer (via ARN)

Instead of building a custom layer, we will use a pre-built layer from the **Klayers** project which contains the **Pillow** library for Python 3.12.

1. Scroll to the very bottom of your Lambda function page to the **Layers** section
2. Click **Add a layer**
3. Select **Specify an ARN**
4. Paste the following ARN (valid for `us-east-1`):
   `arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-Pillow:10`  
   *(If you are using a different region, find the corresponding ARN at [klayers.cloud](https://api.klayers.cloud/api/v2/p3.12/layers/latest/us-east-1/))*
5. Click **Verify** and then **Add**

#### 7d. Give Lambda Access to S3

1. In your Lambda function → **Configuration** tab → **Permissions**
2. Click the **Role name** link (this opens the IAM Console in a new tab)
3. In the IAM tab → **Add permissions → Attach policies**
4. Search for and check **AmazonS3FullAccess**
5. Click **Add permissions**

#### 7e. Increase Timeout

Image processing can be resource-intensive and may take longer than the 3-second default.

1. Back in your Lambda function → **Configuration** tab → **General configuration** → **Edit**
2. Set **Timeout** to `30 seconds`
3. **Save**

---

### 8. Create the Three State Machines

Repeat these steps **three times** — once for each state machine file.

1. Go to **Step Functions → State machines → Create state machine**
2. Choose **Write your workflow in code**
3. In the **Definition** panel, delete the default content
4. Paste the contents of the matching file:
   - First machine: `statemachines/sf_thumbnail.json`
   - Second machine: `statemachines/sf_grayscale.json`
   - Third machine: `statemachines/sf_large.json`
5. In each file, replace `REPLACE_WITH_LAMBDA_ARN` with your Lambda function ARN  
   *(find it in Lambda → your function → top-right corner)*
6. Click **Next**
7. Configure:
   - **Name:**
     - `sf-thumbnail`
     - `sf-grayscale`
     - `sf-large`
   - **Execution role:** Create a new role (AWS will auto-create one with Lambda invoke permissions)
     - If permissions are missing later, attach the policy from `iam/sf_lambda_invoke_policy.json`
8. Click **Create state machine**
9. Note the **ARN** of each state machine — you'll need all three in the next step

---

### 9. Create the EventBridge Rule

1. Go to **EventBridge → Rules → Create rule (Advanced builder)**
2. Configure:
   - **Name:** `media-factory-trigger`
   - **Event bus:** `default`
   - **Rule type:** `Rule with an event pattern`
3. Click **Next**
4. Under **Event pattern**, switch the editor to **Edit pattern** (JSON mode)
5. Paste `eventbridge_pattern.json` from this lab folder  
   Replace `REPLACE_WITH_YOUR_BUCKET_NAME` with your actual bucket name
6. Click **Next**
7. Add **three targets** (click **Add another target** after each):

   | #   | Target type                    | Value                 |
   | --- | ------------------------------ | --------------------- |
   | 1   | `Step Functions state machine` | select `sf-thumbnail` |
   | 2   | `Step Functions state machine` | select `sf-grayscale` |
   | 3   | `Step Functions state machine` | select `sf-large`     |

   For each Step Functions target, under **Execution role**, choose **Create a new role for this specific resource** (EventBridge needs permission to start executions)

8. Click **Next → Next → Create rule**

---

### 10. Test the System

1. Open the **static website URL** from Step 4 in your browser
2. Choose a JPEG image from your computer
3. Click **Upload & Process**
4. Watch the status bar — the three processed images will appear one by one as each Step Function finishes

---

### 11. Observe Parallel Execution in Step Functions

1. Go to **Step Functions → State machines**
2. Open `sf-thumbnail` → **Executions** tab
3. Open the latest execution → inspect the **Graph** and **Event history**
4. Repeat for `sf-grayscale` and `sf-large`
5. Compare the **Start time** of all three — they all started within milliseconds of each other

> **Discussion:** What would happen if you used a single Step Function with three sequential Lambda calls instead? How does parallel execution change the user experience?

---

## Understanding the Loop Prevention

Look at the EventBridge pattern you deployed:

```json
"object": {
  "key": [{ "prefix": "uploads/" }]
}
```

- EventBridge **only** fires when a file is created in `uploads/`
- Your Lambda functions write to `processed/`
- Those writes **do not match** the pattern → no second trigger → no infinite loop

**Try this:** Temporarily change the prefix to `""` (empty string = match everything).  
Upload an image. Watch what happens in the EventBridge **Monitoring** tab.  
Then change it back.

---

## Clean Up

To avoid AWS charges after the lab:

1. **S3** → delete all objects in the bucket, then delete the bucket
2. **Lambda** → delete `image-processor`
3. **Step Functions** → delete all three state machines
4. **EventBridge** → delete rule `media-factory-trigger`
5. **Lambda Layers** → delete `pillow-layer`
