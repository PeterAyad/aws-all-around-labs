#!/bin/bash
# ============================================================
#  AWS VPC Lab — Backend Server Setup Script
#  Amazon Linux 2023 | Node.js 20 + Express + pg
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     AWS VPC Lab — Backend Server Setup       ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Collect configuration ──────────────────────────────────
echo -e "${YELLOW}${BOLD}[CONFIG]${NC} Please provide your PostgreSQL connection string."
echo -e "  Format:  ${CYAN}postgresql://USER:PASSWORD@HOST:5432/DBNAME${NC}"
echo -e "  Example: postgresql://postgres:secret@10.0.3.10:5432/labdb"
echo ""
read -p "  PostgreSQL connection string: " DB_CONNECTION_STRING

if [[ -z "$DB_CONNECTION_STRING" ]]; then
  echo -e "${RED}[ERROR]${NC} Connection string cannot be empty. Exiting."; exit 1
fi

read -p "  Backend port [3000]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-3000}

echo ""
echo -e "${GREEN}${BOLD}[INFO]${NC} Starting installation..."

# ── System update ──────────────────────────────────────────
echo -e "${YELLOW}▶ Updating system packages...${NC}"
sudo dnf update -y -q

# ── Node.js 20 ─────────────────────────────────────────────
echo -e "${YELLOW}▶ Installing Node.js 20...${NC}"
if ! node --version 2>/dev/null | grep -q "v2"; then
  curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash - 2>/dev/null
  sudo dnf install -y nodejs -q
fi
echo -e "  Node: $(node --version)  npm: $(npm --version)"

# ── App directory ──────────────────────────────────────────
APP_DIR="/opt/labapp/backend"
echo -e "${YELLOW}▶ Creating app directory at ${APP_DIR}...${NC}"
sudo mkdir -p "$APP_DIR"
sudo chown ec2-user:ec2-user "$APP_DIR"
cd "$APP_DIR"

# ── package.json ───────────────────────────────────────────
echo -e "${YELLOW}▶ Writing package.json...${NC}"
cat > package.json << 'EOF'
{
  "name": "lab-backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "pg": "^8.11.3"
  }
}
EOF

# ── server.js (written via Python to safely handle special chars) ──
echo -e "${YELLOW}▶ Writing server.js...${NC}"

python3 << 'PYEOF'
code = """const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// DB pool - never crashes the process on DB failure
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 10000,
  max: 10,
});

pool.on('error', (err) => {
  console.error('[DB] Pool error (non-fatal):', err.message);
});

async function checkDb() {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function initDb() {
  try {
    const client = await pool.connect();
    await client.query(`
      CREATE TABLE IF NOT EXISTS books (
        id         SERIAL PRIMARY KEY,
        title      VARCHAR(255) NOT NULL,
        author     VARCHAR(255) NOT NULL,
        year       INTEGER,
        genre      VARCHAR(100),
        rating     NUMERIC(2,1) CHECK (rating >= 0 AND rating <= 5),
        notes      TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    const { rows } = await client.query('SELECT COUNT(*) FROM books');
    if (parseInt(rows[0].count) === 0) {
      await client.query(`
        INSERT INTO books (title, author, year, genre, rating, notes) VALUES
          ('The Pragmatic Programmer', 'David Thomas', 1999, 'Technology', 4.8, 'Essential reading for every developer'),
          ('Clean Code', 'Robert C. Martin', 2008, 'Technology', 4.5, 'Principles for maintainable software'),
          ('AWS in Action', 'Michael Wittig', 2015, 'Technology', 4.3, 'Practical guide to AWS services'),
          ('Designing Data-Intensive Applications', 'Martin Kleppmann', 2017, 'Technology', 4.9, 'Deep dive into distributed systems')
      `);
      console.log('[DB] Seeded sample books');
    }
    client.release();
    console.log('[DB] Table ready');
  } catch (err) {
    console.error('[DB] Init failed (will retry on next request):', err.message);
  }
}

// Health
app.get('/api/health', async (req, res) => {
  const db = await checkDb();
  res.json({
    status:    'ok',
    backend:   true,
    database:  db.ok,
    dbError:   db.ok ? null : db.error,
    timestamp: new Date().toISOString(),
    hostname:  os.hostname(),
  });
});

// GET all books
app.get('/api/books', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM books ORDER BY created_at DESC');
    res.json({ success: true, data: result.rows, count: result.rowCount });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET one book
app.get('/api/books/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM books WHERE id = $1', [req.params.id]);
    if (!result.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST create
app.post('/api/books', async (req, res) => {
  const { title, author, year, genre, rating, notes } = req.body;
  if (!title || !author)
    return res.status(400).json({ success: false, error: 'title and author are required' });
  try {
    const result = await pool.query(
      'INSERT INTO books (title, author, year, genre, rating, notes) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *',
      [title, author, year || null, genre || null, rating || null, notes || null]
    );
    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// PUT update
app.put('/api/books/:id', async (req, res) => {
  const { title, author, year, genre, rating, notes } = req.body;
  try {
    const result = await pool.query(
      `UPDATE books SET
         title  = COALESCE($1, title),
         author = COALESCE($2, author),
         year   = COALESCE($3, year),
         genre  = COALESCE($4, genre),
         rating = COALESCE($5, rating),
         notes  = COALESCE($6, notes),
         updated_at = NOW()
       WHERE id = $7 RETURNING *`,
      [title||null, author||null, year||null, genre||null, rating||null, notes||null, req.params.id]
    );
    if (!result.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// DELETE
app.delete('/api/books/:id', async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM books WHERE id = $1 RETURNING *', [req.params.id]);
    if (!result.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: result.rows[0], message: 'Deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', async () => {
  console.log('[SERVER] Backend API running on port ' + PORT);
  await initDb();
});
"""

