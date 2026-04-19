# AWS VPC Lab — Phase 2: Application Load Balancer + Auto Scaling Group

A self-contained lab that teaches production-grade AWS architecture. You configure the infrastructure entirely through the AWS Console — no manual SSH into backend servers. Instances launch, configure themselves, and register with the load balancer automatically.

---

## Architecture Overview

```txt
                        Internet (HTTP :80)
                               │
                               ▼
                 ┌─────────────────────────┐
                 │  Application Load       │  ← Public Subnets (2 AZs)
                 │  Balancer  (AWS-managed)│    Note: add ACM cert here for HTTPS
                 └────┬──────────────┬─────┘
                      │              │
             /* (frontend)    /api/* (backend)
                      │              │
                      ▼              ▼
          ┌──────────────────┐  ┌─────────────────────────┐
          │  Frontend ASG    │  │  Backend ASG            │
          │  (Nginx, static) │  │  (Node.js :3000)        │
          │  Private Subnet  │  │  Private Subnet         │
          └──────────────────┘  └──────────┬──────────────┘
                                           │
                                           ▼
                                ┌───────────────────────┐
                                │  RDS PostgreSQL       │  ← Isolated Private Subnet
                                │  Port 5432            │    SG: only backend SG allowed
                                └───────────────────────┘
```

**How it works end-to-end:**

1. A browser request hits the **ALB** on port 80
2. The ALB checks the path: `/*` goes to the frontend target group, `/api/*` goes to the backend target group
3. The **frontend** is a static Nginx site — it serves the HTML/JS app with zero configuration
4. The app makes API calls using relative `/api/*` URLs, which go back through the **same ALB** and get routed to a healthy backend instance
5. The **backend** instances are launched automatically by an ASG using a Launch Template with a User Data script — no SSH required
6. Each backend connects to a **shared RDS PostgreSQL** database

> **Adding HTTPS:** In a production setup you would attach an ACM certificate to the ALB listener on port 443 and add a redirect rule from port 80 → 443. The rest of the architecture stays identical.

---

## What You Will Build

| Resource                  | Count     | Purpose                                                        |
| ------------------------- | --------- | -------------------------------------------------------------- |
| VPC                       | 1         | Isolated network for the lab                                   |
| Public Subnets            | 2 (2 AZs) | ALB — AWS requires subnets in 2 AZs                            |
| Private Subnets           | 2 (2 AZs) | EC2 instances and RDS                                          |
| Internet Gateway          | 1         | Outbound internet for public subnets                           |
| NAT Gateway               | 1         | Outbound internet for private subnets (for User Data installs) |
| Security Groups           | 4         | ALB, frontend, backend, RDS                                    |
| S3 Bucket                 | 1         | Hosts the frontend static app file                             |
| IAM Roles + Profiles      | 2         | Allows frontend to read S3, and both to use Systems Manager    |
| RDS PostgreSQL            | 1         | Shared database for all backend nodes                          |
| Launch Template           | 2         | One for frontend, one for backend                              |
| Target Group              | 2         | One for frontend, one for backend                              |
| Application Load Balancer | 1         | Routes traffic by path                                         |
| Auto Scaling Group        | 2         | Manages frontend and backend instances                         |

---

## Step 0 — Prepare the User Data Scripts

Before touching the AWS Console, edit both User Data scripts on your local machine.

**Backend script** — open your backend user data script and replace the placeholder on this line near the top:

```bash
DB_CONNECTION_STRING="postgresql://postgres:postgres@REPLACE_WITH_YOUR_RDS_ENDPOINT:5432/postgres?sslmode=verify-full&sslrootcert=/tmp/global-bundle.pem"
```

You do not have your RDS endpoint yet — that is fine. **Leave this file open**. You will fill in the endpoint after creating RDS in Step 3, then paste the full script into the Launch Template in Step 6.

**Frontend script** — open your frontend user data script and replace the placeholder on this line near the top:

