# Steps

## 1. Create EFS File System

1. Go to **AWS Console → EFS → Create file system**
2. Configure
   * **Name**: anything (e.g. `my-efs`)
   * **VPC**: same VPC as your EC2
   * Leave defaults for now

## 2. Create a Mount Target For EFS

* A `mount target` is an interface for **EFS** to access your **Availability Zone (AZ)**
* Creating a `mount target` involves creating a `network-interface ENI`, assigning an `IP`, and attaching a `security group` as if the **EFS** is an EC2 instance

## 3. Update Security Rules

1. Check which `security group` is attached to the EFS `mount target` in the EFS network settings
2. Add **inbound rule**:

| Protocol | Port | Source             |
| -------- | ---- | ------------------ |
| TCP      | 2049 | EC2 security group |

---

## 3. Launch EC2 Instance

1. Go to **EC2 → Launch instance**
2. Configure
   * AMI: Amazon Linux 2
   * Instance type: t2.micro (for testing)
   * VPC: SAME as EFS
   * Subnet: same AZ as one mount target
   * Security Group Rule: Allow `SSH (22)`

---

## 4. Connect EC2 → EFS

SSH into your instance:

```bash
ssh ec2-user@<your-ip>
```

---

### 5. Install EFS utils

```bash
sudo yum update -y
sudo yum install -y amazon-efs-utils
```

---

### 6. Create mount directory

```bash
mkdir ~/efs
```

---

### 7. Mount EFS

```bash
sudo mount -t efs -o tls fs-XXXXXXXX:/ ~/efs
```

(Replace with your File System ID)

---

### 8. Verify mount

```bash
df -h
```

You’ll see something like:

```txt
fs-xxxx.efs... mounted
```

---

## 8. Fix Permissions (VERY IMPORTANT)

By default, EFS is owned by root → you can’t write. Fix it:

```bash
sudo chown ec2-user:ec2-user ~/efs
```

---

## 9. Use EFS

```bash
cd ~/efs
```

Download File:

```bash
wget https://ash-speed.hetzner.com/1GB.bin
```

---

## 10. (Optional) Auto-mount on reboot

Edit fstab:

```bash
sudo nano /etc/fstab
```

Add:

```bash
fs-XXXXXXXX:/ /home/ec2-user/efs efs _netdev,tls 0 0
```

Then test:

```bash
sudo mount -a
```

---

## 11. Test The EFS

1. Create a new EC2 instance
2. Mount the EFS as above
3. Look for the files you added to the EFS using the other EC2 instance
