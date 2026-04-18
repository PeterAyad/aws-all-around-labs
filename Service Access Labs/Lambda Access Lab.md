# 🔐 Lab 1 — AWS Lambda + IAM Execution Role

**What you'll learn:** Lambda never stores credentials. It assumes an **IAM execution role** to call S3 and DynamoDB. You'll wire up the permissions, test the app, revoke them, and watch it fail — all from the console.

---

## Step 1 — Create an S3 Bucket

1. Open the **S3** console → click **Create bucket**
2. **Bucket name:** `iam-lab-yourname` *(replace "yourname" — must be globally unique)*
3. **AWS Region:** US East (N. Virginia) `us-east-1`
4. Leave all other settings as default → **Create bucket**

---

## Step 2 — Create a DynamoDB Table

1. Open the **DynamoDB** console → **Tables** → **Create table**
2. **Table name:** `iam-lab-notes`
3. **Partition key:** `id` → type: **String**
4. Leave everything default → **Create table**

---

## Step 3 — Create the IAM Execution Role 🔐

Lambda will use this role. Without it, Lambda has zero access to anything.

1. Open the **IAM** console → **Roles** → **Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** Lambda → **Next**
4. Skip the Permissions page for now → **Next**
5. **Role name:** `lambda-iam-lab-role` → **Create role**

Now attach a custom policy so you see exactly what you're granting:

1. Click into `lambda-iam-lab-role` → **Add permissions** → **Create inline policy**
2. Click the **JSON** tab and paste the following, replacing `iam-lab-yourname` with your bucket name:

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

1. **Next** → **Policy name:** `lambda-iam-lab-policy` → **Create policy**

---

## Step 4 — Create the Lambda Function

1. Open the **Lambda** console → **Create function**
2. **Author from scratch**
3. **Function name:** `iam-lab-app`
4. **Runtime:** Node.js 20.x
5. **Execution role:** Use an existing role → `lambda-iam-lab-role`
6. **Create function**

### Upload the code

On your local machine, inside the `shared/` folder, run:

```bash
npm install
zip -r function.zip .
```

Back in the Lambda console:

1. **Upload from** → **.zip file** → upload your `function.zip`
2. **Runtime settings** → **Edit** → set **Handler** to `lambda.handler` → **Save**

### Set environment variables

1. **Configuration** tab → **Environment variables** → **Edit** → **Add environment variable**

| Key            | Value              |
| -------------- | ------------------ |
| `S3_BUCKET`    | `iam-lab-yourname` |
| `DYNAMO_TABLE` | `iam-lab-notes`    |

→ **Save**

---

## Step 5 — Add a Public URL

1. **Configuration** → **Function URL** → **Create function URL**
2. **Auth type:** NONE *(lab only — don't do this in production)*
3. **Save** → copy the generated URL → open in your browser 🎉

---

## Step 6 — Test Everything

Use the app UI and confirm all four actions work:

| Action       | AWS call                         | Permission |
| ------------ | -------------------------------- | ---------- |
| Upload image | `s3:PutObject`                   | ✅         |
| View gallery | `s3:ListBucket` + `s3:GetObject` | ✅         |
| Save note    | `dynamodb:PutItem`               | ✅         |
| Load notes   | `dynamodb:Scan`                  | ✅         |

---

## 🔴 Break It On Purpose

1. **IAM** → **Roles** → `lambda-iam-lab-role` → click your inline policy → **Edit**
2. Delete the DynamoDB statement entirely → **Save changes**
3. Back in the app → click **Load Notes**
4. You'll see: `AccessDeniedException` with the exact action that was denied
5. Restore the statement → **Save** → try again → works immediately

> **Key insight:** Lambda fetches fresh IAM credentials on every invocation — changes take effect instantly, no restart needed.

---

## 🧹 Cleanup

1. **Lambda** → Functions → delete `iam-lab-app`
2. **IAM** → Roles → delete `lambda-iam-lab-role`
3. **S3** → open your bucket → **Empty** → then **Delete bucket**
4. **DynamoDB** → Tables → select `iam-lab-notes` → **Delete**