```bash
S3_PATH="s3://REPLACE_WITH_YOUR_BUCKET_NAME/index.html"
```

You do not have your bucket name yet either — leave this file open. You will fill it in after creating the S3 bucket in Step 5.

---

## Step 1 — Create the VPC

Go to **VPC → Create VPC** and select **VPC and more**.

| Field                        | Value         |
| ---------------------------- | ------------- |
| Name tag                     | `lab`         |
| IPv4 CIDR                    | `10.0.0.0/16` |
| Number of Availability Zones | `2`           |
| Number of public subnets     | `2`           |
| Number of private subnets    | `2`           |
| NAT gateways                 | `In 1 AZ`     |
| VPC endpoints                | `None`        |

Click **Create VPC** and wait for all resources to be created (~1 minute).

This creates: the VPC, 2 public subnets, 2 private subnets, an internet gateway, a NAT gateway, and the associated route tables — all in one step.

> **Note the subnet IDs** after creation. You will need to select them when creating the ALB and ASGs.

---

## Step 2 — Create Security Groups

Go to **VPC → Security Groups → Create security group** for each of the following. All four belong to the `lab-vpc` you just created.

### ALB SG (`lab-alb-sg`)

| Direction | Type        | Port | Source      |
| --------- | ----------- | ---- | ----------- |
| Inbound   | HTTP        | 80   | `0.0.0.0/0` |
| Outbound  | All traffic | All  | `0.0.0.0/0` |

### Frontend SG (`lab-frontend-sg`)

| Direction | Type        | Port | Source       |
| --------- | ----------- | ---- | ------------ |
| Inbound   | HTTP        | 80   | `lab-alb-sg` |
| Outbound  | All traffic | All  | `0.0.0.0/0`  |

### Backend SG (`lab-backend-sg`)

| Direction | Type        | Port | Source       |
| --------- | ----------- | ---- | ------------ |
| Inbound   | Custom TCP  | 3000 | `lab-alb-sg` |
| Outbound  | All traffic | All  | `0.0.0.0/0`  |

### RDS SG (`lab-rds-sg`)

| Direction | Type        | Port | Source           |
| --------- | ----------- | ---- | ---------------- |
| Inbound   | PostgreSQL  | 5432 | `lab-backend-sg` |
| Outbound  | All traffic | All  | `0.0.0.0/0`      |

> Notice that the RDS security group only allows traffic from `lab-backend-sg` — not from the internet or any other source. This is proper security group chaining.

---

## Step 3 — Create the RDS Database

Go to **RDS → Create database**.

| Field                  | Value                                    |
| ---------------------- | ---------------------------------------- |
| Creation method        | Standard create (**Full Configuration**) |
| Engine                 | PostgreSQL                               |
| Engine version         | PostgreSQL 15                            |
| Template               | Free tier                                |
| DB instance identifier | `lab-db`                                 |
| Master username        | `postgres`                               |
| Master password        | `postgres`                               |
| DB instance class      | `db.t3.micro`                            |
| Storage                | `20 GiB gp2`                             |
| VPC                    | `lab-vpc`                                |
| DB subnet group        | Create a new one                         |
| Public access          | **No**                                   |
| VPC security group     | Remove default, add `lab-rds-sg`         |
| Initial database name  | `postgres`                               |
| Automated backups      | Disabled (for the lab)                   |

Click **Create database** and wait for the status to become **Available** (~5–10 minutes).

Once available, go to the database → **Connectivity & Security** → copy the **Endpoint** hostname. Update your backend user data script with the full connection string:

```txt
postgresql://postgres:postgres@lab-db.xxxxxxxxx.us-east-1.rds.amazonaws.com:5432/postgres?sslmode=verify-full&sslrootcert=/tmp/global-bundle.pem
```

---

## Step 4 — Create the S3 Bucket and IAM Roles

The frontend User Data script downloads `index.html` from S3 at boot. Also, since we aren't using SSH, we need IAM roles that allow AWS Systems Manager (SSM) to connect to the instances so we can check logs.

