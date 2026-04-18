const express = require("express");
const multer = require("multer");
const { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } = require("@aws-sdk/client-s3");
const { DynamoDBClient, PutItemCommand, ScanCommand } = require("@aws-sdk/client-dynamodb");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

const REGION = process.env.AWS_REGION || "us-east-1";
const BUCKET = process.env.S3_BUCKET;
const TABLE = process.env.DYNAMO_TABLE;

const s3 = new S3Client({ region: REGION });
const dynamo = new DynamoDBClient({ region: REGION });

app.use(express.json());

// ── HTML UI ───────────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>🔐 AWS IAM Lab</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Space+Grotesk:wght@400;600;700&display=swap');
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg: #0a0e1a; --surface: #111827; --border: #1f2d40;
      --accent: #00e5ff; --accent2: #7c3aed; --warn: #f59e0b;
      --ok: #10b981; --err: #ef4444; --text: #e2e8f0; --muted: #64748b;
    }
    body { background: var(--bg); color: var(--text); font-family: 'Space Grotesk', sans-serif; min-height: 100vh; }
    header {
      background: linear-gradient(135deg, #0a0e1a 0%, #111827 50%, #0f1929 100%);
      border-bottom: 1px solid var(--border); padding: 24px 40px;
      display: flex; align-items: center; gap: 16px;
    }
    header h1 { font-size: 1.4rem; font-weight: 700; letter-spacing: -0.5px; }
    header h1 span { color: var(--accent); }
    .badge {
      font-family: 'JetBrains Mono', monospace; font-size: 0.7rem;
      background: var(--accent2); color: white; padding: 3px 10px;
      border-radius: 20px; letter-spacing: 1px; text-transform: uppercase;
    }
    main { max-width: 900px; margin: 40px auto; padding: 0 24px; }
    .env-bar {
      background: var(--surface); border: 1px solid var(--border); border-radius: 10px;
      padding: 14px 20px; margin-bottom: 32px; font-family: 'JetBrains Mono', monospace;
      font-size: 0.8rem; display: flex; gap: 24px; flex-wrap: wrap;
    }
    .env-bar span { color: var(--muted); }
    .env-bar b { color: var(--accent); }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
    @media (max-width: 640px) { .grid { grid-template-columns: 1fr; } }
    .card {
      background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
      overflow: hidden;
    }
    .card-head {
      padding: 16px 20px; border-bottom: 1px solid var(--border);
      display: flex; align-items: center; gap: 10px; font-weight: 700;
    }
    .card-head .icon { font-size: 1.3rem; }
    .card-head .label { flex: 1; }
    .service-tag {
      font-family: 'JetBrains Mono', monospace; font-size: 0.65rem;
      padding: 2px 8px; border-radius: 4px; text-transform: uppercase; letter-spacing: 1px;
    }
    .s3-tag { background: #7c3aed33; color: #a78bfa; border: 1px solid #7c3aed55; }
    .ddb-tag { background: #00e5ff22; color: var(--accent); border: 1px solid #00e5ff44; }
    .card-body { padding: 20px; }
    label { display: block; font-size: 0.8rem; color: var(--muted); margin-bottom: 6px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
    input[type=text], input[type=file], textarea {
      width: 100%; background: #0d1421; border: 1px solid var(--border); color: var(--text);
      border-radius: 7px; padding: 10px 14px; font-family: inherit; font-size: 0.9rem;
      margin-bottom: 12px; outline: none; transition: border-color .2s;
    }
    input:focus, textarea:focus { border-color: var(--accent); }
    textarea { resize: vertical; height: 80px; }
    button {
      width: 100%; padding: 11px; border-radius: 7px; border: none; font-family: inherit;
      font-weight: 700; font-size: 0.9rem; cursor: pointer; transition: all .2s;
      letter-spacing: 0.3px;
    }
    .btn-s3 { background: var(--accent2); color: white; }
    .btn-s3:hover { background: #6d28d9; }
    .btn-ddb { background: var(--accent); color: #0a0e1a; }
    .btn-ddb:hover { background: #00c9e0; }
    .btn-load { background: transparent; border: 1px solid var(--border) !important; color: var(--text); width: auto; padding: 7px 16px; font-size: 0.8rem; margin-top: 8px; }
    .btn-load:hover { border-color: var(--accent) !important; color: var(--accent); }
    .result-area {
      margin-top: 20px; background: #060a10; border: 1px solid var(--border); border-radius: 8px;
      padding: 14px; font-family: 'JetBrains Mono', monospace; font-size: 0.78rem;
      min-height: 60px; max-height: 220px; overflow-y: auto; white-space: pre-wrap; word-break: break-word;
    }
    .ok   { color: var(--ok); }
    .err  { color: var(--err); }
    .warn { color: var(--warn); }
    .separator { grid-column: 1 / -1; border: none; border-top: 1px solid var(--border); margin: 8px 0; }
    .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; margin-top: 12px; }
    .gallery img { width: 100%; height: 100px; object-fit: cover; border-radius: 6px; border: 1px solid var(--border); cursor: pointer; transition: transform .2s; }
    .gallery img:hover { transform: scale(1.05); border-color: var(--accent); }
    .records { margin-top: 12px; display: flex; flex-direction: column; gap: 8px; }
    .record {
      background: #060a10; border: 1px solid var(--border); border-radius: 6px;
      padding: 10px 14px; font-size: 0.82rem;
    }
    .record b { color: var(--accent); }
    .record .ts { color: var(--muted); font-family: 'JetBrains Mono', monospace; font-size: 0.72rem; }
  </style>
</head>
<body>
<header>
  <span style="font-size:2rem">🔐</span>
  <h1>AWS IAM <span>Permission</span> Lab</h1>
  <span class="badge">Learning Lab</span>
</header>
<main>
  <div class="env-bar">
    <div><span>BUCKET </span><b id="envBucket">loading…</b></div>
    <div><span>TABLE &nbsp;</span><b id="envTable">loading…</b></div>
    <div><span>REGION </span><b id="envRegion">loading…</b></div>
    <div><span>RUNTIME </span><b id="envRuntime">loading…</b></div>
  </div>

  <div class="grid">
    <!-- S3 Upload -->
    <div class="card">
      <div class="card-head">
        <span class="icon">🪣</span>
        <span class="label">Upload Image</span>
        <span class="service-tag s3-tag">S3</span>
      </div>
      <div class="card-body">
        <label>Pick an image (max 5 MB)</label>
        <input type="file" id="imgFile" accept="image/*">
        <button class="btn-s3" onclick="uploadImage()">Upload to S3</button>
        <div class="result-area" id="s3UploadResult">Waiting…</div>
      </div>
    </div>

    <!-- DynamoDB Write -->
    <div class="card">
      <div class="card-head">
        <span class="icon">📋</span>
        <span class="label">Save Note</span>
        <span class="service-tag ddb-tag">DynamoDB</span>
      </div>
      <div class="card-body">
        <label>Title</label>
        <input type="text" id="noteTitle" placeholder="My note title">
        <label>Content</label>
        <textarea id="noteContent" placeholder="Write something…"></textarea>
        <button class="btn-ddb" onclick="saveNote()">Save to DynamoDB</button>
        <div class="result-area" id="ddbWriteResult">Waiting…</div>
      </div>
    </div>

    <!-- S3 Gallery -->
    <div class="card">
      <div class="card-head">
        <span class="icon">🖼️</span>
        <span class="label">Image Gallery</span>
        <span class="service-tag s3-tag">S3</span>
      </div>
      <div class="card-body">
        <button class="btn-load" onclick="loadImages()">🔄 Load Images</button>
        <div id="gallery" class="gallery"></div>
        <div class="result-area" id="s3ListResult" style="margin-top:12px">Click Load Images…</div>
      </div>
    </div>

    <!-- DynamoDB Read -->
    <div class="card">
      <div class="card-head">
        <span class="icon">📖</span>
        <span class="label">Read Notes</span>
        <span class="service-tag ddb-tag">DynamoDB</span>
      </div>
      <div class="card-body">
        <button class="btn-load" onclick="loadNotes()">🔄 Load Notes</button>
        <div id="records" class="records"></div>
        <div class="result-area" id="ddbReadResult" style="margin-top:12px">Click Load Notes…</div>
      </div>
    </div>
  </div>
</main>

<script>
async function apiFetch(path, opts = {}) {
  const r = await fetch(path, opts);
  return r.json();
}

async function loadEnv() {
  const d = await apiFetch("/api/env");
  document.getElementById("envBucket").textContent  = d.bucket  || "NOT SET";
  document.getElementById("envTable").textContent   = d.table   || "NOT SET";
  document.getElementById("envRegion").textContent  = d.region  || "NOT SET";
  document.getElementById("envRuntime").textContent = d.runtime || "unknown";
}

async function uploadImage() {
  const el = document.getElementById("imgFile");
  const out = document.getElementById("s3UploadResult");
  if (!el.files[0]) { out.innerHTML = '<span class="warn">Select a file first.</span>'; return; }
  out.innerHTML = '<span class="warn">Uploading…</span>';
  const fd = new FormData();
  fd.append("image", el.files[0]);
  const d = await apiFetch("/api/upload", { method: "POST", body: fd });
  out.innerHTML = d.ok
    ? '<span class="ok">✅ Uploaded: ' + d.key + '</span>'
    : '<span class="err">❌ ' + d.error + '</span>';
}

async function saveNote() {
  const title = document.getElementById("noteTitle").value.trim();
  const content = document.getElementById("noteContent").value.trim();
  const out = document.getElementById("ddbWriteResult");
  if (!title) { out.innerHTML = '<span class="warn">Enter a title.</span>'; return; }
  out.innerHTML = '<span class="warn">Saving…</span>';
  const d = await apiFetch("/api/note", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title, content })
  });
  out.innerHTML = d.ok
    ? '<span class="ok">✅ Saved with id: ' + d.id + '</span>'
    : '<span class="err">❌ ' + d.error + '</span>';
}

async function loadImages() {
  const out = document.getElementById("s3ListResult");
  const gallery = document.getElementById("gallery");
  out.innerHTML = '<span class="warn">Loading…</span>';
  gallery.innerHTML = "";
  const d = await apiFetch("/api/images");
  if (!d.ok) { out.innerHTML = '<span class="err">❌ ' + d.error + '</span>'; return; }
  out.innerHTML = '<span class="ok">✅ Found ' + d.images.length + ' image(s)</span>';
  d.images.forEach(img => {
    const el = document.createElement("img");
    el.src = img.url;
    el.title = img.key;
    gallery.appendChild(el);
  });
}

async function loadNotes() {
  const out = document.getElementById("ddbReadResult");
  const records = document.getElementById("records");
  out.innerHTML = '<span class="warn">Loading…</span>';
  records.innerHTML = "";
  const d = await apiFetch("/api/notes");
  if (!d.ok) { out.innerHTML = '<span class="err">❌ ' + d.error + '</span>'; return; }
  out.innerHTML = '<span class="ok">✅ Found ' + d.notes.length + ' note(s)</span>';
  d.notes.forEach(n => {
    const el = document.createElement("div");
    el.className = "record";
    el.innerHTML = '<b>' + escHtml(n.title) + '</b><br>' + escHtml(n.content || "") + '<br><span class="ts">' + n.createdAt + '</span>';
    records.appendChild(el);
  });
}

function escHtml(s) {
  return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

loadEnv();
</script>
</body>
</html>`);
});

// ── ENV INFO ──────────────────────────────────────────────────────────────────
app.get("/api/env", (req, res) => {
  const runtime = process.env.AWS_LAMBDA_FUNCTION_NAME ? "lambda"
    : process.env.ECS_CONTAINER_METADATA_URI ? "ecs"
    : process.env.KUBERNETES_SERVICE_HOST ? "eks"
    : "ec2/local";
  res.json({ bucket: BUCKET, table: TABLE, region: REGION, runtime });
});

// ── UPLOAD IMAGE → S3 ─────────────────────────────────────────────────────────
app.post("/api/upload", upload.single("image"), async (req, res) => {
  if (!BUCKET) return res.json({ ok: false, error: "S3_BUCKET env var not set" });
  if (!req.file) return res.json({ ok: false, error: "No file received" });
  const key = `images/${Date.now()}-${req.file.originalname.replace(/\s/g, "_")}`;
  try {
    await s3.send(new PutObjectCommand({
      Bucket: BUCKET, Key: key,
      Body: req.file.buffer, ContentType: req.file.mimetype,
    }));
    res.json({ ok: true, key });
  } catch (e) {
    res.json({ ok: false, error: e.message });
  }
});

// ── LIST IMAGES FROM S3 ───────────────────────────────────────────────────────
app.get("/api/images", async (req, res) => {
  if (!BUCKET) return res.json({ ok: false, error: "S3_BUCKET env var not set" });
  try {
    const data = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET, Prefix: "images/" }));
    const items = data.Contents || [];
    const images = await Promise.all(items.map(async (obj) => ({
      key: obj.Key,
      url: await getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: obj.Key }), { expiresIn: 300 }),
    })));
    res.json({ ok: true, images });
  } catch (e) {
    res.json({ ok: false, error: e.message });
  }
});

// ── SAVE NOTE → DYNAMODB ──────────────────────────────────────────────────────
app.post("/api/note", async (req, res) => {
  if (!TABLE) return res.json({ ok: false, error: "DYNAMO_TABLE env var not set" });
  const { title, content } = req.body;
  const id = `note-${Date.now()}`;
  try {
    await dynamo.send(new PutItemCommand({
      TableName: TABLE,
      Item: {
        id:        { S: id },
        title:     { S: title || "Untitled" },
        content:   { S: content || "" },
        createdAt: { S: new Date().toISOString() },
      },
    }));
    res.json({ ok: true, id });
  } catch (e) {
    res.json({ ok: false, error: e.message });
  }
});

// ── READ NOTES FROM DYNAMODB ──────────────────────────────────────────────────
app.get("/api/notes", async (req, res) => {
  if (!TABLE) return res.json({ ok: false, error: "DYNAMO_TABLE env var not set" });
  try {
    const data = await dynamo.send(new ScanCommand({ TableName: TABLE }));
    const notes = (data.Items || []).map(i => ({
      id:        i.id?.S,
      title:     i.title?.S,
      content:   i.content?.S,
      createdAt: i.createdAt?.S,
    }));
    res.json({ ok: true, notes });
  } catch (e) {
    res.json({ ok: false, error: e.message });
  }
});

// ── HEALTH CHECK ──────────────────────────────────────────────────────────────
app.get("/health", (req, res) => res.json({ status: "ok" }));

// ── START (not used by Lambda handler) ───────────────────────────────────────
if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => console.log(`Lab running → http://localhost:${PORT}`));
}

module.exports = app;
