#!/bin/bash
# ============================================================
#  AWS VPC Lab Phase 2 — BACKEND User Data Script
#  Paste into: EC2 → Launch Templates → Advanced → User data
#
#  BEFORE PASTING: replace the DB connection string below
#  with your actual RDS endpoint.
#
#  Everything else is automatic — no SSH required.
# ============================================================

DB_CONNECTION_STRING="postgresql://postgres:postgres@REPLACE_WITH_YOUR_RDS_ENDPOINT:5432/postgres?sslmode=verify-full&sslrootcert=/tmp/global-bundle.pem"
BACKEND_PORT=3000

# ── Logging — visible in /var/log/lab-backend-init.log ────
exec > >(tee /var/log/lab-backend-init.log | logger -t lab-backend) 2>&1
echo "[INIT] Backend init started at $(date)"

# ── RDS SSL certificate ────────────────────────────────────
echo "[INIT] Downloading RDS SSL certificate..."
curl -sf -o /tmp/global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
chmod 644 /tmp/global-bundle.pem

# ── System update ──────────────────────────────────────────
echo "[INIT] Updating system..."
dnf update -y -q

# ── Node.js 20 ─────────────────────────────────────────────
echo "[INIT] Installing Node.js..."
# AL2023 has Node.js 20 in the native repos, no external setup needed.
dnf install -y nodejs -q
echo "[INIT] Node: $(node --version)"

# ── App directory ──────────────────────────────────────────
APP_DIR="/opt/lab/backend"
mkdir -p "$APP_DIR"
chown ec2-user:ec2-user "$APP_DIR"
cd "$APP_DIR"

# ── package.json ───────────────────────────────────────────
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

# ── server.js ─────────────────────────────────────────────
# Using standard bash heredoc with quoted 'EOF' to prevent variable interpolation
cat > /opt/lab/backend/server.js << 'EOF'
const express = require('express');
const { Pool }   = require('pg');
const cors       = require('cors');
const os         = require('os');
const { execSync } = require('child_process');

const app  = express();
const PORT = process.env.PORT || 3000;

// Resolve EC2 instance ID from metadata service (IMDSv2)
let INSTANCE_ID = os.hostname();
try {
  const token = execSync(
    'curl -sf -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"',
    { timeout: 3000 }
  ).toString().trim();
  const id = execSync(
    `curl -sf -H "X-aws-ec2-metadata-token: ${token}" http://169.254.169.254/latest/meta-data/instance-id`,
    { timeout: 3000 }
  ).toString().trim();
  if (id.startsWith('i-')) INSTANCE_ID = id;
} catch (_) {}

let requestCount = 0;
const startTime  = new Date();

app.use(cors());
app.use(express.json());

// Stamp every response with instance identity so the frontend
// can visualise which node served each request
app.use((req, res, next) => {
  requestCount++;
  res.setHeader('X-Instance-Id', INSTANCE_ID);
  next();
});

// ── DB pool ────────────────────────────────────────────────
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis:       10000,
  max: 10,
});
pool.on('error', err => console.error('[DB] Pool error:', err.message));