### Create the S3 Bucket

Go to **S3 → Create bucket**.

| Field                   | Value                                                           |
| ----------------------- | --------------------------------------------------------------- |
| Bucket name             | `lab-frontend-assets-<your-initials>` (must be globally unique) |
| Region                  | Same region as your VPC                                         |
| Block all public access | **Enabled** (keep default — EC2 reads via IAM, not public URL)  |

Click **Create bucket**.

Go into the bucket and click **Upload**. Upload the `index.html` file included with this lab. Once uploaded you will see it listed in the bucket.

Now update your frontend user data script with your bucket name:

```bash
S3_PATH="s3://lab-frontend-assets-<your-initials>/index.html"
```

### Create the Frontend IAM Role

Go to **IAM → Roles → Create role**.

**Step 1:** Trusted entity type: **AWS service**, Use case: **EC2**. Click **Next**.
**Step 2:** Search for and select **both** of these policies:

* `AmazonS3ReadOnlyAccess`
* `AmazonSSMManagedInstanceCore`
Click **Next**.
**Step 3:** Name the role `lab-frontend-role`. Click **Create role**.

### Create the Backend IAM Role

Go to **IAM → Roles → Create role**.

**Step 1:** Trusted entity type: **AWS service**, Use case: **EC2**. Click **Next**.
**Step 2:** Search for and select this policy:

* `AmazonSSMManagedInstanceCore`
Click **Next**.
**Step 3:** Name the role `lab-backend-role`. Click **Create role**.

*(AWS automatically creates matching instance profiles with the same names — you will select them in the Launch Templates).*

---

## Step 5 — Create Target Groups

You need two target groups before creating the ALB.

Go to **EC2 → Target Groups → Create target group**.

### Backend Target Group

| Field               | Value            |
| ------------------- | ---------------- |
| Target type         | Instances        |
| Name                | `lab-backend-tg` |
| Protocol            | HTTP             |
| Port                | `3000`           |
| VPC                 | `lab-vpc`        |
| Health check path   | `/health`        |
| Healthy threshold   | `2`              |
| Unhealthy threshold | `2`              |
| Interval            | `10` seconds     |

Click **Next** then **Create target group** (do not register targets manually).

### Frontend Target Group

| Field               | Value             |
| ------------------- | ----------------- |
| Target type         | Instances         |
| Name                | `lab-frontend-tg` |
| Protocol            | HTTP              |
| Port                | `80`              |
| VPC                 | `lab-vpc`         |
| Health check path   | `/`               |
| Healthy threshold   | `2`               |
| Unhealthy threshold | `2`               |
| Interval            | `10` seconds      |

Click **Next** then **Create target group**.

---

## Step 6 — Create the Application Load Balancer

Go to **EC2 → Load Balancers → Create load balancer → Application Load Balancer**.

| Field              | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| Name               | `lab-alb`                                                    |
| Scheme             | Internet-facing                                              |
| IP address type    | IPv4                                                         |
| VPC                | `lab-vpc`                                                    |
| Availability Zones | Select **both** AZs and choose the **public** subnet in each |
| Security groups    | Remove default, add `lab-alb-sg`                             |

Under **Listeners and routing**:

| Protocol | Port | Default action               |
| -------- | ---- | ---------------------------- |
| HTTP     | 80   | Forward to `lab-frontend-tg` |

Click **Create load balancer** and wait for the state to become **Active** (~2 minutes).

Once active, go to the ALB → **Listeners** tab → click the HTTP:80 listener → **Add rule**.

Add a rule to route API traffic to the backend:

| Setting   | Value                       |
| --------- | --------------------------- |
| Rule name | `backend-api`               |
| Condition | Path is `/api/*`            |
| Action    | Forward to `lab-backend-tg` |
| Priority  | `1`                         |

Save the rule. The default rule (lower priority) continues to forward everything else to `lab-frontend-tg`.

> Copy the **ALB DNS name** (e.g. `lab-alb-1234567890.us-east-1.elb.amazonaws.com`) — this is your app's URL.

