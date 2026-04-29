# The Legacy System Migration — Amazon MQ Lab

**Scenario:** You are a Cloud Architect helping a retail company migrate to AWS. Their Point-of-Sale terminals and warehouse systems communicate over **AMQP** (the standard protocol used by RabbitMQ and ActiveMQ). The application cannot be rewritten to use SQS. Your job is to provision a managed **Amazon MQ** broker and wire the two systems together — without touching a single line of connection code.

**Services used:** Amazon MQ, EC2

**Assets provided:**

| File               | What it represents                                    |
| ------------------ | ----------------------------------------------------- |
| `producer.py`      | A store's Point-of-Sale terminal placing orders       |
| `consumer.py`      | The warehouse inventory system fulfilling orders      |
| `requirements.txt` | Python dependency (`pika` — the standard AMQP client) |

---

## 1. Create the Amazon MQ Broker

1. Go to **AWS Console → Amazon MQ → Create broker**
2. Select **RabbitMQ** as the broker engine, then click **Next**
3. Choose **Single-instance broker** (sufficient for this lab), then click **Next**
4. Configure the broker:

    | Setting       | Value                                          |
    | ------------- | ---------------------------------------------- |
    | Broker name   | `retail-broker` (or any name)                  |
    | Instance type | `mq.m5.large` (default)                        |
    | Username      | `admin`                                        |
    | Password      | choose a strong password and **write it down** |

5. Under **Access type**, select **Private access** — the broker will live inside your VPC
6. Under **VPC and subnets**, select your **default VPC** and any one subnet
7. Under **Security groups**, choose the **default security group** (you will update it in the next step)
8. Leave all other settings as defaults
9. Click **Create broker**

> ⏳ Provisioning takes **~5 minutes**. The broker status will change from `CREATION IN PROGRESS` to `RUNNING`.

---

## 2. Update the Security Group

The broker needs to accept AMQP connections (port **5671**) from your EC2 instance.

1. Go to **EC2 → Security Groups** and open the **default security group**
2. Click **Edit inbound rules → Add rule**

    | Type       | Protocol | Port | Source                                              |
    | ---------- | -------- | ---- | --------------------------------------------------- |
    | Custom TCP | TCP      | 5671 | `0.0.0.0/0` (or your EC2's SG for tighter security) |

3. Click **Save rules**

---

## 3. Copy the Broker Endpoint

1. Go back to **Amazon MQ → Brokers** and click on `retail-broker`
2. Wait until the status is **RUNNING**
3. Scroll down to the **Connections** section
4. Find the **AMQP** endpoint — it looks like:

    ```txt
    amqps://b-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.mq.us-east-1.amazonaws.com:5671
    ```

5. **Copy just the hostname** (the part between `amqps://` and `:5671`), e.g.:

    ```txt
    b-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.mq.us-east-1.amazonaws.com
    ```

You will pass this as the `--host` argument to the scripts.

---

## 4. Launch an EC2 Instance

1. Go to **EC2 → Launch instance**
2. Configure:

    | Setting        | Value                                 |
    | -------------- | ------------------------------------- |
    | AMI            | Amazon Linux 2023                     |
    | Instance type  | `t2.micro`                            |
    | VPC            | **Same VPC** you chose for the broker |
    | Security Group | Allow **SSH (port 22)** inbound       |

3. Launch the instance and SSH into it:

```bash
ssh -i your-key.pem ec2-user@<your-ec2-public-ip>
```

---

## 5. Install Dependencies

Run these commands on your EC2 instance:

```bash
# Upload the lab files first (from your local machine):
# scp -i your-key.pem producer.py consumer.py requirements.txt ec2-user@<ip>:~

sudo yum update -y
sudo yum install python3-pip -y
pip3 install -r requirements.txt
```

---

## 6. Send Orders (Run the Producer)

This simulates the **Point-of-Sale terminal** sending 5 orders to the broker:

```bash
python3 producer.py \
  --host b-xxxxxxxx-xxxx.mq.us-east-1.amazonaws.com \
  --user admin \
  --password <your-password> \
  --count 5
```

Expected output:

```txt
[POS] Connecting to broker at b-xxxxxxxx....amazonaws.com:5671 ...
[POS]  Sent order 1/5: {"order_id": "ORD-4821", "product": "Widget A", ...}
[POS]  Sent order 2/5: {"order_id": "ORD-1357", "product": "Gadget B", ...}
...
[POS] All orders sent. Connection closed.
```

---

## 7. Receive Orders (Run the Consumer)

Open a **second terminal** and run:

```bash
python3 consumer.py \
  --host b-xxxxxxxx-xxxx.mq.us-east-1.amazonaws.com \
  --user admin \
  --password <your-password>
```

Expected output:

```txt
[WH]  Waiting for orders on queue 'orders'. Press Ctrl+C to stop.

[WH]  ✔ Received order  → ID: ORD-4821 | Product: Widget A | Qty: 3 | Time: ...
[WH]  ✔ Received order  → ID: ORD-1357 | Product: Gadget B | Qty: 7 | Time: ...
...
```

Press **Ctrl+C** to stop the consumer.

---

## 8. Observe the Queue in the RabbitMQ Console (via SSH Tunnel)

Since the broker is in a private subnet, you will use your EC2 instance as a "bridge" (bastion host) to access the management UI from your local browser.

1. **Create the Tunnel:** On your **local machine** (not the EC2), run the following command in a new terminal window:

    ```bash
    ssh -i <your-private-key>.pem -L 8443:<your-broker-hostname>:443 ec2-user@<your-ec2-public-ip>
    ```

    *Keep this terminal window open to maintain the connection.*

2. **Access the UI:** Open your web browser and go to:
    **`https://localhost:8443`**
    *(Note: Your browser will show a security warning because the certificate belongs to AWS, not "localhost". Click **Advanced** and **Proceed/Continue** to bypass this.)*

3. **Log In:** Use the **Username** and **Password** you configured when creating the Amazon MQ broker.

4. **Monitor the Queue:**
    * Click on the **Queues** tab — you will see the `orders` queue listed.
    * **Test Decoupling:** Run the `producer.py` script on your EC2 instance while the consumer is **stopped**. Refresh the browser to see the "Ready" message count increase.
    * **Drain the Queue:** Start the `consumer.py` script and watch the messages disappear from the UI in real-time as they are processed.

> **Key Insight:** Using an SSH tunnel allows you to securely manage private cloud resources without exposing them to the open internet. The RabbitMQ console demonstrates how the broker acts as a durable buffer, ensuring no data is lost even if the consuming application is temporarily offline.

---

## 9. Challenge: Demonstrate Decoupling

1. **Stop the consumer** (Ctrl+C)
2. **Run the producer** to send 10 more orders (`--count 10`)
3. Check the RabbitMQ console — the 10 messages are safely **queued**, even though no consumer is running
4. **Start the consumer** — it immediately processes all 10 backlogged orders
5. The POS terminal never knew the warehouse was offline

---

## 10. Clean Up

To avoid ongoing charges:

1. Go to **Amazon MQ → Brokers → retail-broker**
2. Click **Actions → Delete**
3. Confirm deletion
4. Terminate your EC2 instance (if you launched one)
