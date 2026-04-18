# 🔐 Lab 4 — EKS + IRSA (IAM Roles for Service Accounts)

**What you'll learn:** IRSA is the most advanced AWS IAM pattern. Your Kubernetes pod gets its own IAM role via a service account, scoped using OIDC identity federation. Two pods on the same node can have completely different AWS permissions. You'll build the VPC, cluster, ECR access, and IRSA trust from the console.

> ⚠️ This is the most involved lab. EKS setup is heavy — but every AWS resource is created through the console. Only the final Kubernetes deployment uses `kubectl`.

---

## Step 1 — Create an S3 Bucket

1. **S3** → **Create bucket** → name: `iam-lab-yourname` → region: `us-east-1` → **Create bucket**

---

## Step 2 — Create a DynamoDB Table

1. **DynamoDB** → **Tables** → **Create table** → name: `iam-lab-notes` → partition key: `id` (String) → **Create table**

---

## Step 3 — Create the VPC

EKS needs a VPC with public and private subnets — and specific tags so Kubernetes can discover them.

1. Open the **VPC** console → **Your VPCs** → **Create VPC**
2. Select **VPC and more** at the top

3. Fill in:

   | Setting                      | Value         |
   | ---------------------------- | ------------- |
   | Name tag                     | `iam-lab-vpc` |
   | IPv4 CIDR                    | `10.0.0.0/16` |
   | Number of Availability Zones | `2`           |
   | Number of public subnets     | `2`           |
   | Number of private subnets    | `2`           |
   | NAT gateways                 | **In 1 AZ**   |
   | VPC endpoints                | None          |

4. **Create VPC** — ⏳ wait ~2 minutes

### Tag subnets for EKS

EKS needs specific tags on subnets so the Kubernetes Cloud Controller knows which ones to use for auto-provisioning load balancers.

1. **VPC** → **Subnets** → for each **public subnet**:
   - Click the subnet → **Tags** tab → **Manage tags** → **Add tag**
   - Key: `kubernetes.io/role/elb` | Value: `1`
   - Key: `kubernetes.io/cluster/iam-lab-cluster` | Value: `shared`
   - **Save**

2. For each **private subnet**:
   - Key: `kubernetes.io/role/internal-elb` | Value: `1`
   - Key: `kubernetes.io/cluster/iam-lab-cluster` | Value: `shared`
   - **Save**

---

## Step 4 — Push the Docker Image to ECR (Private)

### Create the ECR repository

1. **ECR** → **Private registry** → **Repositories** → **Create repository**
2. **Visibility:** Private | **Name:** `iam-lab-app` → **Create repository**

### Build and push

1. Click into `iam-lab-app` → **View push commands**
2. Follow the 4 commands shown in your terminal from the `shared/` folder
3. Confirm the `latest` tag appears in the repository

---

## Step 5 — Create the EKS Cluster IAM Role

EKS itself (the control plane) needs an IAM role to manage AWS resources like load balancers.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **EKS** → **EKS - Cluster** → **Next**
3. The `AmazonEKSClusterPolicy` is pre-selected → **Next**
4. **Role name:** `iam-lab-eks-cluster-role` → **Create role**

---

## Step 6 — Create the Node Group IAM Role

