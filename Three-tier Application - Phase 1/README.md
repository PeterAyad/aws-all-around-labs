# AWS VPC Lab — Phase 1: 3-Tier Application

A hands-on lab for learning how to set up a 3-tier architecture in AWS using the console — no code writing required. You run one script per server and the application configures itself.

---

## Architecture Overview

```txt
Internet
    │
    ▼
┌──────────────────────────────┐   Public Subnet
│  Frontend EC2 (Amazon Linux) │  ← Port 80 (Nginx → Node.js :8080)
└──────────────┬───────────────┘
               │ Private network
               ▼
┌──────────────────────────────┐   Private Subnet
│  Backend EC2 (Amazon Linux)  │  ← Port 3000 (Node.js / Express)
└──────────────┬───────────────┘
               │ Private network
               ▼
┌──────────────────────────────┐   Private Subnet
│  PostgreSQL (RDS or EC2)     │  ← Port 5432
└──────────────────────────────┘
```

The frontend app shows you the live health of each tier in real time — if the backend is unreachable, or if the backend can't reach the database, the UI tells you clearly without crashing.

---

## What the App Does

A **Book Catalog** with full CRUD operations on PostgreSQL:

- **Create** — Add a new book (title, author, year, genre, rating, notes)
- **Read** — Browse all books with live search and genre filter
- **Update** — Edit any book via a pre-filled modal
- **Delete** — Remove a book with a confirmation prompt

The table auto-seeds with 4 sample books on first launch.

---

## Prerequisites

Before running any scripts, complete these steps in the AWS Console:

### 1. Create a VPC and Subnets

- Go to **VPC → Create VPC**
- Select **VPC and more**
- Name: `lab-vpc`
- IPv4 CIDR: `10.0.0.0/16`
- Select **1 AZ** with **1 public subnet** and **1 private subnet**
- Select **Zonal** NAT gateway **In 1 AZ**
- No **VPC Endpoints** are needed
- Create VPC

### 2. Create Security Groups

- Go to **VPC → Security Groups**
- Create security group
- Add the security rules

**Frontend SG** (`lab-frontend-sg`), VPC: `lab-vpc`:

| Direction | Type        | Port | Source      |
| --------- | ----------- | ---- | ----------- |
| Inbound   | HTTP        | 80   | `0.0.0.0/0` |
| Inbound   | SSH         | 22   | Your IP     |
| Outbound  | All traffic | All  | `0.0.0.0/0` |

**Backend SG** (`lab-backend-sg`), VPC: `lab-vpc`:

| Direction | Type        | Port | Source                    |
| --------- | ----------- | ---- | ------------------------- |
| Inbound   | Custom TCP  | 3000 | `lab-frontend-sg`         |
| Inbound   | SSH         | 22   | Your IP (or a bastion SG) |
| Outbound  | All traffic | All  | `0.0.0.0/0`               |

### 3. Launch EC2 Instances

**Backend EC2:**

- AMI: Amazon Linux 2023
- Instance type: `t3.micro`
- Network: `lab-vpc` / `lab-private-subnet`
- Security group: `lab-backend-sg`
- Auto-assign public IP: **Disabled**
- Tag Name: `lab-backend`

**Frontend EC2:**

- AMI: Amazon Linux 2023
- Instance type: `t3.micro`
- Network: `lab-vpc` / `lab-public-subnet`
- Security group: `lab-frontend-sg`
- Auto-assign public IP: **Enabled**
- Tag Name: `lab-frontend`

### 4. Set Up the Database

- Go to **RDS → Create database (full configuration)**
- Template: Free tier
- Select **Single-AZ DB instance deployment**
- Engine: PostgreSQL, Version: 15
- DB identifier: `labdb`
- Master username: `postgres`, set a password (for the lab use `postgres`)
- For the authentication, select `Password authentication` for simplicity
- VPC: `lab-vpc`, Subnet group: create one using `lab-private-subnet`
- In additional configuration: Set initial database name as `postgres`
- Use the default values for the rest of the settings and create the DB
- After the db creation finishes, go to the DB configuration page > **Connectivity & Security**
- Under **Security group rules** open the **Security group** with type `EC2 Security Group - Inbound`
- Add to the inbound rules:

