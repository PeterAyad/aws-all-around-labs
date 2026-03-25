# Steps

1. **Create S3 bucket** - don't block public access
2. **Upload** `index.html` to the bucket
3. **Paste** `bucket-policy.json` into the bucket's Permissions → Bucket Policy (**fill in** the placeholders first)
4. **Enable** static website hosting in bucket's properties and copy the URL
5. **Visit** your URL
6. (optional) **point** your domain name to this URL