EC2 worker nodes need their own IAM role to join the cluster, route traffic, and pull images.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **EC2** → **Next**
3. Search and attach these three managed policies:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly` ← *this lets nodes pull your app image from ECR*
4. **Role name:** `iam-lab-eks-node-role` → **Create role**

---

## Step 7 — Create the EKS Cluster

1. Open the **EKS** console → **Clusters** → **Create cluster** (**Custom Configuration** mode)
2. **Disable EKS Auto Mode / Compute configuration (must be OFF to use managed node groups)**
3. **Step 1 — Configure cluster:**
   - **Name:** `iam-lab-cluster`
   - **Kubernetes version:** latest available
   - **Cluster service role:** `iam-lab-eks-cluster-role`
   - → **Next**

4. **Step 2 — Specify networking:**
   - **VPC:** `iam-lab-vpc`
   - **Subnets:** select all 4 subnets (2 public + 2 private)
   - **Security groups:** leave the default selected (EKS will auto-create the necessary security group)
   - **Cluster endpoint access:** **Public and private**
   - → **Next**

5. **Step 3 — Configure observability:** leave defaults → **Next**
6. **Step 4 — Select add-ons:** leave defaults (CoreDNS, kube-proxy, Amazon VPC CNI) → **Next**
7. **Step 5:** leave defaults → **Next** → **Create**

⏳ Cluster creation takes **10–15 minutes**. Status changes from `Creating` to `Active`.

---

## Step 8 — Add a Node Group

1. In the EKS console, click into `iam-lab-cluster` → **Compute** tab → **Add node group**
2. **Name:** `lab-nodes`
3. **Node IAM role:** `iam-lab-eks-node-role`
4. → **Next**
5. **Instance type:** `t3.small`
6. **Scaling:** Desired `1`, Min `1`, Max `2`
7. → **Next**
8. **Subnets:** select only the **private subnets** *(nodes should not be directly public)*
9. → **Next** → **Create**

⏳ Waits ~5 minutes until nodes show `Active`.

---

## Step 9 — Enable the OIDC Identity Provider 🔐

This is what makes IRSA possible. You're telling AWS IAM: *"Trust the identity tokens issued by this EKS cluster."*

1. Click into `iam-lab-cluster` → **Overview** tab
2. Find the field **OpenID Connect provider URL** — it looks like `https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE123`
3. Copy that URL

4. Open **IAM** → **Identity providers** → **Add provider**
5. **Provider type:** OpenID Connect
6. **Provider URL:** paste the URL you copied → click **Get thumbprint** *(AWS fetches and verifies the certificate)*
7. **Audience:** `sts.amazonaws.com`
8. **Add provider**

You'll see it appear in the Identity providers list. EKS will now be able to issue JWT tokens that AWS STS accepts.

---

## Step 10 — Create the IRSA IAM Role 🔐

This role will be assumed by your specific Kubernetes service account — scoped to it and nothing else.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity type:** **Web identity**
3. **Identity provider:** select the OIDC provider you just added
4. **Audience:** `sts.amazonaws.com`
5. → **Next** → skip permissions → **Next**
6. **Role name:** `eks-iam-lab-role` → **Create role**

### Tighten the trust policy

The default trust allows any service account in the cluster. Tighten it to only your specific service account.

1. Click into `eks-iam-lab-role` → **Trust relationships** tab → **Edit trust policy**

    Find your OIDC URL — it's the part after `https://` from your cluster overview. Replace the full policy:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/[oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID](https://oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID)"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
            "StringEquals": {
              "[oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID:sub](https://oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID:sub)": "system:serviceaccount:default:iam-lab-sa",
              "[oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID:aud](https://oidc.eks.us-east-1.amazonaws.com/id/YOUR_OIDC_ID:aud)": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
    ```

    > **How to fill in the values:**
    >
    > - `YOUR_ACCOUNT_ID` — visible in the top-right corner of the AWS console
    > - `YOUR_OIDC_ID` — the hex string at the end of the OIDC provider URL (e.g. `EXAMPLED539D4633E53DE1B71EXAMPLE`)

2. **Update policy**

### Attach App Permissions (S3 & DynamoDB)

Your app code needs to interact with the S3 bucket and DynamoDB table. We attach these permissions directly to the pod's IRSA role:

1. **Add permissions** → **Create inline policy** → **JSON** tab:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "S3Access",
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket"
          ],
          "Resource": [
            "arn:aws:s3:::iam-lab-yourname",
            "arn:aws:s3:::iam-lab-yourname/*"
          ]
        },
        {
          "Sid": "DynamoDBAccess",
          "Effect": "Allow",
          "Action": [
            "dynamodb:PutItem",
            "dynamodb:Scan"
          ],
          "Resource": "arn:aws:dynamodb:us-east-1:*:table/iam-lab-notes"
        }
      ]
    }
    ```

2. Replace `iam-lab-yourname` with your bucket name
3. **Policy name:** `eks-iam-lab-policy` → **Create policy**

> **Important Note:** Notice we didn't add ECR permissions here. ECR image pulling in EKS is handled by the **node role** (`AmazonEC2ContainerRegistryReadOnly` you attached in Step 6). The node pulls the image before the pod starts. The IRSA role you just created is *only* used by your running app code.

---

## Step 11 — Connect kubectl and Deploy

### Configure kubectl

```bash
aws eks update-kubeconfig --name iam-lab-cluster --region us-east-1
kubectl get nodes   # should show 1 node in Ready state
```

### Create k8s.yaml

Fill in `YOUR_ACCOUNT_ID` and `YOUR_IMAGE_URI` (copy from ECR → your repo → URI shown at top + `:latest`):

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: iam-lab-sa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-iam-lab-role
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iam-lab-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: iam-lab
  template:
    metadata:
      labels:
        app: iam-lab
    spec:
      serviceAccountName: iam-lab-sa
      containers:
      - name: app
        image: YOUR_IMAGE_URI
        ports:
        - containerPort: 3000
        env:
        - name: S3_BUCKET
          value: "iam-lab-yourname"
        - name: DYNAMO_TABLE
          value: "iam-lab-notes"
        - name: AWS_REGION
          value: "us-east-1"
---
apiVersion: v1
kind: Service
metadata:
  name: iam-lab-svc
spec:
  type: LoadBalancer
  selector:
    app: iam-lab
  ports:
  - port: 80
    targetPort: 3000
```

```bash
kubectl apply -f k8s.yaml

# Wait for the external load balancer IP (~2-3 min as AWS provisions it)
kubectl get svc iam-lab-svc --watch
```

Open `http://<EXTERNAL-IP>` in your browser 🎉

---

## Step 12 — Verify IRSA from Inside the Pod

```bash
# Shell into the running pod
kubectl exec -it deploy/iam-lab-app -- sh

# IRSA injects two env vars — no access keys anywhere
echo $AWS_ROLE_ARN
echo $AWS_WEB_IDENTITY_TOKEN_FILE

# The token is a Kubernetes-signed JWT — STS exchanges it for temporary credentials
cat $AWS_WEB_IDENTITY_TOKEN_FILE

exit
```

### See it in the AWS console

1. Open **CloudTrail** → **Event history**
2. **Filter:** Event name = `AssumeRoleWithWebIdentity`
3. Click an event → expand **userIdentity** → you'll see `system:serviceaccount:default:iam-lab-sa` as the subject
4. This is proof: Kubernetes issued the token, STS accepted it, your pod got credentials

---

## 🔴 Break It: IRSA (remove the role annotation)

```bash
# Remove the IAM role annotation from the service account
kubectl annotate serviceaccount iam-lab-sa [eks.amazonaws.com/role-arn-](https://eks.amazonaws.com/role-arn-)

# Restart the pods so they pick up the change
kubectl rollout restart deployment/iam-lab-app
```

Try any action in the app → `CredentialsProviderError` — no role means no credentials at all.

Restore and verify:

```bash
kubectl annotate serviceaccount iam-lab-sa \
  [eks.amazonaws.com/role-arn=arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-iam-lab-role](https://eks.amazonaws.com/role-arn=arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-iam-lab-role)
kubectl rollout restart deployment/iam-lab-app
```

## 🔴 Break It: Node Role (ECR pull)

1. **IAM** → `iam-lab-eks-node-role` → remove `AmazonEC2ContainerRegistryReadOnly` → **Save**
2. Force a pod restart: `kubectl rollout restart deployment/iam-lab-app`
3. `kubectl get pods` → pod stuck in `ImagePullBackOff`
4. `kubectl describe pod <pod-name>` → see the exact ECR authorization error
5. Re-attach the policy → restart → pod recovers

> **Key difference from ECS:** In EKS, the *node* pulls the image (using the node role), but the *pod* calls your app's AWS services (using IRSA). These are two different IAM identities on the same machine.

---

## 🧹 Cleanup

```bash
kubectl delete -f k8s.yaml
```

Then in the console (order matters):

1. **EKS** → `iam-lab-cluster` → **Compute** → delete node group `lab-nodes` → wait until deleted
2. **EKS** → delete cluster `iam-lab-cluster`
3. **IAM** → delete `eks-iam-lab-role`, `iam-lab-eks-node-role`, `iam-lab-eks-cluster-role`
4. **IAM** → **Identity providers** → delete the OIDC provider
5. **ECR** → delete `iam-lab-app` repository
6. **VPC** → **NAT Gateways** → delete → wait until deleted
7. **VPC** → **Elastic IPs** → release
8. **VPC** → delete `iam-lab-vpc`
9. **S3** → empty → delete | **DynamoDB** → delete table
