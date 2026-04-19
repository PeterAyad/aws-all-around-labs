#!/bin/bash
# ============================================================
#  AWS VPC Lab Phase 2 — FRONTEND User Data Script
#  Paste into: EC2 → Launch Templates → Advanced → User data
#
#  BEFORE PASTING: replace the S3 path below with yours.
#
#  Prerequisites (done in the console before creating this
#  Launch Template — see README Step 5):
#    1. An S3 bucket in the same region (e.g. lab-frontend-assets)
#    2. index.html uploaded to that bucket
#    3. An IAM instance profile attached to this Launch Template
#       that allows s3:GetObject on the bucket
# ============================================================

S3_PATH="s3://REPLACE_WITH_YOUR_BUCKET_NAME/index.html"

# ── Logging ────────────────────────────────────────────────
exec > >(tee /var/log/lab-frontend-init.log | logger -t lab-frontend) 2>&1
echo "[INIT] Frontend init started at $(date)"

# ── System update + Nginx ──────────────────────────────────
dnf update -y -q
dnf install -y nginx -q

# ── Download the app from S3 ───────────────────────────────
APP_DIR="/usr/share/nginx/lab"
mkdir -p "$APP_DIR"

echo "[INIT] Downloading index.html from ${S3_PATH}..."
aws s3 cp "$S3_PATH" "$APP_DIR/index.html"

# ── Nginx config ───────────────────────────────────────────
cat > /etc/nginx/conf.d/lab.conf << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    root /usr/share/nginx/lab;
    index index.html;

    # All routes → SPA
    location / {
        try_files $uri $uri/ /index.html;
    }

    access_log /var/log/nginx/lab-access.log;
    error_log  /var/log/nginx/lab-error.log;
}
EOF

rm -f /etc/nginx/conf.d/default.conf
nginx -t

systemctl enable nginx
systemctl start nginx

echo "[INIT] Frontend init complete at $(date)"
echo "[INIT] Serving: $APP_DIR/index.html"