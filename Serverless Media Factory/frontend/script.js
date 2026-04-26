// ─── CONFIG — replace these two values after you create your bucket ───────────
const BUCKET_NAME   = "REPLACE_WITH_YOUR_BUCKET_NAME";
const BUCKET_REGION = "us-east-1";          // change if you use a different region
// ──────────────────────────────────────────────────────────────────────────────

const BASE_URL = `https://${BUCKET_NAME}.s3.${BUCKET_REGION}.amazonaws.com`;

// DOM refs
const dropZone    = document.getElementById("drop-zone");
const fileInput   = document.getElementById("file-input");
const uploadBtn   = document.getElementById("upload-btn");
const statusEl    = document.getElementById("status");
const resultsEl   = document.getElementById("results");
const resultsLabel= document.getElementById("results-label");
const chosenName  = document.getElementById("chosen-name");

let selectedFile  = null;
let pollingTimer  = null;

// ── File selection ────────────────────────────────────────────────────────────
fileInput.addEventListener("change", () => {
  if (fileInput.files[0]) pickFile(fileInput.files[0]);
});

dropZone.addEventListener("dragover",  e => { e.preventDefault(); dropZone.classList.add("drag"); });
dropZone.addEventListener("dragleave", ()=> dropZone.classList.remove("drag"));
dropZone.addEventListener("drop", e => {
  e.preventDefault();
  dropZone.classList.remove("drag");
  if (e.dataTransfer.files[0]) pickFile(e.dataTransfer.files[0]);
});

function pickFile(file) {
  selectedFile          = file;
  chosenName.textContent = `Selected: ${file.name}`;
  uploadBtn.style.display = "inline-block";
  uploadBtn.disabled    = false;
  clearResults();
  setStatus("");
}

// ── Upload ────────────────────────────────────────────────────────────────────
uploadBtn.addEventListener("click", async () => {
  if (!selectedFile) return;
  uploadBtn.disabled = true;

  const key = `uploads/${selectedFile.name}`;
  setStatus(`<span class="spinner"></span>Uploading <b>${selectedFile.name}</b> …`);

  try {
    const res = await fetch(`${BASE_URL}/${key}`, {
      method: "PUT",
      headers: { "Content-Type": selectedFile.type || "image/jpeg" },
      body: selectedFile,
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    setStatus(`<span class="spinner"></span>Uploaded! Waiting for Step Functions to process …`);
    startPolling(selectedFile.name);

  } catch (err) {
    setStatus(`❌ Upload failed: ${err.message}`);
    uploadBtn.disabled = false;
  }
});

// ── Poll /processed for the three output files ────────────────────────────────
function startPolling(filename) {
  clearInterval(pollingTimer);
  const baseName = filename.replace(/\.[^.]+$/, "");   // strip extension
  const ext      = filename.split(".").pop();

  const targets = [
    { key: `processed/${baseName}_thumb.${ext}`,  label: "Thumbnail",  tag: "150×150"  },
    { key: `processed/${baseName}_bw.${ext}`,     label: "Grayscale",  tag: "B&W"      },
    { key: `processed/${baseName}_large.${ext}`,  label: "Large",      tag: "1280×720" },
  ];

  // Also show the original
  const originalUrl = `${BASE_URL}/uploads/${filename}`;
  showCard(originalUrl, filename, "Original", true);
  resultsLabel.style.display = "block";

  let found = new Set();

  pollingTimer = setInterval(async () => {
    for (const t of targets) {
      if (found.has(t.key)) continue;
      const url = `${BASE_URL}/${t.key}`;
      try {
        const r = await fetch(url, { method: "HEAD" });
        if (r.ok) {
          found.add(t.key);
          showCard(url, t.label, t.label, false, t.tag);
        }
      } catch (_) { /* not ready yet */ }
    }

    if (found.size === targets.length) {
      clearInterval(pollingTimer);
      setStatus("✅ All three outputs are ready!");
    }
  }, 3000);   // poll every 3 s
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function showCard(url, filename, label, isOriginal = false, tag = "") {
  const card       = document.createElement("div");
  card.className   = "card";
  card.style.animationDelay = `${resultsEl.children.length * 60}ms`;

  const img        = document.createElement("img");
  img.src          = url + "?t=" + Date.now();   // bust cache
  img.alt          = label;

  const meta       = document.createElement("div");
  meta.className   = "card-meta";
  meta.innerHTML   = `
    <span class="label">${label}</span>
    <span class="tag ${isOriginal ? "original" : ""}">${isOriginal ? "original" : tag}</span>
  `;

  card.appendChild(img);
  card.appendChild(meta);
  resultsEl.appendChild(card);
}

function clearResults() {
  resultsEl.innerHTML    = "";
  resultsLabel.style.display = "none";
  clearInterval(pollingTimer);
}

function setStatus(html) {
  statusEl.innerHTML = html;
}
