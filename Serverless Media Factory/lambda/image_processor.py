import boto3
import os
from PIL import Image
import io

s3 = boto3.client("s3")

def lambda_handler(event, context):
    """
    Triggered by Step Functions.
    Expects:
      event = {
        "bucket": "my-media-bucket",
        "key": "uploads/vacation.jpg",
        "mode": "thumbnail" | "grayscale" | "large"
      }
    """

    bucket = event["bucket"]
    key    = event["key"]
    mode   = event["mode"]

    # ── 1. Download the original image from S3 ──────────────────────────────
    response = s3.get_object(Bucket=bucket, Key=key)
    image_data = response["Body"].read()
    img = Image.open(io.BytesIO(image_data)).convert("RGB")

    # ── 2. Process based on mode ─────────────────────────────────────────────
    if mode == "thumbnail":
        img.thumbnail((150, 150))
        suffix = "_thumb"

    elif mode == "grayscale":
        img = img.convert("L").convert("RGB")  # keep 3-channel for JPEG
        suffix = "_bw"

    elif mode == "large":
        img = img.resize((1280, 720), Image.LANCZOS)
        suffix = "_large"

    else:
        raise ValueError(f"Unknown mode: {mode}")

    # ── 3. Build output key:  uploads/vacation.jpg → processed/vacation_thumb.jpg
    filename   = os.path.basename(key)                    # vacation.jpg
    name, ext  = os.path.splitext(filename)               # vacation  .jpg
    output_key = f"processed/{name}{suffix}{ext}"         # processed/vacation_thumb.jpg

    # ── 4. Upload result to /processed ──────────────────────────────────────
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG", quality=85)
    buffer.seek(0)

    s3.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=buffer,
        ContentType="image/jpeg",
    )

    return {
        "statusCode": 200,
        "input_key":  key,
        "output_key": output_key,
        "mode":       mode,
    }
