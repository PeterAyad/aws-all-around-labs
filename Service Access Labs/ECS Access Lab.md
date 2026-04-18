# 🔐 Lab 3 — ECS Fargate + Task Role

**What you'll learn:** ECS has *two* IAM roles — students always mix them up. The **task execution role** lets ECS pull your private image from ECR and write logs. The **task role** is what your *app code* uses to call S3 and DynamoDB. You'll build the full network from scratch and wire up both roles from the console.

---

## Step 1 — Create an S3 Bucket

1. **S3** console → **Create bucket** → name: `iam-lab-yourname` → region: `us-east-1` → **Create bucket**

---

## Step 2 — Create a DynamoDB Table

1. **DynamoDB** → **Tables** → **Create table**
2. **Table name:** `iam-lab-notes` | **Partition key:** `id` (String) → **Create table**

---

## Step 3 — Create the VPC

ECS Fargate tasks need a properly networked VPC. The wizard creates everything in one shot.

1. Open the **VPC** console → **Your VPCs** → **Create VPC**
2. At the top, select **VPC and more** *(this activates the full wizard)*
3. Fill in the settings:

   | Setting                      | Value                                    |
   | ---------------------------- | ---------------------------------------- |
   | Name tag                     | `iam-lab-vpc`                            |
   | IPv4 CIDR                    | `10.0.0.0/16`                            |
   | Number of Availability Zones | `2`                                      |
   | Number of public subnets     | `2`                                      |
   | Number of private subnets    | `2`                                      |
   | NAT gateways                 | **In 1 AZ** *(reduces cost for the lab)* |
   | VPC endpoints                | None                                     |

4. **Create VPC** — ⏳ wait ~2 minutes

The wizard creates: 1 Internet Gateway (for the public subnets), 1 NAT Gateway (so private subnets can reach ECR and AWS APIs outbound), route tables wired up correctly.

1. Once created, go to **Subnets** and note down:
   - The **2 public subnet IDs** — names will contain `public`
   - The **2 private subnet IDs** — names will contain `private`

---

## Step 4 — Create Security Groups

Two security groups: one for the load balancer (internet-facing), one for the containers (internal only).

### Security Group A — Load Balancer

1. **VPC** console → **Security groups** → **Create security group**
2. **Name:** `iam-lab-alb-sg`
3. **VPC:** select `iam-lab-vpc`
4. **Inbound rules** → **Add rule:**
   - Type: **HTTP** | Port: `80` | Source: `0.0.0.0/0`
5. **Create security group**

### Security Group B — ECS Tasks

1. **Create security group**
2. **Name:** `iam-lab-ecs-sg`
3. **VPC:** select `iam-lab-vpc`
4. **Inbound rules** → **Add rule:**
   - Type: **Custom TCP** | Port: `3000` | Source: select **`iam-lab-alb-sg`** from the dropdown
   *(Only the load balancer can reach the containers — nothing else)*
5. **Create security group**

---

## Step 5 — Push the Docker Image to ECR (Private)

### Create the ECR repository

1. Open the **ECR** console → **Private registry** → **Repositories** → **Create repository**
2. **Visibility:** Private
3. **Repository name:** `iam-lab-app`
4. Leave all other settings default → **Create repository**

### Build and push

1. Click into `iam-lab-app` → click **View push commands** (top-right button)
2. A panel opens with 4 commands tailored to your account and region — follow them in order in your terminal from the `shared/` folder:
   - Command 1: authenticates Docker to your private ECR registry
   - Command 2: builds the Docker image
   - Command 3: tags it with the ECR URI
   - Command 4: pushes it

3. Refresh the ECR console — you'll see a `latest` image tag appear

> The image is **private**. No one can pull it without the correct IAM permissions. This is exactly why the execution role exists.

---

## Step 6 — Create the Two IAM Roles 🔐

This is the heart of the lab. Read carefully — these two roles do completely different things.

### Role A: Task Execution Role *(ECS infrastructure uses this)*

This role lets ECS itself: authenticate to ECR to pull your private image, and write container logs to CloudWatch. Your app code never uses this role.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → scroll down to find **Elastic Container Service Task** → select it → **Next**
3. Search for and attach: `AmazonECSTaskExecutionRolePolicy` *(this is an AWS-managed policy)*
4. **Next** → **Role name:** `ecs-lab-execution-role` → **Create role**