---

## Step 7 — Create Launch Templates

### Backend Launch Template

Go to **EC2 → Launch Templates → Create launch template**.

| Field           | Value                                                             |
| --------------- | ----------------------------------------------------------------- |
| Name            | `lab-backend-lt`                                                  |
| Description     | `Backend API node`                                                |
| AMI             | Amazon Linux 2023 (64-bit x86)                                    |
| Instance type   | `t3.micro`                                                        |
| Key pair        | Select your key pair (optional — you can reach instances via SSM) |
| Security groups | `lab-backend-sg`                                                  |

Scroll to **Advanced details** and configure two more fields:

**IAM instance profile** — select `lab-backend-role`. This grants SSM permissions.

**User data** — paste the entire contents of your edited backend user data script.

Click **Create launch template**.

### Frontend Launch Template

Go to **EC2 → Launch Templates → Create launch template**.

| Field           | Value                           |
| --------------- | ------------------------------- |
| Name            | `lab-frontend-lt`               |
| Description     | `Frontend static server`        |
| AMI             | Amazon Linux 2023 (64-bit x86)  |
| Instance type   | `t3.micro`                      |
| Key pair        | Select your key pair (optional) |
| Security groups | `lab-frontend-sg`               |

Scroll to **Advanced details** and configure two more fields:

**IAM instance profile** — select `lab-frontend-role`. This gives the EC2 instance permission to download `index.html` from S3, as well as SSM permissions.

**User data** — paste the entire contents of your edited frontend user data script.

Click **Create launch template**.

---

## Step 8 — Create Auto Scaling Groups

### Backend ASG

Go to **EC2 → Auto Scaling Groups → Create Auto Scaling group**.

**Step 1 — Launch template:**

| Field           | Value             |
| --------------- | ----------------- |
| Name            | `lab-backend-asg` |
| Launch template | `lab-backend-lt`  |

**Step 2 — Instance launch options:**

| Field   | Value                           |
| ------- | ------------------------------- |
| VPC     | `lab-vpc`                       |
| Subnets | Select both **private** subnets |

**Step 3 — Advanced options:**

| Field                     | Value                               |
| ------------------------- | ----------------------------------- |
| Load balancing            | Attach to an existing load balancer |
| Target groups             | `lab-backend-tg`                    |
| Health check              | Turn on ELB health checks           |
| Health check grace period | `90` seconds                        |

**Step 4 — Group size:**

| Field   | Value |
| ------- | ----- |
| Desired | `2`   |
| Minimum | `1`   |
| Maximum | `4`   |

Skip steps 5 and 6. Click **Create Auto Scaling group**.

### Frontend ASG

Repeat the same steps with these values:

| Field               | Value                    |
| ------------------- | ------------------------ |
| Name                | `lab-frontend-asg`       |
| Launch template     | `lab-frontend-lt`        |
| Subnets             | Both **private** subnets |
| Target groups       | `lab-frontend-tg`        |
| Desired / Min / Max | `1` / `1` / `2`          |

---

## Step 9 — Open the App

Both ASGs will immediately start launching instances. The User Data scripts run on first boot (~2–3 minutes). Monitor progress at:

**EC2 → Target Groups → lab-backend-tg → Targets.**

Wait until at least one backend instance shows **healthy** and at least one frontend instance shows **healthy**.

Then open your browser:

```txt
http://<ALB_DNS_NAME>
```

The **ASG Dashboard** opens by default. Instance cards appear as the ALB discovers each node.

---

## Proving Load Balancing Works

### Method 1 — Generate Load

Click **⚡ Generate load** on the ASG Dashboard. Watch the instance cards flash as different backend nodes receive requests and the hit counts climb.

### Method 2 — Book Catalog

Switch to the **Book Catalog** tab. The **Served by** column on each row shows the EC2 instance ID that handled the request. Reload the page several times — the instance ID changes as the ALB round-robins across your backend nodes.

