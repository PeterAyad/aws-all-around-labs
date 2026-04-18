# 🛰 Lab — EKS + Node Role (ECR Image Pull)

**What you'll learn:** EKS has two IAM layers students always confuse. The **cluster role** is for the Kubernetes control plane. The **node role** is for EC2 worker nodes — and it's the node that pulls your private image from ECR *before the pod starts*. Without the right policy on the node role, every pod you deploy lands in `ImagePullBackOff`. You'll build the VPC, cluster, ECR access, and both roles from the console.

> ⚠️ This is a heavy setup lab, but every AWS resource is created through the console. Only the final Kubernetes deployment uses `kubectl`.

---

## Step 1 — Create the VPC

EKS needs a VPC with public and private subnets — and specific tags so Kubernetes can discover them.

1. Open the **VPC** console → **Your VPCs** → **Create VPC**
2. Select **VPC and more** at the top

3. Fill in:

   | Setting                      | Value                             |
   | ---------------------------- | --------------------------------- |
   | Name tag                     | `mission-control-vpc`             |
   | IPv4 CIDR                    | `10.0.0.0/16`                     |
   | Number of Availability Zones | `2`                               |
   | Number of public subnets     | `2`                               |
   | Number of private subnets    | `2`                               |
   | NAT gateways                 | **In 1 AZ** *(reduces lab costs)* |
   | VPC endpoints                | None                              |

4. **Create VPC** — ⏳ wait ~2 minutes

### Tag subnets for EKS

EKS needs specific tags on subnets so the Kubernetes Cloud Controller knows which ones to use for auto-provisioning load balancers.

1. **VPC** → **Subnets** → for each **public subnet**:
   - Click the subnet → **Tags** tab → **Manage tags** → **Add tag**
   - Key: `kubernetes.io/role/elb` | Value: `1`
   - Key: `kubernetes.io/cluster/mission-control-cluster` | Value: `shared`
   - **Save**

2. For each **private subnet**:
   - Key: `kubernetes.io/role/internal-elb` | Value: `1`
   - Key: `kubernetes.io/cluster/mission-control-cluster` | Value: `shared`
   - **Save**

---

## Step 2 — Push the Docker Image to ECR (Private)

### Create the ECR repository

1. **ECR** → **Private registry** → **Repositories** → **Create repository**
2. **Visibility:** Private | **Name:** `mission-control` → **Create repository**

### Build and push

1. Click into `mission-control` → **View push commands**
2. Follow the 4 commands shown in your terminal from the `shared/` folder
3. Confirm the `latest` tag appears in the repository

> The image is **private**. No node can pull it without the correct IAM permissions. This is exactly why the node role exists.

---

## Step 3 — Create the EKS Cluster Role 🔐

EKS itself (the control plane) needs an IAM role to manage AWS resources.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **EKS** → **EKS - Cluster** → **Next**
3. The `AmazonEKSClusterPolicy` is pre-selected → **Next**
4. **Role name:** `mission-control-cluster-role` → **Create role**

---

## Step 4 — Create the Node Group Role 🔐

This is the heart of the lab. EC2 worker nodes assume this role. It gives them permission to join the EKS cluster, configure pod networking, and — critically — **pull your private image from ECR**.

1. **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **EC2** → **Next**
3. Search and attach these **three** managed policies:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly` ← *this lets nodes pull your app image from ECR*
4. **Role name:** `mission-control-node-role` → **Create role**

### Attach App Permissions (ECR Pull)

Instead of using the broad AWS managed ECR policy (`AmazonEC2ContainerRegistryReadOnly`), you can create an explicit inline policy so you can see exactly what permissions the node needs to pull images:

1. Click into `mission-control-node-role` → **Add permissions** → **Create inline policy** → **JSON** tab:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "ECRAuth",
          "Effect": "Allow",
          "Action": "ecr:GetAuthorizationToken",
          "Resource": "*"
        },
        {
          "Sid": "ECRPullImage",
          "Effect": "Allow",
          "Action": [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ],
          "Resource": "arn:aws:ecr:YOUR_REGION:YOUR_ACCOUNT_ID:repository/mission-control"
        }
      ]
    }
    ```

2. Replace `YOUR_REGION` (e.g., `us-east-1`) and `YOUR_ACCOUNT_ID` with your values
3. **Policy name:** `mission-control-ecr-pull-policy` → **Create policy**

> **Notice:** `ecr:GetAuthorizationToken` must be `Resource: "*"` — it's a global API call that returns a Docker login token for your registry. There's no specific resource ARN to scope it to. The actual image pull actions are scoped to your specific repository.

---

## Step 5 — Create the EKS Cluster

1. Open the **EKS** console → **Clusters** → **Create cluster** (**Custom Configuration** mode)
2. **Disable EKS Auto Mode / Compute configuration (must be OFF to use managed node groups)**
3. **Step 1 — Configure cluster:**
   - **Name:** `mission-control-cluster`
   - **Kubernetes version:** latest available
   - **Cluster service role:** `mission-control-cluster-role`
   - → **Next**

4. **Step 2 — Specify networking:**
   - **VPC:** `mission-control-vpc`
   - **Subnets:** select all 4 subnets (2 public + 2 private)
   - **Security groups:** leave the default selected
   - **Cluster endpoint access:** **Public and private**
   - → **Next**

