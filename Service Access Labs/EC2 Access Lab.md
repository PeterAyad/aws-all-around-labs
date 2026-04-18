# 🔐 Lab 2 — EC2 + IAM Instance Profile

**What you'll learn:** EC2 uses an **instance profile** — an IAM role attached directly to the virtual machine. The app running on the VM inherits those permissions automatically, with no credentials stored anywhere on disk.

---

## Step 1 — Create an S3 Bucket

1. Open the **S3** console → **Create bucket**
2. **Bucket name:** `iam-lab-yourname` *(replace "yourname" — globally unique)*
3. **Region:** `us-east-1`
4. Leave defaults → **Create bucket**

---

## Step 2 — Create a DynamoDB Table

1. Open the **DynamoDB** console → **Tables** → **Create table**
2. **Table name:** `iam-lab-notes`
3. **Partition key:** `id` → type: **String**
4. Leave defaults → **Create table**

---

## Step 3 — Create the IAM Role 🔐

1. Open the **IAM** console → **Roles** → **Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** EC2 → **Next**
4. Skip the permissions for now → **Next**
5. **Role name:** `ec2-iam-lab-role` → **Create role**

Now attach the permissions:

1. Click into `ec2-iam-lab-role` → **Add permissions** → **Create inline policy**
2. Click the **JSON** tab and paste, replacing `iam-lab-yourname` with your bucket name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::iam-lab-yourname",
        "arn:aws:s3:::iam-lab-yourname/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/iam-lab-notes"
    }
  ]
}
```

1. **Next** → **Policy name:** `ec2-iam-lab-policy` → **Create policy**

---

## Step 4 — Launch the EC2 Instance

1. Open the **EC2** console → **Instances** → **Launch instances**
2. **Name:** `iam-lab-server`
3. **AMI:** Amazon Linux 2023 (free tier eligible)
4. **Instance type:** t2.micro
5. **Key pair:** select an existing one or create a new one *(you'll need this to SSH in)*
6. **Network settings** → Edit → Add a security group rule:
   - Type: **Custom TCP**, Port: `3000`, Source: `0.0.0.0/0`
   - *(Keep the default SSH rule on port 22)*
7. Expand **Advanced details** → find **IAM instance profile** → select `ec2-iam-lab-role`
8. **Launch instance**

---

## Step 5 — Deploy and Run the App via SSH

To deploy your application, you will use **SCP** (Secure Copy) to transfer your files and **SSH** to connect to your instance and run the server.

### 1. Transfer Files to EC2

From your **local machine's terminal** (in the directory where your project files are located), run the following command to upload your code:

```bash
# Upload app.js and package.json to the EC2 home directory
scp -i /path/to/your-key.pem app.js package.json ec2-user@<PUBLIC_IP>:~/
```

### 2. Connect and Run the App

Now, establish an SSH connection to install dependencies and start the server:

```bash
# Connect to your instance
ssh -i /path/to/your-key.pem ec2-user@<PUBLIC_IP>

# Inside the EC2 terminal:
# Install Node.js
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs

# Organize files and install dependencies
mkdir -p app && mv app.js package.json app/
cd app
npm install

# Set environment variables and start the app
export S3_BUCKET="iam-lab-yourname"
export DYNAMO_TABLE="iam-lab-notes"
export AWS_REGION="us-east-1"
export PORT=3000

node app.js
```

Open: `http://<PUBLIC_IP>:3000` — find the public IP in the EC2 console under **Instance details** 🎉

---

## Step 6 — Test Everything

Use the web UI to confirm all actions work, then:

### 🔴 Break It On Purpose

1. **IAM** console → **Roles** → `ec2-iam-lab-role` → edit the inline policy
2. Remove `s3:PutObject` from the S3 actions → **Save changes**
3. Try uploading an image → `AccessDeniedException`!
4. In the EC2 terminal, also try: `aws s3 cp /etc/hostname s3://iam-lab-yourname/test.txt`
   → Same error — the role applies to everything on this VM, including CLI commands
5. Restore the permission → works again

> **Key insight:** The IAM role is attached to the VM itself — not to a user or a process. Any code running on this machine shares the same AWS identity.

---

## 🧹 Cleanup

1. **EC2** → select instance → **Instance state** → **Terminate**
2. **IAM** → delete `ec2-iam-lab-role`
3. **S3** → empty bucket → delete bucket
4. **DynamoDB** → delete `iam-lab-notes`
