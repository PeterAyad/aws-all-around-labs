# 🛰 Lab — ECS Fargate + Task Execution Role

**What you'll learn:** ECS Fargate has a role that most students skip — the **task execution role**. It's not for your app. It's the identity ECS uses to pull your private image from ECR and write logs to CloudWatch *before your container even starts*. Without it, your task stays stuck in `PROVISIONING` forever. You'll build the full network from scratch and wire up this role from the console.

---

## Step 1 — Create the VPC

ECS Fargate tasks need a properly networked VPC. Tasks run in **private subnets** (no direct internet exposure), and a **NAT Gateway** gives them outbound internet access to reach ECR and CloudWatch.

1. Open the **VPC** console → **Your VPCs** → **Create VPC**
2. At the top, select **VPC and more** *(activates the full wizard — builds everything in one shot)*
3. Fill in the settings:

   | Setting                      | Value                                                   |
   | ---------------------------- | ------------------------------------------------------- |
   | Name tag                     | `mission-control-vpc`                                   |
   | IPv4 CIDR                    | `10.0.0.0/16`                                           |
   | Number of Availability Zones | `2`                                                     |
   | Number of public subnets     | `2`                                                     |
   | Number of private subnets    | `2`                                                     |
   | NAT gateways                 | **In 1 AZ** *(gives private subnets outbound internet)* |
   | VPC endpoints                | None                                                    |

4. Click **Create VPC** — ⏳ wait ~2 minutes for all resources to show **Created**
5. Click **View VPC** → go to **Subnets** and note down:
   - The **2 public subnet IDs** — names contain `public`
   - The **2 private subnet IDs** — names contain `private`

> ✅ The wizard created: 1 Internet Gateway (for public subnets), 1 NAT Gateway (so private subnets can reach ECR and CloudWatch outbound), and route tables wired up correctly for both.

---

## Step 2 — Create Security Groups

Two security groups: one for the load balancer (internet-facing), one for the containers (internal only).

### Security Group A — Load Balancer

1. **VPC** console → **Security groups** → **Create security group**
2. **Name:** `mission-control-alb-sg`
3. **VPC:** select `mission-control-vpc`
4. **Inbound rules** → **Add rule:**
   - Type: **HTTP** | Port: `80` | Source: `0.0.0.0/0`
5. **Create security group**

### Security Group B — ECS Tasks

1. **Create security group**
2. **Name:** `mission-control-ecs-sg`
3. **VPC:** select `mission-control-vpc`
4. **Inbound rules** → **Add rule:**
   - Type: **Custom TCP** | Port: `80` | Source: select **`mission-control-alb-sg`** from the dropdown
   *(Only the load balancer can reach the containers — nothing else)*
5. **Create security group**

---

## Step 3 — Push the Docker Image to ECR (Private)

### Create the ECR repository

1. **ECR** → **Private registry** → **Repositories** → **Create repository**
2. **Visibility:** Private | **Name:** `mission-control` → **Create repository**

### Build and push

1. Click into `mission-control` → **View push commands**
2. Follow the 4 commands shown in your terminal
3. Confirm the `latest` tag appears in the repository

> The image is **private**. No node can pull it without the correct IAM permissions. This is exactly why the node role exists.

---

## Step 4 — Create the Task Execution Role 🔐

This is the heart of the lab. The task execution role is used by **ECS infrastructure** — not your app code. ECS assumes this role to do two things before your container starts: authenticate to ECR and pull your private image, and create a CloudWatch log stream.

1. Open **IAM** → **Roles** → **Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** scroll down → find **Elastic Container Service** → select **Elastic Container Service Task** → **Next**
4. Search for and attach: `AmazonECSTaskExecutionRolePolicy` *(AWS-managed policy)* → **Next**
5. **Role name:** `mission-control-execution-role` → **Create role**

Now add an explicit inline policy so you can see the exact ECR permissions being granted:

1. Click into `mission-control-execution-role` → **Add permissions** → **Create inline policy** → **JSON** tab
2. Paste the following:

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
               "Resource": "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/mission-control"
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

3. Replace `<REGION>` and `<ACCOUNT_ID>` with your values
4. **Policy name:** `mission-control-execution-policy` → **Create policy**

> **Why `ecr:GetAuthorizationToken` uses `Resource: "*"`:** This is a global API call — it returns a Docker login token for your whole registry. There's no specific resource ARN to scope it to. The actual image pull actions (`BatchGetImage`, etc.) are scoped to your specific repository.

---

## Step 5 — Create the ECS Cluster