Now add an explicit inline policy so you can see exactly what ECR permissions are needed:

1. Click into `ecs-lab-execution-role` → **Add permissions** → **Create inline policy** → **JSON** tab:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "ECRAuth",
          "Effect": "Allow",
          "Action": "ecr:GetAuthorizationToken",
          "Resource": "*"
        },
        {
          "Sid": "ECRPullImage",
          "Effect": "Allow",
          "Action": [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ],
          "Resource": "arn:aws:ecr:us-east-1:*:repository/iam-lab-app"
        },
        {
          "Sid": "CloudWatchLogs",
          "Effect": "Allow",
          "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "*"
        }
      ]
    }
    ```

2. **Policy name:** `ecs-lab-execution-policy` → **Create policy**

> Notice: `ecr:GetAuthorizationToken` must be `Resource: "*"` — it's a global API call with no specific resource ARN. The actual image pull actions are scoped to your specific repository.

### Role B: Task Role *(your app code uses this)*

This is what the Node.js app uses when it calls `s3.send(...)` or `dynamo.send(...)`. It has nothing to do with ECR or logs.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **Elastic Container Service Task** → **Next**
3. Skip policies → **Next**
4. **Role name:** `ecs-lab-task-role` → **Create role**

5. Click into `ecs-lab-task-role` → **Add permissions** → **Create inline policy** → **JSON** tab:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "S3Access",
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket"
          ],
          "Resource": [
            "arn:aws:s3:::iam-lab-yourname",
            "arn:aws:s3:::iam-lab-yourname/*"
          ]
        },
        {
          "Sid": "DynamoDBAccess",
          "Effect": "Allow",
          "Action": [
            "dynamodb:PutItem",
            "dynamodb:Scan"
          ],
          "Resource": "arn:aws:dynamodb:us-east-1:*:table/iam-lab-notes"
        }
      ]
    }
    ```

6. Replace `iam-lab-yourname` with your actual bucket name
7. **Policy name:** `ecs-lab-task-policy` → **Create policy**

---

## Step 7 — Create an Application Load Balancer

The load balancer sits in the public subnets and forwards traffic to your containers in the private subnets.

1. **EC2** console → **Load Balancers** → **Create load balancer** → **Application Load Balancer** → **Create**
2. **Name:** `iam-lab-alb`
3. **Scheme:** Internet-facing | **IP address type:** IPv4
4. **VPC:** `iam-lab-vpc`
5. **Availability Zones:** select both AZs → for each, pick the **public subnet** *(subnet name contains "public")*
6. **Security groups:** remove the default SG → add `iam-lab-alb-sg`
7. **Listeners and routing:** HTTP on port 80 → for Default action, click **Create target group** *(opens a new tab)*:
   - **Target type:** IP addresses
   - **Name:** `iam-lab-tg`
   - **Protocol:** HTTP | **Port:** `3000`
   - **VPC:** `iam-lab-vpc`
   - **Health check path:** `/health`
   - **Create target group** — don't register any targets (ECS will do this automatically)
8. Back on the ALB tab → refresh the target group dropdown → select `iam-lab-tg`
9. **Create load balancer**

---

## Step 8 — Create the ECS Cluster

1. **ECS** console → **Clusters** → **Create cluster**
2. **Cluster name:** `iam-lab-cluster`
3. **Infrastructure:** AWS Fargate *(serverless — no EC2 nodes to manage)*
4. **Create**

---

## Step 9 — Create the Task Definition

The task definition is the blueprint for your container: what image to run, what roles to use, what ports to open.

1. **ECS** → **Task definitions** → **Create new task definition**
2. **Family name:** `iam-lab-task`
3. **Infrastructure:** AWS Fargate | **CPU:** 0.25 vCPU | **Memory:** 0.5 GB
4. **Task role:** `ecs-lab-task-role` ← *your app's identity for S3/DynamoDB*
5. **Task execution role:** `ecs-lab-execution-role` ← *ECS's identity to pull the image*
6. Under **Container — Add container:**
   - **Name:** `app`
   - **Image URI:** copy from your ECR repo (click the repo name in ECR → copy the URI shown at the top, then append `:latest`)
   - **Container port:** `3000` | Protocol: TCP
   - **Log collection:** leave enabled → it will create a CloudWatch log group
   - **Environment variables — Add:**

     | Key            | Value              |
     | -------------- | ------------------ |
     | `S3_BUCKET`    | `iam-lab-yourname` |
     | `DYNAMO_TABLE` | `iam-lab-notes`    |
     | `AWS_REGION`   | `us-east-1`        |

