# Steps

1. **Create S3 bucket** — block all public access
2. **Upload** `index.html` to the bucket
3. **Create CloudFront distribution** — origin points to the S3 bucket, don't set default root object to `index.html`, disable WAF, enable OAC
4. **Visit** your `*.cloudfront.net` URL appended by `/index.html`
5. (optional) **point** your domain name to this URL
