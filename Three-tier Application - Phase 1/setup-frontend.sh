#!/bin/bash
# ============================================================
#  AWS VPC Lab — Frontend Server Setup Script
#  Installs Node.js app + Nginx reverse proxy on Amazon Linux 2023
#  Asks for backend IP, sets up everything
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║    AWS VPC Lab — Frontend Server Setup       ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Collect configuration ──────────────────────────────────
echo -e "${YELLOW}${BOLD}[CONFIG]${NC} Please provide the backend server's private IP address."
echo -e "  This is the ${BOLD}private IP${NC} of your backend EC2 instance."
echo ""
read -p "  Backend private IP address: " BACKEND_IP

if [[ -z "$BACKEND_IP" ]]; then
  echo -e "${RED}[ERROR]${NC} Backend IP cannot be empty. Exiting."
  exit 1
fi

echo ""
read -p "  Backend port [3000]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-3000}

echo ""
echo -e "${GREEN}${BOLD}[INFO]${NC} Starting installation..."
echo -e "  Backend target: ${CYAN}${BACKEND_IP}:${BACKEND_PORT}${NC}"
echo ""

# ── System update ──────────────────────────────────────────
echo -e "${YELLOW}▶ Updating system packages...${NC}"
sudo dnf update -y -q

# ── Node.js 20 ─────────────────────────────────────────────
echo -e "${YELLOW}▶ Installing Node.js 20...${NC}"
sudo dnf install -y nodejs -q 2>/dev/null || {
  curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash - -q
  sudo dnf install -y nodejs -q
}
echo -e "  Node.js version: $(node --version)"

# ── Nginx ──────────────────────────────────────────────────
echo -e "${YELLOW}▶ Installing Nginx...${NC}"
sudo dnf install -y nginx -q
echo -e "  Nginx version: $(nginx -v 2>&1 | head -1)"

# ── App directory ──────────────────────────────────────────
APP_DIR="/opt/labapp/frontend"
echo -e "${YELLOW}▶ Creating app directory at ${APP_DIR}...${NC}"
sudo mkdir -p "$APP_DIR"
sudo chown ec2-user:ec2-user "$APP_DIR"

# ── package.json ───────────────────────────────────────────
echo -e "${YELLOW}▶ Writing package.json...${NC}"
cat > "$APP_DIR/package.json" <<'PKGJSON'
{
  "name": "lab-frontend",
  "version": "1.0.0",
  "description": "AWS VPC Lab — Frontend",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "http-proxy-middleware": "^2.0.6",
    "node-fetch": "^2.7.0"
  }
}
PKGJSON

# ── Frontend HTML (the app) ────────────────────────────────
echo -e "${YELLOW}▶ Writing frontend application...${NC}"
mkdir -p "$APP_DIR/public"

