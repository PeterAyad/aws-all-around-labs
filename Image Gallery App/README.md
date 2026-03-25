# Steps

## 1. Launch EC2

1. Go to AWS Console → EC2 → click "Launch instances"
2. Name it something like `gallery-lab-1`
3. AMI: select **"Amazon Linux 2023"**
4. Instance type: `t2.micro` or `t3.micro`
5. Key pair: create or select an existing `.pem` key (you'll need it to SSH in)
6. Leave the rest as default → click "Launch instance"

## 2. Open port 8080

1. Go to EC2 → Security Groups → select the group attached to your instance
2. Click "Inbound rules" → "Edit inbound rules"
3. Add rule: Type = Custom TCP, Port = `8080`, Source = `0.0.0.0/0`
4. Save rules

## 3. Create and attach EBS volume

1. Go to EC2 → Elastic Block Store → Volumes → "Create volume" with any size
2. Availability Zone: must match your EC2 instance's AZ (e.g. `us-east-1a`) — check this in your instance details
3. Click "Create volume"
4. Once it shows "available" → Actions → "Attach volume" → select your instance, device `/dev/xvdf` → Attach

## 4. Upload the files

1. On your local machine, upload to EC2:

```bash
scp -i your-key.pem -r image-gallery/ ec2-user@<EC2-PUBLIC-IP>:~/
```

## 5. Run the setup script

1. SSH into the instance:

```bash
ssh -i your-key.pem ec2-user@<EC2-PUBLIC-IP>
```

1. Run the installer:

```bash
sudo bash ~/image-gallery/setup.sh
```

The script formats and mounts the EBS, installs Flask, and starts the gallery as a systemd service.

## 6. Open the gallery

1. Go to `http://<EC2-PUBLIC-IP>:8080` in your browser
2. Upload some images and add captions — this is your "before" state saved on EBS

---

## 7. The persistence test (the actual lab)

1. Go to EC2 Console → select your instance → Instance state → "Terminate instance" (the EBS volume stays because it's a separate resource)
2. Launch a brand new EC2 instance (steps 1–2 again, same AZ)
3. Attach the same EBS volume to the new instance (steps 15 again)
4. SCP the files again and SSH into the new instance
5. Run `sudo bash ~/image-gallery/setup.sh` again — it detects the existing filesystem and skips formatting
6. Open `http://<NEW-EC2-IP>:8080` — all your images and captions are still there