5. **Step 3 — Configure observability:** leave defaults → **Next**
6. **Step 4 — Select add-ons:** leave defaults (CoreDNS, kube-proxy, Amazon VPC CNI) → **Next**
7. **Step 5:** leave defaults → **Next** → **Create**

⏳ Cluster creation takes **10–15 minutes**. Status changes from `Creating` to `Active`.

---

## Step 6 — Add a Node Group

1. In the EKS console, click into `mission-control-cluster` → **Compute** tab → **Add node group**
2. **Name:** `mission-control-nodes`
3. **Node IAM role:** `mission-control-node-role` ← *this is what grants ECR access*
4. → **Next**
5. **Instance type:** `t3.small`
6. **Scaling:** Desired `2`, Min `1`, Max `3`
7. → **Next**
8. **Subnets:** select only the **private subnets** *(nodes should not be directly public)*
9. → **Next** → **Create**

⏳ Wait ~5 minutes until nodes show `Active`.

---

## Step 7 — Connect kubectl and Deploy

### Configure kubectl

```bash
aws eks update-kubeconfig --name mission-control-cluster --region us-east-1
kubectl get nodes   # should show 2 nodes in Ready state
```

### Create k8s.yaml

Fill in `YOUR_IMAGE_URI` (copy from ECR → your repo → URI shown at top + `:latest`):

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mission-control
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mission-control
  template:
    metadata:
      labels:
        app: mission-control
    spec:
      containers:
      - name: app
        image: YOUR_IMAGE_URI
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: mission-control-svc
spec:
  type: LoadBalancer
  selector:
    app: mission-control
  ports:
  - port: 80
    targetPort: 80
```

```bash
kubectl apply -f k8s.yaml

# Wait for the pods to run
kubectl get pods -w

# Wait for the external load balancer IP (~2-3 min as AWS provisions it)
kubectl get svc mission-control-svc --watch
```

If pods land in `ImagePullBackOff`, the node role is missing an ECR permission — re-check Step 4.
Otherwise, open `http://<EXTERNAL-IP>` in your browser 🎉

---

## Step 8 — Understand What Just Happened

Go to **EKS** → `mission-control-cluster` → **Resources** → **Pods** → click a running pod.

You'll see the pod is running with no IAM role annotation (`ServiceAccount`) — it doesn't need one. Our app is a static dashboard that doesn't call any AWS services at runtime.

The container is in a private subnet with no public IP. Traffic flows:

```txt
Browser → Internet Gateway → NLB (public subnet) → Pod (private subnet, port 80)

Pod startup (outbound via NAT Gateway):
  → ECR  (node pulls the image using mission-control-node-role)
  → EKS control plane  (node registers itself using AmazonEKSWorkerNodePolicy)
```

---

## 🔴 Break It: Node Role (ECR pull)

1. **IAM** → `mission-control-node-role` → click `mission-control-ecr-pull-policy` → **Edit**
2. Delete the `ECRPullImage` statement (the one with `ecr:BatchGetImage`) → **Save**
3. Force a pod restart:

   ```bash
   kubectl rollout restart deployment/mission-control
   ```

4. Watch the pods:

   ```bash
   kubectl get pods -w
   ```

   New pods will appear and get stuck. Then:

   ```bash
   kubectl describe pod <new-pod-name>
   ```

   Scroll to **Events** at the bottom:

   ```txt
   Failed to pull image "...": ... is not authorized to perform: ecr:BatchGetImage
   ```

5. Restore the permission → **Save**, then:

   ```bash
   kubectl rollout restart deployment/mission-control
   kubectl get pods -w
   ```

   Pods recover and return to `Running`.

> The failure happens at the **node level** before any Kubernetes pod code runs — containerd on the node tried to pull the image and was denied by IAM.

## 🔴 Break It: ECRAuth (the token call)

Remove only `ecr:GetAuthorizationToken` and see a different failure mode.

1. **IAM** → `mission-control-node-role` → `mission-control-ecr-pull-policy` → **Edit**
2. Delete only the `ECRAuth` statement → **Save**
3. Force a restart: `kubectl rollout restart deployment/mission-control`
4. `kubectl describe pod <new-pod-name>` → **Events:**

   ```txt
   Failed to pull image "...": no basic auth credentials
   ```

5. Restore the permission → restart → pods recover.

> **Key difference:** `GetAuthorizationToken` is step 1 — exchanging your IAM identity for a short-lived Docker login token. `BatchGetImage` is step 2 — fetching the actual image layers. Both are required. Removing either breaks the pull in a different way.

---

## 🧹 Cleanup

```bash
kubectl delete -f k8s.yaml
```

Then in the console (order matters):

1. **EKS** → `mission-control-cluster` → **Compute** → delete node group `mission-control-nodes` → wait until deleted
2. **EKS** → delete cluster `mission-control-cluster`
3. **IAM** → delete `mission-control-node-role` and `mission-control-cluster-role`
4. **ECR** → delete `mission-control` repository
5. **VPC** → **NAT Gateways** → delete → ⏳ wait until deleted
6. **VPC** → **Elastic IPs** → release the IP that was used by the NAT gateway
7. **VPC** → delete `mission-control-vpc`
