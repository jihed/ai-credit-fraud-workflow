# EKS Pod Identity Migration Guide

## Overview

This document explains the migration from IRSA (IAM Roles for Service Accounts) to EKS Pod Identity for application workloads in the fraud detection JARK stack.

## What is EKS Pod Identity?

EKS Pod Identity is a newer, simpler way to provide AWS permissions to pods running on Amazon EKS. It eliminates the need for OIDC providers and complex role trust policies, making it easier to manage and more secure.

### Benefits of Pod Identity over IRSA:
- ✅ **Simpler Setup**: No OIDC provider configuration needed
- ✅ **Better Security**: Uses AWS STS directly with pod-level authentication
- ✅ **Easier Management**: Direct association between service accounts and IAM roles
- ✅ **Reduced Complexity**: No need for complex trust policies
- ✅ **Better Auditing**: Clearer audit trails in CloudTrail

## Migration Strategy

### Components Using Pod Identity (Migrated)
1. **JupyterHub**: Notebook environment authentication
2. **Ray Cluster**: Distributed ML workload authentication
3. **Argo Workflows**: Pipeline orchestration authentication

### Components Still Using IRSA (System Level)
1. **VPC CNI**: Core networking component
2. **EBS CSI Driver**: Storage provisioning
3. **Karpenter**: Node provisioning (via blueprints addon)
4. **AWS Load Balancer Controller**: Load balancer management
5. **FluentBit**: Log forwarding

## Implementation Details

### 1. JupyterHub Pod Identity

**Before (IRSA):**
```hcl
module "jupyterhub_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["jupyterhub:jupyterhub"]
    }
  }
}
```

**After (Pod Identity):**
```hcl
resource "aws_iam_role" "jupyterhub_pod_identity_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "jupyterhub" {
  cluster_name    = module.eks.cluster_name
  namespace       = "jupyterhub"
  service_account = "jupyterhub"
  role_arn        = aws_iam_role.jupyterhub_pod_identity_role.arn
}
```

### 2. Ray Cluster Pod Identity

**Key Changes:**
- Removed IRSA module and OIDC configuration
- Created dedicated Pod Identity role with S3 access
- Associated role with `ray-service-account` in `ray-clusters` namespace

**Permissions:**
- S3 read/write access for model storage and data processing
- No EMR permissions needed (Ray handles its own workloads)

### 3. Argo Workflows Pod Identity

**Key Changes:**
- Migrated both `argo-workflows-sa` and `argo-server` service accounts
- Combined S3 and EMR permissions in single Pod Identity role
- Simplified trust policy using `pods.eks.amazonaws.com` service

**Permissions:**
- S3 access for workflow artifacts and data
- EMR access for submitting Spark jobs
- IAM PassRole for EMR job execution

## Service Account Configuration

### JupyterHub Service Accounts
```yaml
# Hub service account (automatic)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jupyterhub
  namespace: jupyterhub

# User service account (for notebook pods)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jupyterhub-user-sa
  namespace: jupyterhub
```

### Ray Service Account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ray-service-account
  namespace: ray-clusters
```

### Argo Workflows Service Accounts
```yaml
# Workflow execution service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflows-sa
  namespace: argo-workflows

# Server service account (automatic)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-server
  namespace: argo-workflows
```

## Verification Commands

### Check Pod Identity Associations
```bash
# List all Pod Identity associations
aws eks list-pod-identity-associations --cluster-name fraud-detection-emr-eks

# Describe specific association
aws eks describe-pod-identity-association \
  --cluster-name fraud-detection-emr-eks \
  --association-id <association-id>
```

### Test Pod Authentication
```bash
# Test from JupyterHub pod
kubectl exec -n jupyterhub <pod-name> -- aws sts get-caller-identity

# Test from Ray pod
kubectl exec -n ray-clusters <pod-name> -- aws sts get-caller-identity

# Test from Argo pod
kubectl exec -n argo-workflows <pod-name> -- aws sts get-caller-identity
```

### Check Service Account Annotations
```bash
# JupyterHub (should NOT have IRSA annotation)
kubectl get sa -n jupyterhub jupyterhub -o yaml

# Ray (should NOT have IRSA annotation)
kubectl get sa -n ray-clusters ray-service-account -o yaml

# Argo (should NOT have IRSA annotation)
kubectl get sa -n argo-workflows argo-workflows-sa -o yaml
```

## Troubleshooting

### Common Issues

1. **Pod Identity Agent Not Running**
   ```bash
   kubectl get pods -n kube-system | grep pod-identity-agent
   ```
   **Solution**: Ensure `eks-pod-identity-agent` addon is enabled in cluster configuration.

2. **Association Not Found**
   ```bash
   aws eks list-pod-identity-associations --cluster-name <cluster-name>
   ```
   **Solution**: Check that Pod Identity associations were created successfully in Terraform.

3. **Permission Denied**
   ```bash
   kubectl logs -n <namespace> <pod-name>
   ```
   **Solution**: Verify IAM role has correct policies attached and trust relationship.

### Debug Commands
```bash
# Check Pod Identity addon status
aws eks describe-addon --cluster-name <cluster-name> --addon-name eks-pod-identity-agent

# View pod identity associations
kubectl get podidentityassociation -A

# Check IAM role trust policy
aws iam get-role --role-name <role-name>

# View role policies
aws iam list-attached-role-policies --role-name <role-name>
```

## Migration Benefits Realized

### Security Improvements
- **Reduced Attack Surface**: No OIDC provider endpoints to secure
- **Better Isolation**: Pod-level authentication vs. service account level
- **Simplified Trust**: Direct AWS service trust vs. complex OIDC trust

### Operational Benefits
- **Easier Debugging**: Clearer authentication flow
- **Better Monitoring**: Enhanced CloudTrail logging
- **Simplified Management**: Direct role-to-service-account mapping

### Performance Benefits
- **Faster Authentication**: Direct STS calls vs. OIDC token exchange
- **Reduced Latency**: Fewer network hops for authentication
- **Better Caching**: AWS SDK handles token caching automatically

## Best Practices

### When to Use Pod Identity vs. IRSA

**Use Pod Identity for:**
- ✅ Application workloads (JupyterHub, Ray, Argo)
- ✅ Custom applications with AWS SDK integration
- ✅ Workloads requiring fine-grained permissions
- ✅ New deployments on EKS 1.24+

**Keep IRSA for:**
- ✅ System components (VPC CNI, EBS CSI)
- ✅ Add-ons managed by AWS (Karpenter, ALB Controller)
- ✅ Third-party tools that expect IRSA annotations
- ✅ Multi-cluster scenarios with shared OIDC providers

### Security Recommendations
1. **Principle of Least Privilege**: Grant only necessary permissions
2. **Regular Audits**: Review Pod Identity associations periodically
3. **Monitoring**: Set up CloudTrail alerts for Pod Identity usage
4. **Testing**: Validate permissions in non-production environments first

## Conclusion

The migration to EKS Pod Identity for application workloads provides:
- **Simplified authentication architecture**
- **Enhanced security posture**
- **Better operational experience**
- **Future-proof authentication method**

This hybrid approach (Pod Identity for apps, IRSA for system components) provides the best of both worlds while maintaining compatibility with existing AWS add-ons and system components.