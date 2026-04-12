# Steps to Secure Your AWS Free Tier

1. **Create a Custom Policy**
    Go to **AWS IAM** > **Policies** > **Create Policy**. Use the configuration provided in [Policy.json](./policy.json) to define specific permissions.

2. **Provision a New User**
    Navigate to **AWS IAM** > **Users** and create a new user. Attach the policy you just created to ensure the account is properly constrained.

3. **Operate via the Restricted User**
    Log in with the new user account for your daily tasks. This helps prevent accidental charges and follows the principle of least privilege for your AWS Free Tier.

---

> **Tip:** If you need to view other services without making changes, attach the AWS-managed policy **ReadOnlyAccess** to your user.
