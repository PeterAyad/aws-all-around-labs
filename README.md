# ☁️ AWS All Around Labs

Welcome to **AWS All Around Labs**\! This repository is a collection of hands-on, step-by-step labs designed to walk you through core AWS services—from basic storage to compute, networking, containers, and identity management.

## 🤔 Why did I make these labs?

AWS is massive. While reading documentation and watching courses is great for theory, the cloud is best learned by *doing*. Configuring VPCs, spinning up EC2 instances, and inevitably breaking (and fixing) IAM permissions is where the real learning happens. I built this repository to bridge the gap between theoretical knowledge and practical execution, giving you a safe, structured way to build muscle memory in the AWS Console.

## 🎯 Who is this for?

* **Beginners:** If you are new to AWS and feeling overwhelmed by the sheer number of services.
* **Certification Hunters:** If you are studying for exams like the *AWS Certified Solutions Architect* or *Developer Associate* and need practical experience to cement the concepts.
* **Developers:** If you want to understand the infrastructure that runs your code, especially how different compute services handle permissions.

## 🚀 How to use these labs

Every completed lab in this repository is designed to be executed directly in the **AWS Management Console**.

1. **Pick a lab** from the table below based on what you want to learn.
2. **Navigate to its folder** in the repository.
3. **Open the `README.md`** inside that folder. It contains clear, step-by-step instructions on what to click, what to configure, and how to verify your setup.
4. **Clean up\!** Always remember to delete your resources after completing a lab to avoid unexpected charges.

-----

## 🛠️ The Labs

| #   | Lab                                                                                 | AWS Services        | What You'll Do                                                                       | Status    |
| --- | ----------------------------------------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------ | --------- |
| 1   | **[Free Services Policy](./Free%20Services%20Policy/)**                             | IAM                 | Apply a guardrail IAM policy that keeps your account inside the free tier.           | 🟢 Ready  |
| 2   | **[Static Website - Phase 1](./Static%20Website%20-%20Phase%201/)**                 | S3                  | Host a static site on S3 with a public bucket policy.                                | 🟢 Ready  |
| 3   | **[Static Website - Phase 2](./Static%20Website%20-%20Phase%202/)**                 | S3, CloudFront      | Re-host the site behind CloudFront with Origin Access Control.                       | 🟢 Ready  |
| 4   | **[Self-Hosted Service](./Self-Hosted%20Service/)**                                 | EC2                 | Deploy a self-hosted app on a public EC2 instance.                                   | 🟢 Ready  |
| 5   | **[Image Gallery App](./Image%20Gallery%20App/)**                                   | EC2, EBS            | Build a gallery, terminate the instance, re-attach EBS — your data survives.         | 🟢 Ready  |
| 6   | **[Large Dataset Download](./Large%20Dataset%20Download/)**                         | EC2, EFS            | Mount EFS on EC2, download data, verify it's shared across instances.                | 🟢 Ready  |
| 7   | **[DynamoDB Playground](./DynamoDB%20Playground/)**                                 | DynamoDB            | Create tables, seed data, and query — all from a browser UI.                         | 🟢 Ready  |
| 8   | **[Stateless API](./Stateless%20API/)**                                             | API Gateway, Lambda | Wire up a REST API backed by a Lambda function.                                      | 🟢 Ready  |
| 9   | **[Single Container App 1](./Single%20Container%20App%201/)**                       | ECS, Fargate        | Deploy and manage a containerized application using Elastic Container Service.       | 🟢 Ready  |
| 10  | **[Single Container App 2](./Single%20Container%20App%202/)**                       | EKS                 | Deploy and manage a containerized application using Elastic Kubernetes Service.      | 🟢 Ready  |
| 11  | **[Three-tier Application - Phase 1](./Three-tier%20Application%20-%20Phase%201/)** | VPC, RDS, EC2       | Spin up a full 3-tier app (DB + backend + frontend) across public & private subnets. | 🟢 Ready  |
| 12  | **[Three-tier Application - Phase 2](./Three-tier%20Application%20-%20Phase%202/)** | ELB, Auto Scaling   | Add load balancing and high availability to the 3-tier architecture.                 | 🟢 Ready  |
| 13  | **[EC2 Access Lab](./Service%20Access%20Labs/)**                                    | IAM, EC2            | Learn how EC2 instances securely access AWS resources via Instance Profiles.         | 🟢 Ready  |
| 14  | **[Lambda Access Lab](./Service%20Access%20Labs/)**                                 | IAM, Lambda         | Understand Lambda Execution Roles and how credentials refresh dynamically.           | 🟢 Ready  |
| 15  | **[ECS Access Lab](./Service%20Access%20Labs/)**                                    | IAM, ECS            | Learn the critical difference between ECS infrastructure roles and task-level roles. | 🟢 Ready  |
| 16  | **[EKS Access Lab](./Service%20Access%20Labs/)**                                    | IAM, EKS            | Explore pod-scoped permissions (IRSA via OIDC) inside a Kubernetes cluster.          | 🟢 Ready  |
| 17  | **[Order Processing](./Order%20Processing/)**                                       | SNS, SQS, Lambda    | Fan out a single order event to three independent queues and observe DLQ behavior.   | 🟢 Ready  |

-----

*Note: Labs marked with 🚧 are currently being built out. Check back soon for the full step-by-step guides\!*