7. **Create**

---

## Step 10 — Create the ECS Service

A Service ensures your task stays running and registers itself with the load balancer automatically.

1. Open cluster `iam-lab-cluster` → **Services** tab → **Create**
2. **Compute options:** Launch type → **Fargate**
3. **Task definition:** `iam-lab-task` (latest revision)
4. **Service name:** `iam-lab-service`
5. **Desired tasks:** `1`
6. **Networking:**
   - **VPC:** `iam-lab-vpc`
   - **Subnets:** select the **private subnets** *(subnet names contain "private")*
   - **Security group:** remove the default → add `iam-lab-ecs-sg`
   - **Public IP:** **DISABLED** *(tasks are hidden behind the load balancer)*
7. **Load balancing:**
   - **Load balancer type:** Application Load Balancer
   - **Load balancer:** `iam-lab-alb`
   - **Container to load balance:** select `app:3000`
   - **Listener:** use existing → `80:HTTP`
   - **Target group:** use existing → `iam-lab-tg`
8. **Create** — ⏳ wait ~2 minutes for the task to start and become healthy

---

## Step 11 — Open the App

1. **EC2** → **Load Balancers** → `iam-lab-alb` → copy the **DNS name** from the details panel
2. Open `http://<ALB-DNS-NAME>` in your browser 🎉

If it doesn't load yet, wait another minute and check that the target in `iam-lab-tg` shows **healthy**.

---

## Step 12 — Understand What Just Happened

Look at your running task: **ECS** → `iam-lab-cluster` → **Tasks** → click the task ID → **Configuration** tab.

You'll see:

- **Task role:** `ecs-lab-task-role` — used by your Node.js code
- **Task execution role:** `ecs-lab-execution-role` — used by ECS to start the task

The container is in a private subnet with no public IP. Traffic flows:

```txt
Browser → Internet Gateway → ALB (public subnet) → NAT → ECS Task (private subnet)
                                                          ↓
                                               S3 / DynamoDB / ECR (via NAT)
```

---

## 🔴 Break It: Task Role (app permissions)

1. **IAM** → `ecs-lab-task-role` → edit inline policy → delete the DynamoDB statement → **Save**
2. In the app → **Load Notes** → `AccessDeniedException` — the app shows exactly which action failed
3. Restore the policy → **Save** → try again → works immediately *(no restart needed)*

## 🔴 Break It: Execution Role (image pull)

1. **IAM** → `ecs-lab-execution-role` → edit your inline policy → remove `ecr:BatchGetImage` → **Save**
2. **ECS** → `iam-lab-cluster` → `iam-lab-service` → **Update service** → check **Force new deployment** → **Update**
3. Watch the new task in the **Tasks** tab — it will appear then immediately stop
4. Click the **stopped task** → scroll to **Stopped reason** → `CannotPullContainerError: ... is not authorized to perform: ecr:BatchGetImage`
5. Restore the permission → force another deployment → task starts successfully

> **The key difference:** A task role failure happens *while your code is running*. An execution role failure happens *before your container even starts*.

---

## 🧹 Cleanup

Do this in order to avoid dependency errors:

1. **ECS** → `iam-lab-service` → **Update** → set Desired tasks to `0` → Update → then **Delete service** → delete cluster
2. **EC2** → **Load Balancers** → delete `iam-lab-alb`
3. **EC2** → **Target Groups** → delete `iam-lab-tg`
4. **ECR** → delete `iam-lab-app` repository
5. **IAM** → delete `ecs-lab-task-role` and `ecs-lab-execution-role`
6. **VPC** → **NAT Gateways** → delete the NAT gateway → wait until deleted
7. **VPC** → **Elastic IPs** → release the IP that was used by the NAT gateway
8. **VPC** → **Your VPCs** → select `iam-lab-vpc` → **Actions** → **Delete VPC** *(deletes subnets, route tables, IGW automatically)*
9. **S3** → empty → delete bucket | **DynamoDB** → delete `iam-lab-notes`