### Method 3 — curl

```bash
for i in {1..10}; do
  curl -s http://<ALB_DNS_NAME>/api/books | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('servedBy','?'))"
done
```

---

## Simulating Failures and Scaling

### Scale the backend up

Go to **EC2 → Auto Scaling Groups → lab-backend-asg → Edit**. Change Desired from `2` to `3`. The ASG launches a new instance, User Data runs automatically, and the new node appears in the dashboard within 90 seconds.

### Scale the backend down

Change Desired back to `2`. The ASG terminates one instance gracefully — the ALB drains its connections first.

### Terminate an instance manually (self-healing demo)

Go to **EC2 → Instances**, select a backend instance, and terminate it. The ASG detects the loss and automatically replaces it. This is **self-healing** — the desired count is always maintained.

### Force an ALB health check failure

Go to **EC2 → Target Groups → lab-backend-tg → Targets**. Select a target and click **Deregister**. Traffic stops going to it immediately. Re-register to restore it.

### Database unreachable

Go to **VPC → Security Groups → lab-rds-sg** and delete the inbound rule on port 5432. The backend instances remain running but report `database: error` in the dashboard. This is an important teaching point: **the ALB health check only tests what you configure it to test.** The `/health` endpoint only checks that Node.js is running — not database connectivity. In production you would decide deliberately what your health check covers.

Restore the security group rule to recover.

---

## Checking Logs

Since there is no SSH in the normal lab flow, use **SSM Session Manager** to access instances without a key pair:

Go to **EC2 → Instances → select an instance → Connect → Session Manager**.

```bash
# Backend instance — view init log
sudo cat /var/log/lab-backend-init.log

# Backend instance — live service logs
sudo journalctl -u lab-backend -f

# Frontend instance — view init log
sudo cat /var/log/lab-frontend-init.log

# Frontend instance — Nginx error log
sudo tail -f /var/log/nginx/lab-error.log
```

---

## Application Files

| Instance type | Path                              | Description                          |
| ------------- | --------------------------------- | ------------------------------------ |
| Backend       | `/opt/lab/backend/server.js`      | Express REST API                     |
| Backend       | `/opt/lab/backend/.env`           | DB connection string + port          |
| Backend       | `/var/log/lab-backend-init.log`   | User Data execution log              |
| Frontend      | `/usr/share/nginx/lab/index.html` | Static SPA (ASG dashboard + catalog) |
| Frontend      | `/etc/nginx/conf.d/lab.conf`      | Nginx config                         |
| Frontend      | `/var/log/lab-frontend-init.log`  | User Data execution log              |

---

## API Reference

All backend endpoints are available via the ALB at `http://<ALB_DNS_NAME>`:

| Method | Path             | Description                                               |
| ------ | ---------------- | --------------------------------------------------------- |
| GET    | `/health`        | Fast health check for the ALB (200 if Node.js is running) |
| GET    | `/api/health`    | Full status including DB connectivity and instance ID     |
| GET    | `/api/books`     | List all books — response includes `servedBy` instance ID |
| POST   | `/api/books`     | Create a book                                             |
| PUT    | `/api/books/:id` | Update a book                                             |
| DELETE | `/api/books/:id` | Delete a book                                             |

---

## Cleanup

Delete resources in this order to avoid dependency errors:

1. **Auto Scaling Groups** — delete `lab-backend-asg` and `lab-frontend-asg` (this terminates all EC2 instances)
2. **Application Load Balancer** — delete `lab-alb`
3. **Target Groups** — delete `lab-backend-tg` and `lab-frontend-tg`
4. **Launch Templates** — delete `lab-backend-lt` and `lab-frontend-lt`
5. **RDS instance** — delete `lab-db` (disable final snapshot for the lab)
6. **NAT Gateway** — delete it and wait for status to change to Deleted
7. **Elastic IP** — release the EIP that was allocated for the NAT Gateway
8. **VPC** — delete `lab-vpc` (this removes subnets, route tables, IGW, and security groups)
