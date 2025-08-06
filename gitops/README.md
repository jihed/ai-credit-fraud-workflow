# GitOps Deployment with ArgoCD

This directory contains ArgoCD applications for managing the fraud detection demo applications using GitOps principles.

## Why GitOps?

GitOps provides several advantages over direct Helm deployments:

- **Declarative**: All application state is declared in Git
- **Versioned**: Changes are tracked and can be rolled back
- **Automated**: Applications are automatically synced from Git
- **Auditable**: All changes have a clear audit trail
- **Self-healing**: ArgoCD ensures actual state matches desired state

## Prerequisites

1. EKS cluster deployed via Terraform
2. kubectl configured to access the cluster
3. ArgoCD installed (see installation steps below)

## Quick Start

1. **Install ArgoCD**:
   ```bash
   ./scripts/install-argocd.sh
   ```

2. **Deploy applications**:
   ```bash
   kubectl apply -f applications/
   ```

3. **Access ArgoCD UI**:
   ```bash
   # Get admin password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

   # Port forward to access UI
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   
   # Access at https://localhost:8080
   # Username: admin
   # Password: (from above command)
   ```

## Application Structure

The GitOps setup includes:

- **ArgoCD Applications**: Declarative application definitions
- **Helm Charts**: Referenced from public repositories
- **Values Overlays**: Environment-specific configurations
- **Sync Policies**: Automated sync and self-healing configuration

## Applications

### JupyterHub Application
- **Chart**: `jupyterhub/jupyterhub`
- **Namespace**: `jupyterhub`
- **Sync Policy**: Automated with self-healing
- **Values**: Fraud detection specific profiles

### Ray Cluster Application
- **Chart**: `kuberay/ray-cluster`
- **Namespace**: `ray-system`
- **Sync Policy**: Automated with self-healing
- **Values**: ML workload optimized configuration

## Managing Applications

### Sync Applications
```bash
# Sync all applications
argocd app sync --all

# Sync specific application
argocd app sync jupyterhub
argocd app sync ray-cluster
```

### Check Application Status
```bash
# List all applications
argocd app list

# Get application details
argocd app get jupyterhub
argocd app get ray-cluster
```

### Rollback Applications
```bash
# Rollback to previous version
argocd app rollback jupyterhub

# Rollback to specific revision
argocd app rollback ray-cluster --revision 5
```

## Configuration Management

### Environment-Specific Values

Values are managed through:
1. **Base values**: Common configuration in `values/`
2. **Environment overlays**: Environment-specific overrides
3. **Secret management**: Sensitive data via Kubernetes secrets

### Updating Applications

1. **Update values files** in this repository
2. **Commit changes** to Git
3. **ArgoCD automatically syncs** the changes
4. **Monitor deployment** via ArgoCD UI

## Security

- **RBAC**: ArgoCD uses Kubernetes RBAC for access control
- **Git Authentication**: Private repositories require Git credentials
- **Secret Management**: Sensitive values stored as Kubernetes secrets
- **Network Policies**: Applications are isolated via network policies

## Monitoring

ArgoCD provides:
- **Application Health**: Real-time health status
- **Sync Status**: Git sync state and drift detection
- **Resource View**: Kubernetes resource visualization
- **Event History**: Deployment and sync event logs

## Troubleshooting

### Application Not Syncing
```bash
# Check application status
argocd app get <app-name>

# Force refresh
argocd app refresh <app-name>

# Manual sync
argocd app sync <app-name>
```

### Resource Issues
```bash
# Check resource status in ArgoCD
argocd app resources <app-name>

# Check Kubernetes events
kubectl get events -n <namespace>
```

### Configuration Issues
```bash
# Validate Helm values
helm template <chart> -f values/<app>-values.yaml

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```