with open('/opt/labapp/backend/server.js', 'w') as f:
    f.write(code)
print('server.js written OK')
PYEOF

# ── Install dependencies ────────────────────────────────────
echo -e "${YELLOW}▶ Installing npm dependencies...${NC}"
npm install --silent

# ── Environment file ───────────────────────────────────────
echo -e "${YELLOW}▶ Writing .env...${NC}"
printf 'DATABASE_URL=%s\nPORT=%s\n' "$DB_CONNECTION_STRING" "$BACKEND_PORT" > "$APP_DIR/.env"
sudo chmod 600 "$APP_DIR/.env"

# ── systemd service ────────────────────────────────────────
echo -e "${YELLOW}▶ Installing systemd service...${NC}"
sudo tee /etc/systemd/system/lab-backend.service > /dev/null << SVCEOF
[Unit]
Description=AWS VPC Lab - Backend API Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=/usr/bin/node ${APP_DIR}/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lab-backend

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable lab-backend
sudo systemctl start lab-backend

# ── Verify ─────────────────────────────────────────────────
echo -e "${YELLOW}▶ Waiting for service to start...${NC}"
sleep 4

if sudo systemctl is-active --quiet lab-backend; then
  PRIVATE_IP=$(hostname -I | awk '{print $1}')
  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║          ✓  Backend setup complete!          ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Private IP:${NC}        ${PRIVATE_IP}"
  echo -e "  ${BOLD}Health endpoint:${NC}   http://${PRIVATE_IP}:${BACKEND_PORT}/api/health"
  echo -e "  ${BOLD}Books endpoint:${NC}    http://${PRIVATE_IP}:${BACKEND_PORT}/api/books"
  echo ""
  echo -e "  ${CYAN}Quick test:${NC}  curl http://localhost:${BACKEND_PORT}/api/health"
  echo -e "  ${CYAN}Live logs:${NC}   sudo journalctl -u lab-backend -f"
  echo ""
  echo -e "  ${YELLOW}${BOLD}Next step:${NC} Run setup-frontend.sh on the public EC2"
  echo -e "  and enter this private IP when prompted: ${BOLD}${PRIVATE_IP}${NC}"
  echo ""
else
  echo -e "${RED}${BOLD}[ERROR]${NC} Service failed to start."
  echo -e "  Check logs: sudo journalctl -u lab-backend -n 50 --no-pager"
  exit 1
fi