1. Open **ECS** console → **Clusters** → **Create cluster**
2. **Cluster name:** `mission-control-cluster`
3. **Infrastructure:** AWS Fargate *(serverless — no EC2 nodes to manage)*
4. Leave all other settings default → **Create**
5. Wait ~1 minute for the cluster to show **Active**

---

## Step 6 — Create the Task Definition

The task definition is the blueprint: what image to run, what roles to use, what ports to open.

1. **ECS** → **Task definitions** → **Create new task definition**
2. **Family name:** `mission-control-task`
3. **Infrastructure requirements:**
   - Launch type: `AWS Fargate`
   - OS: `Linux/X86_64`
   - CPU: `0.25 vCPU`
   - Memory: `0.5 GB`
4. **Task execution role:** select `mission-control-execution-role` ← *ECS uses this to pull the image*
5. Leave **Task role** empty *(our app doesn't call any AWS services — it's a static dashboard)*
6. Under **Container — 1:**
   - **Name:** `mission-control`
   - **Image URI:** paste your ECR URI from Step 3 (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/mission-control:latest`)
   - **Container port:** `80` | Protocol: TCP
   - **Log collection:** leave **enabled** → ECS will create a CloudWatch log group automatically
7. Scroll to **HealthCheck:**
   - Command: `CMD-SHELL, wget -qO- http://localhost/health || exit 1`
   - Interval: `30` | Timeout: `5` | Start period: `10` | Retries: `3`
8. Click **Create**

---

## Step 7 — Create the Application Load Balancer

The load balancer sits in the **public subnets** and forwards traffic to containers in the **private subnets**.

### Create the Target Group first

1. **EC2** → **Target Groups** → **Create target group**
2. **Target type:** IP addresses
3. **Name:** `mission-control-tg`
4. **Protocol:** HTTP | **Port:** `80`
5. **VPC:** select `mission-control-vpc`
6. **Health check path:** `/health`
7. Click **Next** → skip registering targets → **Create target group**

### Create the Load Balancer

1. **EC2** → **Load Balancers** → **Create load balancer** → **Application Load Balancer** → **Create**
2. **Name:** `mission-control-alb`
3. **Scheme:** Internet-facing | **IP address type:** IPv4
4. **VPC:** `mission-control-vpc`
5. **Availability Zones:** select both AZs → for each, pick the **public subnet** *(name contains "public")*
6. **Security groups:** remove the default → add `mission-control-alb-sg`
7. **Listeners and routing:** HTTP on port `80` → **Default action:** Forward to → select `mission-control-tg`
8. **Create load balancer** — ⏳ wait ~2 minutes for state to show **Active**
9. Copy the **DNS name** from the details panel — you'll open the app with this

---

## Step 8 — Create the ECS Service

A Service keeps your task running and registers it with the load balancer automatically.

1. **ECS** → **Clusters** → click `mission-control-cluster` → **Services** tab → **Create**
2. **Compute options:** Launch type → **Fargate**
3. **Task definition:** `mission-control-task` (latest revision)
4. **Service name:** `mission-control-service`
5. **Desired tasks:** `2`
6. **Networking:**
   - **VPC:** `mission-control-vpc`
   - **Subnets:** select the **2 private subnets** *(names contain "private")*
   - **Security group:** remove the default → add `mission-control-ecs-sg`
   - **Public IP:** **DISABLED** *(tasks are hidden behind the load balancer — they use NAT to reach ECR outbound)*
7. **Load balancing:**
   - **Load balancer type:** Application Load Balancer
   - **Load balancer:** `mission-control-alb`
   - **Listener:** use existing → `80:HTTP`
   - **Target group:** use existing → `mission-control-tg`
8. **Create** — ⏳ wait ~2 minutes for tasks to start and the target group to show **healthy**

---

## Step 9 — Open the App

1. **EC2** → **Load Balancers** → `mission-control-alb` → copy the **DNS name**
2. Open `http://<ALB-DNS-NAME>` in your browser 🎉

The **Mission Control Dashboard** loads — the platform badge shows **ECS**.

If it doesn't load yet, wait another minute and check: **EC2** → **Target Groups** → `mission-control-tg` → **Targets** tab → both targets should show **healthy**.

---

## Step 10 — Understand What Just Happened

Go to **ECS** → `mission-control-cluster` → **Tasks** → click the running task ID → **Configuration** tab.

You'll see:

- **Task execution role:** `mission-control-execution-role` — used by ECS to start the task
- **Task role:** *(empty)* — our app doesn't need to call any AWS services

Traffic flow through the architecture:

```txt
Browser
  → Internet Gateway
    → ALB (public subnet, port 80)
      → ECS Task (private subnet, port 80)

ECS Task startup (outbound via NAT Gateway):
  → ECR (to pull the container image)
  → CloudWatch Logs (to stream container output)
```

The container never has a public IP. All outbound AWS API calls leave through the NAT Gateway.

---

## 🔴 Break It: Remove the ECR pull permission

Watch what happens when ECS can't pull the image.

1. **IAM** → click `mission-control-execution-role` → **Permissions** tab → click `mission-control-execution-policy` → **Edit**
2. Delete the entire `ECRPullImage` statement (the one with `ecr:BatchGetImage`) → **Save**
3. **ECS** → `mission-control-cluster` → `mission-control-service` → **Update service** → check **Force new deployment** → **Update**
4. Watch the **Tasks** tab — a new task will appear and then immediately stop
5. Click the **stopped task** → scroll to **Stopped reason:**

   ```txt
   CannotPullContainerError: ... is not authorized to perform: ecr:BatchGetImage
   ```

6. Restore the permission → **Save** → force another deployment → the new task starts successfully

> The execution role failure happens **before your container even starts** — not while it's running. The task stops at the image pull stage. Your running tasks are unaffected until they're replaced.

## 🔴 Break It: Remove the CloudWatch Logs permission

Watch what happens when ECS can't set up the log stream.

1. **IAM** → `mission-control-execution-role` → `mission-control-execution-policy` → **Edit**
2. Delete the entire `CloudWatchLogs` statement → **Save**
3. Force a new deployment (same as above)
4. Watch the stopped task → **Stopped reason:**

   ```txt
   CannotStartLogging: ... is not authorized to perform: logs:CreateLogGroup
   ```

5. Restore the permission → force another deployment → works

> This fails at log driver initialization — also before your code runs. ECS validates both ECR access and log destination before marking a task as running.

---

## Explore: View Live Container Logs

1. **ECS** → `mission-control-cluster` → **Services** → `mission-control-service` → **Tasks** tab
2. Click a running task → **Logs** tab
3. You see nginx access logs streaming live from inside the container
4. Refresh the dashboard in your browser — watch new log entries appear in real time

These logs are written to **CloudWatch Logs** — which only works because the execution role has `logs:PutLogEvents` permission.

## Explore: Scale the Service

1. **ECS** → `mission-control-service` → **Update service**
2. Change **Desired tasks** to `3` → **Update**
3. Watch a third task launch and register as healthy in the **Tasks** tab

## Explore: Force a Rolling Deployment

1. **ECS** → `mission-control-service` → **Update service**
2. Check **Force new deployment** → **Update**
3. ECS replaces all tasks one by one — old tasks drain, new tasks start — zero downtime

---

## 🧹 Cleanup

Run in this order to avoid dependency errors:

1. **ECS** → `mission-control-service` → **Update** → set Desired tasks to `0` → **Update** → then **Delete service**
2. **ECS** → **Clusters** → `mission-control-cluster` → **Delete cluster**
3. **EC2** → **Load Balancers** → delete `mission-control-alb`
4. **EC2** → **Target Groups** → delete `mission-control-tg`
5. **EC2** → **Security Groups** → delete `mission-control-ecs-sg`, then `mission-control-alb-sg`
6. **ECS** → **Task definitions** → `mission-control-task` → select all revisions → **Deregister**
7. **ECR** → select `mission-control` → **Delete repository**
8. **IAM** → **Roles** → delete `mission-control-execution-role`
9. **VPC** → **NAT Gateways** → delete the NAT gateway → ⏳ wait until **Deleted**
10. **VPC** → **Elastic IPs** → release the IP that was attached to the NAT gateway
11. **VPC** → select `mission-control-vpc` → **Actions** → **Delete VPC** *(deletes subnets, route tables, and IGW automatically)*

---

## Key Concepts Covered

| Concept                                           | Where You Saw It |
| ------------------------------------------------- | ---------------- |
| VPC with public + private subnets                 | Step 1           |
| NAT Gateway for private subnet outbound access    | Step 1           |
| Security groups (ALB + ECS task)                  | Step 2           |
| Private ECR repository                            | Step 3           |
| Task execution role — what it is and why          | Step 4           |
| Inline IAM policy with scoped ECR permissions     | Step 4           |
| ECS cluster (Fargate)                             | Step 5           |
| Task definition — execution role vs task role     | Step 6           |
| ALB target group + health check                   | Step 7           |
| ECS Service in private subnets                    | Step 8           |
| Execution role failure → CannotPullContainerError | Break It #1      |
| Execution role failure → CannotStartLogging       | Break It #2      |
| Live container logs via CloudWatch                | Explore          |
| Horizontal scaling                                | Explore          |
| Rolling deployment                                | Explore          |