async function checkDb() {
  try {
    const c = await pool.connect();
    await c.query('SELECT 1');
    c.release();
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function initDb() {
  try {
    const c = await pool.connect();
    await c.query(`
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
    const { rows } = await c.query('SELECT COUNT(*) FROM books');
    if (parseInt(rows[0].count) === 0) {
      await c.query(`
        INSERT INTO books (title, author, year, genre, rating, notes) VALUES
          ('The Pragmatic Programmer',             'David Thomas',     1999, 'Technology', 4.8, 'Essential reading for every developer'),
          ('Clean Code',                            'Robert C. Martin', 2008, 'Technology', 4.5, 'Principles for maintainable software'),
          ('AWS in Action',                         'Michael Wittig',   2015, 'Technology', 4.3, 'Practical guide to AWS services'),
          ('Designing Data-Intensive Applications', 'Martin Kleppmann', 2017, 'Technology', 4.9, 'Deep dive into distributed systems')
      `);
      console.log('[DB] Seeded sample data');
    }
    c.release();
    console.log('[DB] Ready');
  } catch (err) {
    console.error('[DB] Init error (non-fatal):', err.message);
  }
}

// ── ALB health check — must return 200 fast ───────────────
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ── Full health — used by frontend dashboard ──────────────
app.get('/api/health', async (_req, res) => {
  const db = await checkDb();
  res.json({
    status:       'ok',
    instanceId:   INSTANCE_ID,
    hostname:     os.hostname(),
    backend:      true,
    database:     db.ok,
    dbError:      db.ok ? null : db.error,
    requestCount: requestCount,
    uptime:       Math.floor((Date.now() - startTime) / 1000),
    timestamp:    new Date().toISOString(),
  });
});

// ── CRUD ──────────────────────────────────────────────────
app.get('/api/books', async (_req, res) => {
  try {
    const r = await pool.query('SELECT * FROM books ORDER BY created_at DESC');
    res.json({ success: true, data: r.rows, count: r.rowCount, servedBy: INSTANCE_ID });
  } catch (err) { res.status(500).json({ success: false, error: err.message }); }
});

app.get('/api/books/:id', async (req, res) => {
  try {
    const r = await pool.query('SELECT * FROM books WHERE id = $1', [req.params.id]);
    if (!r.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: r.rows[0], servedBy: INSTANCE_ID });
  } catch (err) { res.status(500).json({ success: false, error: err.message }); }
});

app.post('/api/books', async (req, res) => {
  const { title, author, year, genre, rating, notes } = req.body;
  if (!title || !author)
    return res.status(400).json({ success: false, error: 'title and author are required' });
  try {
    const r = await pool.query(
      'INSERT INTO books (title,author,year,genre,rating,notes) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *',
      [title, author, year||null, genre||null, rating||null, notes||null]
    );
    res.status(201).json({ success: true, data: r.rows[0], servedBy: INSTANCE_ID });
  } catch (err) { res.status(500).json({ success: false, error: err.message }); }
});

app.put('/api/books/:id', async (req, res) => {
  const { title, author, year, genre, rating, notes } = req.body;
  try {
    const r = await pool.query(
      `UPDATE books SET
         title  = COALESCE($1, title),  author = COALESCE($2, author),
         year   = COALESCE($3, year),   genre  = COALESCE($4, genre),
         rating = COALESCE($5, rating), notes  = COALESCE($6, notes),
         updated_at = NOW()
       WHERE id = $7 RETURNING *`,
      [title||null, author||null, year||null, genre||null, rating||null, notes||null, req.params.id]
    );
    if (!r.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: r.rows[0], servedBy: INSTANCE_ID });
  } catch (err) { res.status(500).json({ success: false, error: err.message }); }
});

app.delete('/api/books/:id', async (req, res) => {
  try {
    const r = await pool.query('DELETE FROM books WHERE id = $1 RETURNING *', [req.params.id]);
    if (!r.rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: r.rows[0], servedBy: INSTANCE_ID });
  } catch (err) { res.status(500).json({ success: false, error: err.message }); }
});

// ── Start ─────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', async () => {
  console.log('[SERVER] ' + INSTANCE_ID + ' listening on :' + PORT);
  await initDb();
});
EOF
echo "[INIT] server.js written"

# ── Install dependencies ───────────────────────────────────
echo "[INIT] Running npm install..."
cd "$APP_DIR" && npm install --silent

# ── Environment ────────────────────────────────────────────
printf 'DATABASE_URL=%s\nPORT=%s\n' "$DB_CONNECTION_STRING" "$BACKEND_PORT" \
  > "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"
chown ec2-user:ec2-user "$APP_DIR/.env"

# ── systemd service ────────────────────────────────────────
cat > /etc/systemd/system/lab-backend.service << SVCEOF
[Unit]
Description=Lab Backend API
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/lab/backend
EnvironmentFile=/opt/lab/backend/.env
ExecStart=/usr/bin/node /opt/lab/backend/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=lab-backend

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable lab-backend
systemctl start lab-backend

echo "[INIT] Backend init complete at $(date)"
echo "[INIT] ALB health check endpoint: http://localhost:${BACKEND_PORT}/health"