cat > "$APP_DIR/public/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>AWS VPC Lab — Book Catalog</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=DM+Mono:ital,wght@0,400;0,500;1,400&family=Lora:ital,wght@0,400;0,500;1,400&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg:        #0d0f14;
      --surface:   #13161e;
      --surface2:  #1a1e28;
      --border:    #252a38;
      --accent:    #f0a500;
      --accent2:   #e05c3a;
      --green:     #3ecf8e;
      --red:       #e05c3a;
      --yellow:    #f0a500;
      --blue:      #5b9cf6;
      --text:      #e8eaf0;
      --muted:     #6b7280;
      --radius:    8px;
    }

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Lora', Georgia, serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
      overflow-x: hidden;
    }

    /* ── Layout ── */
    .app { display: grid; grid-template-rows: auto 1fr; min-height: 100vh; }

    /* ── Header ── */
    header {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      padding: 0 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      height: 64px;
      position: sticky;
      top: 0;
      z-index: 100;
    }
    .logo {
      display: flex; align-items: center; gap: 12px;
      font-family: 'Syne', sans-serif;
      font-weight: 800; font-size: 1.1rem;
      letter-spacing: -0.02em;
      color: var(--text);
      text-decoration: none;
    }
    .logo-icon {
      width: 32px; height: 32px;
      background: var(--accent);
      border-radius: 6px;
      display: flex; align-items: center; justify-content: center;
      font-size: 16px; color: #000;
    }
    .header-right { display: flex; align-items: center; gap: 16px; }

    /* ── Status Pill ── */
    .status-bar {
      display: flex; align-items: center; gap: 8px;
      padding: 6px 14px;
      border-radius: 999px;
      font-family: 'DM Mono', monospace;
      font-size: 0.72rem;
      font-weight: 500;
      letter-spacing: 0.03em;
      border: 1px solid var(--border);
      background: var(--surface2);
      cursor: pointer;
      transition: all 0.2s;
      user-select: none;
    }
    .status-bar:hover { border-color: var(--accent); }
    .status-dot {
      width: 7px; height: 7px; border-radius: 50%;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }
    .dot-ok     { background: var(--green); }
    .dot-warn   { background: var(--yellow); animation: none; }
    .dot-error  { background: var(--red); animation: none; }
    .dot-loading { background: var(--blue); }

    /* ── Status Panel ── */
    .status-panel {
      position: fixed; top: 72px; right: 1.5rem;
      width: 340px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.25rem;
      z-index: 200;
      display: none;
      box-shadow: 0 24px 64px rgba(0,0,0,0.5);
      animation: slideIn 0.2s ease;
    }
    @keyframes slideIn { from { opacity:0; transform:translateY(-8px); } to { opacity:1; transform:translateY(0); } }
    .status-panel.open { display: block; }
    .status-panel-title {
      font-family: 'Syne', sans-serif; font-weight: 700;
      font-size: 0.8rem; letter-spacing: 0.08em; text-transform: uppercase;
      color: var(--muted); margin-bottom: 1rem;
    }
    .status-row {
      display: flex; align-items: center; justify-content: space-between;
      padding: 10px 0;
      border-bottom: 1px solid var(--border);
    }
    .status-row:last-child { border-bottom: none; }
    .status-label {
      font-family: 'DM Mono', monospace; font-size: 0.82rem; color: var(--muted);
    }
    .status-val {
      font-family: 'DM Mono', monospace; font-size: 0.82rem; font-weight: 500;
      display: flex; align-items: center; gap: 6px;
    }
    .badge {
      padding: 2px 10px; border-radius: 999px;
      font-size: 0.7rem; font-weight: 600; font-family: 'Syne', sans-serif;
      letter-spacing: 0.04em; text-transform: uppercase;
    }
    .badge-ok     { background: rgba(62,207,142,0.15); color: var(--green); }
    .badge-error  { background: rgba(224,92,58,0.15);  color: var(--red);   }
    .badge-warn   { background: rgba(240,165,0,0.15);  color: var(--yellow);}
    .badge-loading{ background: rgba(91,156,246,0.15); color: var(--blue);  }

    .status-error-msg {
      margin-top: 0.75rem; padding: 10px 12px;
      background: rgba(224,92,58,0.08);
      border: 1px solid rgba(224,92,58,0.2);
      border-radius: 6px;
      font-family: 'DM Mono', monospace;
      font-size: 0.72rem; color: var(--red);
      line-height: 1.5;
      word-break: break-all;
    }

    /* ── Main content ── */
    .main {
      max-width: 1100px;
      margin: 0 auto;
      padding: 2.5rem 1.5rem 4rem;
    }

    /* ── Alert Banner ── */
    .alert-banner {
      display: none;
      padding: 14px 20px;
      border-radius: var(--radius);
      margin-bottom: 1.5rem;
      font-family: 'DM Mono', monospace;
      font-size: 0.82rem;
      line-height: 1.6;
      border-left: 3px solid;
    }
    .alert-banner.show { display: flex; align-items: flex-start; gap: 10px; }
    .alert-warn  { background: rgba(240,165,0,0.08); border-color: var(--yellow); color: var(--yellow); }
    .alert-error { background: rgba(224,92,58,0.08); border-color: var(--red);    color: var(--red);    }

    /* ── Page heading ── */
    .page-header {
      display: flex; align-items: flex-end; justify-content: space-between;
      margin-bottom: 2rem; flex-wrap: wrap; gap: 1rem;
    }
    .page-title {
      font-family: 'Syne', sans-serif; font-weight: 800;
      font-size: 2rem; letter-spacing: -0.03em;
      line-height: 1;
    }
    .page-subtitle {
      font-family: 'DM Mono', monospace; font-size: 0.8rem;
      color: var(--muted); margin-top: 6px;
    }

    /* ── Button ── */
    .btn {
      display: inline-flex; align-items: center; gap: 7px;
      padding: 9px 18px;
      border-radius: var(--radius);
      font-family: 'Syne', sans-serif; font-weight: 600;
      font-size: 0.85rem; letter-spacing: 0.01em;
      border: none; cursor: pointer;
      transition: all 0.18s;
    }
    .btn-primary { background: var(--accent); color: #000; }
    .btn-primary:hover { background: #ffb820; transform: translateY(-1px); }
    .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; transform: none; }
    .btn-ghost {
      background: transparent; color: var(--muted);
      border: 1px solid var(--border);
    }
    .btn-ghost:hover { border-color: var(--accent); color: var(--accent); }
    .btn-danger { background: rgba(224,92,58,0.12); color: var(--red); border: 1px solid rgba(224,92,58,0.25); }
    .btn-danger:hover { background: rgba(224,92,58,0.22); }
    .btn-sm { padding: 6px 12px; font-size: 0.78rem; }
    .btn-icon { padding: 8px; border-radius: 6px; }

    /* ── Search + Filter row ── */
    .toolbar {
      display: flex; align-items: center; gap: 10px;
      margin-bottom: 1.5rem; flex-wrap: wrap;
    }
    .search-wrap { position: relative; flex: 1; min-width: 200px; }
    .search-wrap input {
      width: 100%;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      color: var(--text);
      font-family: 'DM Mono', monospace;
      font-size: 0.85rem;
      padding: 10px 12px 10px 38px;
      outline: none;
      transition: border-color 0.2s;
    }
    .search-wrap input:focus { border-color: var(--accent); }
    .search-icon {
      position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
      color: var(--muted); font-size: 14px; pointer-events: none;
    }

    /* ── Book table ── */
    .table-wrap {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      overflow: hidden;
    }
    table { width: 100%; border-collapse: collapse; }
    thead tr {
      background: var(--surface2);
      border-bottom: 1px solid var(--border);
    }
    th {
      font-family: 'Syne', sans-serif; font-weight: 700;
      font-size: 0.72rem; letter-spacing: 0.06em; text-transform: uppercase;
      color: var(--muted); padding: 12px 16px; text-align: left;
    }
    td {
      padding: 13px 16px;
      border-bottom: 1px solid var(--border);
      font-size: 0.9rem;
      vertical-align: middle;
    }
    tbody tr:last-child td { border-bottom: none; }
    tbody tr:hover { background: var(--surface2); }
    .td-title { font-weight: 500; color: var(--text); }
    .td-author { color: var(--muted); font-style: italic; font-family: 'Lora'; }
    .td-genre {
      display: inline-block; padding: 2px 9px;
      border-radius: 999px; font-family: 'DM Mono', monospace; font-size: 0.72rem;
      background: rgba(91,156,246,0.12); color: var(--blue);
    }
    .td-year { font-family: 'DM Mono', monospace; font-size: 0.82rem; color: var(--muted); }
    .stars { color: var(--accent); font-size: 0.85rem; letter-spacing: -2px; }
    .td-actions { display: flex; gap: 6px; align-items: center; }
    .empty-state {
      text-align: center; padding: 4rem 1rem;
      color: var(--muted); font-size: 0.9rem;
      font-family: 'DM Mono', monospace;
    }
    .empty-state .empty-icon { font-size: 2.5rem; margin-bottom: 0.75rem; }

    /* ── Modal ── */
    .overlay {
      position: fixed; inset: 0; background: rgba(0,0,0,0.65);
      display: none; align-items: center; justify-content: center;
      z-index: 300; backdrop-filter: blur(3px);
      animation: fadeIn 0.15s;
    }
    @keyframes fadeIn { from { opacity:0; } to { opacity:1; } }
    .overlay.open { display: flex; }
    .modal {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 14px;
      width: 100%; max-width: 520px;
      max-height: 90vh; overflow-y: auto;
      padding: 2rem;
      animation: modalIn 0.2s ease;
    }
    @keyframes modalIn { from { transform:scale(0.96); opacity:0; } to { transform:scale(1); opacity:1; } }
    .modal-header {
      display: flex; align-items: center; justify-content: space-between;
      margin-bottom: 1.5rem;
    }
    .modal-title {
      font-family: 'Syne', sans-serif; font-weight: 800;
      font-size: 1.2rem; letter-spacing: -0.02em;
    }
    .modal-close {
      background: none; border: none; color: var(--muted);
      font-size: 1.3rem; cursor: pointer; padding: 4px 8px;
      border-radius: 6px; transition: color 0.2s;
    }
    .modal-close:hover { color: var(--text); }

    /* ── Form ── */
    .form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
    .form-full { grid-column: 1 / -1; }
    .field { display: flex; flex-direction: column; gap: 6px; }
    label {
      font-family: 'Syne', sans-serif; font-size: 0.75rem;
      font-weight: 700; letter-spacing: 0.05em; text-transform: uppercase;
      color: var(--muted);
    }
    input[type=text], input[type=number], select, textarea {
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      color: var(--text);
      font-family: 'Lora', serif; font-size: 0.9rem;
      padding: 10px 12px; outline: none;
      transition: border-color 0.2s;
      width: 100%;
    }
    input:focus, select:focus, textarea:focus { border-color: var(--accent); }
    select option { background: var(--surface2); }
    textarea { resize: vertical; min-height: 80px; }
    .form-actions {
      display: flex; gap: 10px; justify-content: flex-end;
      margin-top: 1.5rem;
    }

    /* ── Toast ── */
    .toast-wrap {
      position: fixed; bottom: 2rem; right: 1.5rem;
      display: flex; flex-direction: column; gap: 8px;
      z-index: 400;
    }
    .toast {
      padding: 12px 18px;
      border-radius: 8px;
      font-family: 'DM Mono', monospace; font-size: 0.8rem;
      display: flex; align-items: center; gap: 8px;
      animation: toastIn 0.25s ease;
      max-width: 320px;
      border: 1px solid;
    }
    @keyframes toastIn { from { opacity:0; transform:translateY(12px); } to { opacity:1; transform:translateY(0); } }
    .toast-ok    { background: rgba(62,207,142,0.1); border-color: rgba(62,207,142,0.3); color: var(--green); }
    .toast-error { background: rgba(224,92,58,0.1);  border-color: rgba(224,92,58,0.3);  color: var(--red);   }

    /* ── Loader ── */
    .loader {
      display: inline-block; width: 14px; height: 14px;
      border: 2px solid var(--border);
      border-top-color: var(--accent);
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    /* ── Confirm modal ── */
    .confirm-modal {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      width: 100%; max-width: 360px;
      padding: 1.75rem;
      animation: modalIn 0.2s;
    }
    .confirm-title { font-family:'Syne',sans-serif; font-weight:800; font-size:1.05rem; margin-bottom:0.5rem; }
    .confirm-body  { color: var(--muted); font-size: 0.88rem; margin-bottom: 1.5rem; line-height: 1.6; }
    .confirm-actions { display: flex; gap: 10px; justify-content: flex-end; }
  </style>
</head>
<body>
<div class="app">
  <!-- ── Header ── -->
  <header>
    <a class="logo" href="#">
      <div class="logo-icon">📚</div>
      Book Catalog <span style="color:var(--muted);font-weight:400;font-size:0.85rem;margin-left:4px">/ VPC Lab</span>
    </a>
    <div class="header-right">
      <div class="status-bar" id="statusBtn" onclick="toggleStatus()">
        <div class="status-dot dot-loading" id="statusDot"></div>
        <span id="statusText">Checking...</span>
      </div>
    </div>
  </header>

  <!-- ── Status panel ── -->
  <div class="status-panel" id="statusPanel">
    <div class="status-panel-title">Infrastructure Status</div>
    <div class="status-row">
      <span class="status-label">Frontend</span>
      <span class="status-val"><span class="badge badge-ok">Online</span></span>
    </div>
    <div class="status-row">
      <span class="status-label">Backend API</span>
      <span class="status-val" id="spBackend"><span class="badge badge-loading">Checking</span></span>
    </div>
    <div class="status-row">
      <span class="status-label">Database</span>
      <span class="status-val" id="spDb"><span class="badge badge-loading">Checking</span></span>
    </div>
    <div class="status-row">
      <span class="status-label">Last check</span>
      <span class="status-val" id="spTime" style="font-family:'DM Mono',monospace;font-size:0.78rem;color:var(--muted)">—</span>
    </div>
    <div class="status-row">
      <span class="status-label">Backend host</span>
      <span class="status-val" id="spHost" style="font-family:'DM Mono',monospace;font-size:0.78rem;color:var(--muted)">—</span>
    </div>
    <div id="spError" class="status-error-msg" style="display:none"></div>
  </div>

  <!-- ── Main ── -->
  <div class="main">
    <!-- Alert banners -->
    <div class="alert-banner alert-warn" id="alertWarn">
      <span>⚠️</span>
      <span id="alertWarnMsg"></span>
    </div>
    <div class="alert-banner alert-error" id="alertError">
      <span>🔴</span>
      <span id="alertErrorMsg"></span>
    </div>

    <div class="page-header">
      <div>
        <h1 class="page-title">Book Catalog</h1>
        <div class="page-subtitle" id="bookCount">Loading books...</div>
      </div>
      <button class="btn btn-primary" id="addBtn" onclick="openAdd()" disabled>
        <span>＋</span> Add Book
      </button>
    </div>

    <div class="toolbar">
      <div class="search-wrap">
        <span class="search-icon">🔍</span>
        <input type="text" id="searchInput" placeholder="Search by title or author…" oninput="filterBooks()"/>
      </div>
      <select id="genreFilter" onchange="filterBooks()" style="max-width:160px">
        <option value="">All genres</option>
      </select>
    </div>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Title</th>
            <th>Author</th>
            <th>Year</th>
            <th>Genre</th>
            <th>Rating</th>
            <th>Notes</th>
            <th style="width:100px">Actions</th>
          </tr>
        </thead>
        <tbody id="bookTable"></tbody>
      </table>
    </div>
  </div>
</div>

<!-- ── Add/Edit Modal ── -->
<div class="overlay" id="bookModal">
  <div class="modal">
    <div class="modal-header">
      <div class="modal-title" id="modalTitle">Add Book</div>
      <button class="modal-close" onclick="closeModal()">✕</button>
    </div>
    <div class="form-grid">
      <div class="field form-full">
        <label>Title *</label>
        <input type="text" id="f-title" placeholder="Enter book title"/>
      </div>
      <div class="field">
        <label>Author *</label>
        <input type="text" id="f-author" placeholder="Author name"/>
      </div>
      <div class="field">
        <label>Year</label>
        <input type="number" id="f-year" placeholder="e.g. 2023" min="1000" max="2099"/>
      </div>
      <div class="field">
        <label>Genre</label>
        <select id="f-genre">
          <option value="">Select genre</option>
          <option>Technology</option><option>Science</option><option>Fiction</option>
          <option>Non-Fiction</option><option>History</option><option>Philosophy</option>
          <option>Business</option><option>Biography</option><option>Other</option>
        </select>
      </div>
      <div class="field">
        <label>Rating (0–5)</label>
        <input type="number" id="f-rating" placeholder="4.5" min="0" max="5" step="0.1"/>
      </div>
      <div class="field form-full">
        <label>Notes</label>
        <textarea id="f-notes" placeholder="Optional notes about the book…"></textarea>
      </div>
    </div>
    <div class="form-actions">
      <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" id="saveBtn" onclick="saveBook()">Save Book</button>
    </div>
  </div>
</div>

<!-- ── Confirm Delete Modal ── -->
<div class="overlay" id="confirmModal">
  <div class="confirm-modal">
    <div class="confirm-title">Delete this book?</div>
    <div class="confirm-body">This action cannot be undone. The book will be permanently removed from the database.</div>
    <div class="confirm-actions">
      <button class="btn btn-ghost" onclick="closeConfirm()">Cancel</button>
      <button class="btn btn-danger" id="confirmDeleteBtn">Delete</button>
    </div>
  </div>
</div>

<!-- ── Toast container ── -->
<div class="toast-wrap" id="toastWrap"></div>

<script>
// ── State ──────────────────────────────────────────────────
let books = [];
let editingId = null;
let deleteId = null;
let systemOk = false;

// ── Status checking ────────────────────────────────────────
async function checkHealth() {
  try {
    const res = await fetch('/api/health', { signal: AbortSignal.timeout(6000) });
    const data = await res.json();
    updateStatus(data);
  } catch(err) {
    updateStatus({ backend: false, database: false, _fetchError: err.message });
  }
}

function updateStatus(data) {
  const dot     = document.getElementById('statusDot');
  const text    = document.getElementById('statusText');
  const spBe    = document.getElementById('spBackend');
  const spDb    = document.getElementById('spDb');
  const spTime  = document.getElementById('spTime');
  const spHost  = document.getElementById('spHost');
  const spErr   = document.getElementById('spError');
  const warnBanner  = document.getElementById('alertWarn');
  const errorBanner = document.getElementById('alertError');
  const warnMsg     = document.getElementById('alertWarnMsg');
  const errorMsg    = document.getElementById('alertErrorMsg');
  const addBtn      = document.getElementById('addBtn');

  const now = new Date().toLocaleTimeString();
  spTime.textContent = now;

  // Backend unreachable
  if (!data.backend || data._fetchError) {
    dot.className = 'status-dot dot-error';
    text.textContent = 'Backend down';
    spBe.innerHTML = '<span class="badge badge-error">Unreachable</span>';
    spDb.innerHTML = '<span class="badge badge-warn">Unknown</span>';
    spErr.style.display = 'block';
    spErr.textContent = data._fetchError || 'Cannot reach backend API';
    warnBanner.classList.remove('show');
    errorBanner.classList.add('show');
    errorMsg.textContent = 'Cannot reach backend server. Check your security groups and that the backend service is running.';
    addBtn.disabled = true;
    systemOk = false;
    return;
  }

  spBe.innerHTML = '<span class="badge badge-ok">Online</span>';
  spHost.textContent = data.hostname || '—';

  // Backend up, DB down
  if (!data.database) {
    dot.className = 'status-dot dot-warn';
    text.textContent = 'DB unreachable';
    spDb.innerHTML = '<span class="badge badge-error">Unreachable</span>';
    spErr.style.display = 'block';
    spErr.textContent = data.dbError || 'Database connection failed';
    errorBanner.classList.remove('show');
    warnBanner.classList.add('show');
    warnMsg.textContent = 'Backend is running but cannot reach the database. Check your RDS security group and connection string.';
    addBtn.disabled = true;
    systemOk = false;
    return;
  }

  // All good
  dot.className = 'status-dot dot-ok';
  text.textContent = 'All systems OK';
  spDb.innerHTML = '<span class="badge badge-ok">Connected</span>';
  spErr.style.display = 'none';
  warnBanner.classList.remove('show');
  errorBanner.classList.remove('show');
  addBtn.disabled = false;
  systemOk = true;
  loadBooks();
}

function toggleStatus() {
  document.getElementById('statusPanel').classList.toggle('open');
}
document.addEventListener('click', e => {
  if (!e.target.closest('#statusPanel') && !e.target.closest('#statusBtn'))
    document.getElementById('statusPanel').classList.remove('open');
});

// ── Books CRUD ─────────────────────────────────────────────
async function loadBooks() {
  try {
    const res = await fetch('/api/books');
    const data = await res.json();
    if (data.success) {
      books = data.data;
      renderBooks(books);
      updateGenreFilter();
      document.getElementById('bookCount').textContent =
        `${books.length} book${books.length !== 1 ? 's' : ''} in catalog`;
    }
  } catch(err) {
    toast('Could not load books', 'error');
  }
}

function renderBooks(list) {
  const tbody = document.getElementById('bookTable');
  if (!list.length) {
    tbody.innerHTML = `<tr><td colspan="7">
      <div class="empty-state">
        <div class="empty-icon">📭</div>
        No books found. Add your first book!
      </div>
    </td></tr>`;
    return;
  }
  tbody.innerHTML = list.map(b => `
    <tr>
      <td class="td-title">${esc(b.title)}</td>
      <td class="td-author">${esc(b.author)}</td>
      <td class="td-year">${b.year || '—'}</td>
      <td>${b.genre ? `<span class="td-genre">${esc(b.genre)}</span>` : '—'}</td>
      <td>${renderStars(b.rating)}</td>
      <td style="color:var(--muted);font-size:0.82rem;max-width:180px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(b.notes||'') || '—'}</td>
      <td>
        <div class="td-actions">
          <button class="btn btn-ghost btn-sm btn-icon" title="Edit" onclick="openEdit(${b.id})">✏️</button>
          <button class="btn btn-danger btn-sm btn-icon" title="Delete" onclick="openDelete(${b.id})">🗑️</button>
        </div>
      </td>
    </tr>
  `).join('');
}

function renderStars(r) {
  if (r === null || r === undefined) return '<span style="color:var(--muted)">—</span>';
  const full = Math.floor(r);
  const half = r % 1 >= 0.5 ? 1 : 0;
  return `<span class="stars">${'★'.repeat(full)}${'☆'.repeat(5-full-half)}</span> <span style="font-family:'DM Mono',monospace;font-size:0.78rem;color:var(--muted)">${Number(r).toFixed(1)}</span>`;
}

function filterBooks() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  const g = document.getElementById('genreFilter').value;
  const filtered = books.filter(b =>
    (!q || b.title.toLowerCase().includes(q) || b.author.toLowerCase().includes(q)) &&
    (!g || b.genre === g)
  );
  renderBooks(filtered);
}

function updateGenreFilter() {
  const genres = [...new Set(books.map(b=>b.genre).filter(Boolean))].sort();
  const sel = document.getElementById('genreFilter');
  const cur = sel.value;
  sel.innerHTML = '<option value="">All genres</option>' +
    genres.map(g=>`<option${cur===g?' selected':''}>${g}</option>`).join('');
}

// ── Modal ──────────────────────────────────────────────────
function openAdd() {
  editingId = null;
  document.getElementById('modalTitle').textContent = 'Add Book';
  document.getElementById('saveBtn').textContent = 'Add Book';
  ['title','author','year','genre','rating','notes'].forEach(f =>
    document.getElementById('f-'+f).value = '');
  document.getElementById('bookModal').classList.add('open');
  document.getElementById('f-title').focus();
}

function openEdit(id) {
  const b = books.find(x=>x.id===id);
  if (!b) return;
  editingId = id;
  document.getElementById('modalTitle').textContent = 'Edit Book';
  document.getElementById('saveBtn').textContent = 'Save Changes';
  document.getElementById('f-title').value  = b.title || '';
  document.getElementById('f-author').value = b.author || '';
  document.getElementById('f-year').value   = b.year || '';
  document.getElementById('f-genre').value  = b.genre || '';
  document.getElementById('f-rating').value = b.rating || '';
  document.getElementById('f-notes').value  = b.notes || '';
  document.getElementById('bookModal').classList.add('open');
  document.getElementById('f-title').focus();
}

function closeModal() {
  document.getElementById('bookModal').classList.remove('open');
}

async function saveBook() {
  const title  = document.getElementById('f-title').value.trim();
  const author = document.getElementById('f-author').value.trim();
  if (!title || !author) { toast('Title and author are required', 'error'); return; }

  const payload = {
    title, author,
    year:   document.getElementById('f-year').value   || null,
    genre:  document.getElementById('f-genre').value  || null,
    rating: document.getElementById('f-rating').value || null,
    notes:  document.getElementById('f-notes').value  || null,
  };

  const btn = document.getElementById('saveBtn');
  btn.disabled = true;
  btn.innerHTML = '<span class="loader"></span> Saving…';

  try {
    const url    = editingId ? `/api/books/${editingId}` : '/api/books';
    const method = editingId ? 'PUT' : 'POST';
    const res    = await fetch(url, {
      method, headers: {'Content-Type':'application/json'}, body: JSON.stringify(payload)
    });
    const data = await res.json();
    if (data.success) {
      toast(editingId ? 'Book updated!' : 'Book added!', 'ok');
      closeModal();
      loadBooks();
    } else {
      toast(data.error || 'Save failed', 'error');
    }
  } catch(err) {
    toast('Network error: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = editingId ? 'Save Changes' : 'Add Book';
  }
}

// ── Delete ──────────────────────────────────────────────────
function openDelete(id) {
  deleteId = id;
  const btn = document.getElementById('confirmDeleteBtn');
  btn.onclick = confirmDelete;
  document.getElementById('confirmModal').classList.add('open');
}
function closeConfirm() {
  document.getElementById('confirmModal').classList.remove('open');
  deleteId = null;
}
async function confirmDelete() {
  if (!deleteId) return;
  try {
    const res = await fetch(`/api/books/${deleteId}`, { method: 'DELETE' });
    const data = await res.json();
    if (data.success) {
      toast('Book deleted', 'ok');
      closeConfirm();
      loadBooks();
    } else {
      toast(data.error || 'Delete failed', 'error');
    }
  } catch(err) {
    toast('Network error', 'error');
  }
}

// ── Toast ──────────────────────────────────────────────────
function toast(msg, type='ok') {
  const wrap = document.getElementById('toastWrap');
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.innerHTML = (type==='ok'?'✓':'✕') + ' ' + msg;
  wrap.appendChild(t);
  setTimeout(() => t.remove(), 3500);
}

// ── Helpers ────────────────────────────────────────────────
function esc(s) {
  return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// ── Init ───────────────────────────────────────────────────
checkHealth();
setInterval(checkHealth, 30000);
</script>
</body>
</html>
HTMLEOF

# ── server.js (Express proxy layer) ───────────────────────
echo -e "${YELLOW}▶ Writing Express server with proxy...${NC}"
cat > "$APP_DIR/server.js" <<SERVERJS
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const BACKEND_URL = process.env.BACKEND_URL;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Proxy /api/* → backend
app.use('/api', createProxyMiddleware({
  target: BACKEND_URL,
  changeOrigin: true,
  timeout: 8000,
  proxyTimeout: 8000,
  on: {
    error: (err, req, res) => {
      console.error('[PROXY ERROR]', err.message);
      if (!res.headersSent) {
        res.status(502).json({
          success: false,
          backend: false,
          database: false,
          error: 'Backend unreachable: ' + err.message,
        });
      }
    }
  }
}));

// Catch-all
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('[FRONTEND] Listening on port', PORT);
  console.log('[FRONTEND] Proxying /api to:', BACKEND_URL);
});
SERVERJS

# ── Install dependencies ────────────────────────────────────
echo -e "${YELLOW}▶ Installing npm dependencies...${NC}"
cd "$APP_DIR"
npm install --silent

# ── Environment file ───────────────────────────────────────
echo -e "${YELLOW}▶ Writing environment config...${NC}"
cat > "$APP_DIR/.env" <<ENVFILE
BACKEND_URL=http://${BACKEND_IP}:${BACKEND_PORT}
PORT=8080
ENVFILE

# ── systemd service for frontend ───────────────────────────
echo -e "${YELLOW}▶ Creating frontend systemd service...${NC}"
sudo tee /etc/systemd/system/lab-frontend.service > /dev/null <<SVCFILE
[Unit]
Description=AWS VPC Lab - Frontend Server
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
SyslogIdentifier=lab-frontend

[Install]
WantedBy=multi-user.target
SVCFILE

# ── Nginx config ───────────────────────────────────────────
echo -e "${YELLOW}▶ Configuring Nginx as reverse proxy on port 80...${NC}"
sudo tee /etc/nginx/conf.d/lab.conf > /dev/null <<NGINXCONF
server {
    listen 80 default_server;
    server_name _;

    access_log /var/log/nginx/lab-access.log;
    error_log  /var/log/nginx/lab-error.log;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 60s;
        proxy_connect_timeout 10s;

        # Return graceful error if backend is down
        proxy_intercept_errors off;
    }
}
NGINXCONF

# Remove default nginx conf if present
sudo rm -f /etc/nginx/conf.d/default.conf

sudo nginx -t && echo -e "  Nginx config OK ✓"

# ── Start services ─────────────────────────────────────────
echo -e "${YELLOW}▶ Starting services...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable lab-frontend nginx
sudo systemctl start lab-frontend
sudo systemctl start nginx

sleep 4

# ── Verify ─────────────────────────────────────────────────
FE_OK=false
NG_OK=false
systemctl is-active --quiet lab-frontend && FE_OK=true
systemctl is-active --quiet nginx        && NG_OK=true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          ✓  Frontend setup complete!         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Frontend app:${NC}      http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}')"
echo -e "  ${BOLD}Node service:${NC}      $($FE_OK && echo '🟢 Running' || echo '🔴 Not running')"
echo -e "  ${BOLD}Nginx proxy:${NC}       $($NG_OK && echo '🟢 Running' || echo '🔴 Not running')"
echo -e "  ${BOLD}Backend target:${NC}    http://${BACKEND_IP}:${BACKEND_PORT}"
echo ""
echo -e "  ${CYAN}Logs:${NC}  sudo journalctl -u lab-frontend -f"
echo -e "  ${CYAN}Nginx:${NC} sudo tail -f /var/log/nginx/lab-error.log"
echo ""
echo -e "  Open the public IP in your browser to see the app."
echo -e "  The UI shows backend/database status in real time."
echo ""