| Direction | Type | Port | Source      |
| --------- | ---- | ---- | ----------- |
| Inbound   | TCP  | 5432 | `0.0.0.0/0` |

---

## Lab Steps

### Step 0 — Access The instances

To fully setup the application, you need:

1. DB Connection String
   1. In the RDS DB, you just created, go to **Connectivity & Security** > **Endpoints**
   2. Build the connection string be replacing your variables in this format `postgresql://USERNAME:PASSWORD@DB_ENDPOINT:5432/postgres?sslmode=verify-full&sslrootcert=/home/ec2-user/global-bundle.pem`
2. Private EC2 (backend instance) IP
3. public EC2 (frontend instance) IP

To access the EC2 instances using SSH:

1. Set the SSH key permission `chmod 400 ./ec2-ssh.pem`
2. Copy the SSH key file to the public EC2 instance `scp -i ./ec2-ssh.pem ./ec2-ssh.pem ec2-user@<EC2-Public-IP>:~/`
3. SSH into the frontend EC2 `ssh -i ./ec2-ssh.pem ec2-user@<EC2-Public-IP>`
4. Set the SSH key permission `chmod 400 ./ec2-ssh.pem`
5. SSH into the backend EC2 `ssh -i ./ec2-ssh.pem ec2-user@<EC2-Private-IP>`
6. Now install the SSH key to RDS using this command `curl -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`
7. Now you can access both machines

### Step 1 - Copying the files

To copy the files to both EC2 instances, copy them to the public instance first then to the private instance through the public instance

```bash
scp -i ./ec2-ssh.pem ./setup-backend.sh ./setup-frontend.sh ec2-user@<EC2-Public-IP>:~/
ssh -i ./ec2-ssh.pem ec2-user@<EC2-Public-IP>
scp -i ./ec2-ssh.pem ./setup-backend.sh ec2-user@<EC2-Private-IP>:~/
```

### Step 2 — Set up the Backend

SSH into the backend EC2 and run:

```bash
chmod +x setup-backend.sh
./setup-backend.sh
```

The script will ask for:

1. **PostgreSQL connection string**
2. **Backend port** — press Enter to accept default `3000`

**Verify it worked:**

```bash
curl http://localhost:3000/api/health
# Should return: {"status":"ok","backend":true,"database":true,...}
```

---

### Step 3 — Set up the Frontend

SSH into the frontend EC2 and run:

```bash
chmod +x setup-frontend.sh
./setup-frontend.sh
```

The script will ask for:

1. **Backend private IP** — paste the IP from Step 1
2. **Backend port** — press Enter to accept default `3000`

When it finishes, it will print the frontend public IP.

---

### Step 3 — Open the App

Open your browser and go to:

```txt
http://<FRONTEND_PUBLIC_IP>
```

You should see the Book Catalog with a green **"All systems OK"** status pill in the header.

---

## Verifying Each Tier

The header status pill shows the current state and updates every 30 seconds. Click it to open the status panel showing individual tier health.

**To simulate a failure (good for learning):**

| Scenario             | How to trigger                                                         | Expected UI                      |
| -------------------- | ---------------------------------------------------------------------- | -------------------------------- |
| Backend unreachable  | Stop the `lab-backend` service or block port 3000 in the SG            | Red banner + "Backend down"      |
| Database unreachable | Change the backend's DB connection string or block port 5432 in the SG | Yellow banner + "DB unreachable" |
| Full recovery        | Restore the service or SG rule                                         | Green "All systems OK"           |

Stop/start the backend service:

```bash
sudo systemctl stop lab-backend
sudo systemctl start lab-backend
```

---

## Service Management

On the **backend EC2:**

```bash
sudo systemctl status lab-backend
sudo systemctl restart lab-backend
sudo journalctl -u lab-backend -f          # live logs
```

On the **frontend EC2:**

```bash
sudo systemctl status lab-frontend
sudo systemctl status nginx
sudo journalctl -u lab-frontend -f         # app logs
sudo tail -f /var/log/nginx/lab-error.log  # nginx logs
```

---

## Cleanup

To avoid ongoing AWS charges after the lab:

1. Terminate both EC2 instances
2. Delete the RDS instance (if created)
3. Release the Elastic IP allocated for the NAT Gateway
4. Delete the NAT Gateway
5. Delete the VPC (this removes subnets, route tables, IGW, and security groups)
