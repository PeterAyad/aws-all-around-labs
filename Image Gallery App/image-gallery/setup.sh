#!/bin/bash
# ============================================================
#  EBS Image Gallery — Amazon Linux Setup Script
#  Usage:  sudo bash setup.sh
#
#  What this does:
#    1. Asks which block device is your EBS volume
#    2. Installs Python 3 + pip (if missing)
#    3. Installs Flask + Werkzeug
#    4. Copies app files to /opt/gallery
#    5. Mounts the EBS volume at /mnt/data
#    6. Creates a systemd service (gallery.service)
#    7. Starts the service and enables it on boot
# ============================================================
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────
DATA_DIR="/mnt/data/gallery"
APP_DIR="/opt/gallery"
SERVICE_NAME="gallery"
PORT="${PORT:-8080}"
MAX_MB="${MAX_MB:-50}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# Must run as root
[[ $EUID -eq 0 ]] || error "Run with sudo: sudo bash setup.sh"

# ─── Interactive device picker ────────────────────────────────
echo ""
echo -e "${CYAN}  Available block devices:${NC}"
echo "  ──────────────────────────────────────"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS | sed 's/^/  /'
echo "  ──────────────────────────────────────"
echo ""
echo -e "  Your EBS data volume is the disk that is NOT mounted to / or /boot."
echo -e "  It is usually the one with no MOUNTPOINTS listed (e.g. nvme1n1)."
echo ""

while true; do
  read -rp "  Enter the EBS device name (e.g. nvme1n1 or xvdf): " DEV_INPUT
  DEV_INPUT="${DEV_INPUT#/dev/}"           # strip /dev/ prefix if user typed it
  EBS_DEVICE="/dev/${DEV_INPUT}"
  if [[ -z "${DEV_INPUT}" ]]; then
    warn "Device name cannot be empty. Try again."
  elif ! lsblk "${EBS_DEVICE}" &>/dev/null; then
    warn "${EBS_DEVICE} not found. Check the name and try again."
  else
    echo ""
    info "Selected device: ${EBS_DEVICE}"
    break
  fi
done

# ─── 1. Python & pip ─────────────────────────────────────────
info "Checking Python 3..."
if ! command -v python3 &>/dev/null; then
  info "Installing Python 3..."
  yum install -y python3 python3-pip 2>/dev/null || \
    dnf install -y python3 python3-pip 2>/dev/null || \
    error "Could not install Python 3. Check your yum/dnf repos."
else
  info "Python 3 found: $(python3 --version)"
fi

if ! command -v pip3 &>/dev/null; then
  python3 -m ensurepip --upgrade
fi

# ─── 2. Flask ────────────────────────────────────────────────
info "Installing Flask + Werkzeug..."
pip3 install -q flask werkzeug

# ─── 3. Copy app files ───────────────────────────────────────
info "Installing app to ${APP_DIR}..."
mkdir -p "${APP_DIR}/static"
cp "${SCRIPT_DIR}/app.py"              "${APP_DIR}/app.py"
cp "${SCRIPT_DIR}/static/index.html"   "${APP_DIR}/static/index.html"
chmod 755 "${APP_DIR}/app.py"

# ─── 4. EBS volume setup ─────────────────────────────────────
info "Setting up EBS volume at ${EBS_DEVICE}..."

# Format only if no filesystem present
if ! blkid "${EBS_DEVICE}" &>/dev/null; then
  info "No filesystem found on ${EBS_DEVICE} — formatting as ext4..."
  mkfs -t ext4 "${EBS_DEVICE}"
  info "Filesystem created."
else
  info "${EBS_DEVICE} already has a filesystem — skipping format (data preserved)."
fi

# Mount
mkdir -p /mnt/data
if mountpoint -q /mnt/data; then
  info "/mnt/data already mounted."
else
  info "Mounting ${EBS_DEVICE} → /mnt/data..."
  mount "${EBS_DEVICE}" /mnt/data
fi

# fstab persistence
if ! grep -q "${EBS_DEVICE}" /etc/fstab; then
  info "Adding ${EBS_DEVICE} to /etc/fstab for auto-mount on reboot..."
  echo "${EBS_DEVICE}  /mnt/data  ext4  defaults,nofail  0  2" >> /etc/fstab
fi

mkdir -p "${DATA_DIR}"
sudo chown -R ec2-user:ec2-user /mnt/data
info "Data directory: ${DATA_DIR}"

# ─── 5. Systemd service ──────────────────────────────────────
info "Creating systemd service: ${SERVICE_NAME}.service..."

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EBS Image Gallery
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=${APP_DIR}
Environment="DATA_DIR=${DATA_DIR}"
Environment="PORT=${PORT}"
Environment="MAX_MB=${MAX_MB}"
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ─── 6. Start service ────────────────────────────────────────
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

sleep 2
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  info "Service is running."
else
  warn "Service may have failed to start. Check logs:"
  warn "  journalctl -u ${SERVICE_NAME} -n 30"
fi

# ─── Done ────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<EC2-public-IP>")

echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓  EBS Image Gallery is live!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  URL    →  http://${PUBLIC_IP}:${PORT}"
echo -e "  Data   →  ${DATA_DIR}  (on EBS)"
echo ""
echo -e "  Useful commands:"
echo -e "    systemctl status ${SERVICE_NAME}       # check health"
echo -e "    journalctl -u ${SERVICE_NAME} -f       # live logs"
echo -e "    systemctl restart ${SERVICE_NAME}      # restart"
echo ""
echo -e "  To prove EBS persistence:"
echo -e "    1. Upload images via the browser"
echo -e "    2. Terminate this EC2 instance"
echo -e "    3. Launch a new EC2, attach same EBS"
echo -e "    4. Run:  sudo bash setup.sh"
echo -e "    5. Open the new IP — all images still there ✓"
echo ""
