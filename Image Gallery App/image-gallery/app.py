#!/usr/bin/env python3
"""
EBS Image Gallery — A minimal image gallery server for AWS EBS persistence labs.
All data (images + metadata) is stored under DATA_DIR which should be on an EBS volume.
"""

import os
import json
import uuid
import mimetypes
from datetime import datetime
from pathlib import Path
from flask import (
    Flask, request, jsonify, send_from_directory,
    redirect, url_for, abort
)
from werkzeug.utils import secure_filename

# ─── Config ──────────────────────────────────────────────────────────────────
DATA_DIR    = os.environ.get("DATA_DIR", "/mnt/data/gallery")
UPLOAD_DIR  = os.path.join(DATA_DIR, "images")
META_FILE   = os.path.join(DATA_DIR, "metadata.json")
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
MAX_MB      = int(os.environ.get("MAX_MB", "50"))
PORT        = int(os.environ.get("PORT", "8080"))

# ─── Init ─────────────────────────────────────────────────────────────────────
app = Flask(__name__, static_folder="static")
app.config["MAX_CONTENT_LENGTH"] = MAX_MB * 1024 * 1024

Path(UPLOAD_DIR).mkdir(parents=True, exist_ok=True)
if not os.path.exists(META_FILE):
    with open(META_FILE, "w") as f:
        json.dump([], f)


# ─── Helpers ──────────────────────────────────────────────────────────────────
def load_meta():
    with open(META_FILE, "r") as f:
        return json.load(f)

def save_meta(data):
    with open(META_FILE, "w") as f:
        json.dump(data, f, indent=2)

def allowed(filename):
    return Path(filename).suffix.lower() in ALLOWED_EXT


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return send_from_directory("static", "index.html")

@app.route("/api/images", methods=["GET"])
def list_images():
    return jsonify(load_meta())

@app.route("/api/upload", methods=["POST"])
def upload():
    if "file" not in request.files:
        return jsonify({"error": "No file field"}), 400
    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400
    if not allowed(file.filename):
        return jsonify({"error": f"File type not allowed. Use: {', '.join(ALLOWED_EXT)}"}), 400

    ext      = Path(secure_filename(file.filename)).suffix.lower()
    img_id   = str(uuid.uuid4())
    filename = img_id + ext
    filepath = os.path.join(UPLOAD_DIR, filename)
    file.save(filepath)
    size = os.path.getsize(filepath)

    record = {
        "id":           img_id,
        "filename":     filename,
        "original":     secure_filename(file.filename),
        "caption":      request.form.get("caption", "").strip(),
        "uploaded_at":  datetime.utcnow().isoformat() + "Z",
        "size_bytes":   size,
    }
    meta = load_meta()
    meta.insert(0, record)   # newest first
    save_meta(meta)
    return jsonify(record), 201

@app.route("/api/images/<img_id>", methods=["DELETE"])
def delete_image(img_id):
    meta = load_meta()
    record = next((r for r in meta if r["id"] == img_id), None)
    if not record:
        return jsonify({"error": "Not found"}), 404
    filepath = os.path.join(UPLOAD_DIR, record["filename"])
    if os.path.exists(filepath):
        os.remove(filepath)
    meta = [r for r in meta if r["id"] != img_id]
    save_meta(meta)
    return jsonify({"deleted": img_id})

@app.route("/api/images/<img_id>/caption", methods=["PATCH"])
def update_caption(img_id):
    body = request.get_json(silent=True) or {}
    caption = body.get("caption", "").strip()
    meta = load_meta()
    for r in meta:
        if r["id"] == img_id:
            r["caption"] = caption
            save_meta(meta)
            return jsonify(r)
    return jsonify({"error": "Not found"}), 404

@app.route("/images/<filename>")
def serve_image(filename):
    return send_from_directory(UPLOAD_DIR, filename)

@app.route("/api/status")
def status():
    meta = load_meta()
    total_bytes = sum(r.get("size_bytes", 0) for r in meta)
    return jsonify({
        "status":        "ok",
        "image_count":   len(meta),
        "total_size_mb": round(total_bytes / 1024 / 1024, 2),
        "data_dir":      DATA_DIR,
        "server_time":   datetime.utcnow().isoformat() + "Z",
    })


if __name__ == "__main__":
    print(f"[gallery] Data dir : {DATA_DIR}")
    print(f"[gallery] Listening: http://0.0.0.0:{PORT}")
    app.run(host="0.0.0.0", port=PORT)
