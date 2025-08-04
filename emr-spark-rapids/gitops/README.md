# GitOps Deployment Pipeline with ArgoCD

This directory contains the complete GitOps deployment pipeline implementation for the EMR to EKS migration project using ArgoCD instead of FluxCD.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Git Repository│    │     ArgoCD      │    │   Kubernetes    │
│                 │    │                 │    │                 │
│ • Helm Charts   │───▶│ • Applications  │───▶│ • Deployments   │
│ • Configurations│    │ • Sync Policies │    │ • Services      │
│ • Environments  │    │ • Rollback      │    │ • ConfigMaps    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Monitoring    │
                       │                 │
                       │ • Health Checks │
                       │ • Rollback      │
                       │ • Notifications │
                       └─────────────────┘
```

## 📁 Directory Structure

```
gitops/
├── argocd/                          # ArgoCD installation and configuration
│   ├── install-argocd.sh           # ArgoCD installation script
│   ├── deploy-applications.sh      # Deploy all applications
│   ├── configure-rollback.sh       # Configure automated rollback
│   ├── rollback-policies.yaml      # Rollback policies and notifications
│   ├── app-of-apps.yaml           # App of Apps pattern
│   └── applications/               # Individual application manifests
│       ├── fraud-inference-app.yaml
│       └── monitoring-stack-app.yaml
├── helm-charts/                    # Helm charts for applications
│   ├── fraud-inference/           # Fraud detection inference service
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── monitoring-stack/          # Comprehensive monitoring stack
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── environments/                   # Environment-specific configurations
│   ├── dev/
│   ├── staging/
│   └── production/
├── deploy-gitops-pipeline.sh      # Complete deployment script
└── README.md                      # This file
```

## 🚀 Quick Start

### Prerequisites
- EKS cluster running
- kubectl configured
- Helm 3.x installed
- Docker (for building images)

### 1. Deploy Complete GitOps Pipeline
```bash
# Set environment variables
export CLUSTER_NAME="data-on-eks"
export AWS_REGION="us-west-2"
export GIT_REPO_URL="https://github.com/your-org/emr-to-eks-migration.git"

# Deploy everything
chmod +x deploy-gitops-pipeline.sh
./deploy-gitops-pipeline.sh
```

### 2. Validate Deployment
```bash
# Run comprehensive validation
./validate-gitops-deployment.sh

# Check ArgoCD applications
kubectl get applications -n argocd
```

### 3. Access ArgoCD UI
```bash
# Get ArgoCD server URL
kubectl get svc argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 🎯 Applications Managed

### 1. Monitoring Stack
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Kubecost**: Cost monitoring and optimization
- **Custom Exporters**: EMR and Ray metrics
- **NVIDIA DCGM**: GPU monitoring
- **Alerting Rules**: Comprehensive alerting

### 2. Fraud Inference Service
- **FastAPI Service**: ML model serving
- **Auto-scaling**: HPA with CPU/memory targets
- **Load Balancing**: ALB ingress
- **Monitoring**: Prometheus metrics
- **Health Checks**: Liveness and readiness probes

### 3. App of Apps
- **Centralized Management**: Single point of control
- **Dependency Management**: Proper deployment order
- **Environment Isolation**: Separate configurations

## 🔄 Automated Rollback Features

### Rollback Triggers
- Application health degradation
- Sync failures
- Pod readiness issues
- Custom metric thresholds

### Rollback Strategies
- **Immediate**: Fast rollback for critical issues
- **Gradual**: Staged rollback with validation
- **Manual**: Human-approved rollback

### Monitoring and Notifications
- Continuous health monitoring
- Slack/email notifications
- Detailed rollback logs
- Success/failure tracking

## 🌍 Environment Management

### Development
- Single replica deployments
- Debug logging enabled
- Relaxed resource limits
- Fast sync intervals

### Staging
- Production-like configuration
- Load testing capabilities
- Integration test validation
- Automated promotion

### Production
- High availability setup
- Strict resource limits
- Security hardening
- Comprehensive monitoring

## 🛠️ Operations

### Deploy New Version
```bash
# Update image tag in Git repository
git commit -m "Update fraud-inference to v1.2.0"
git push

# ArgoCD will automatically sync (if enabled)
# Or manually sync:
kubectl patch application fraud-inference -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

### Manual Rollback
```bash
# Rollback to previous version
./argocd/manual-rollback.sh fraud-inference

# Rollback to specific revision
./argocd/manual-rollback.sh fraud-inference abc123
```

### Monitor Applications
```bash
# Start automated monitoring
./argocd/monitor-rollbacks.sh

# Check logs
tail -f /tmp/rollback-monitor.log
```

## 📊 Key Features Implemented

### ✅ ArgoCD GitOps Controller
- Complete ArgoCD installation and configuration
- Project-based RBAC and security
- LoadBalancer access with ingress
- CLI integration and automation

### ✅ Helm Charts for All Components
- **Fraud Inference**: Production-ready FastAPI service
- **Monitoring Stack**: Comprehensive observability
- **Environment Configurations**: Dev/Staging/Production
- **Dependency Management**: Automated updates

### ✅ Environment-Specific Configuration
- **Values Files**: Environment-specific overrides
- **Resource Scaling**: Appropriate sizing per environment
- **Security Settings**: Environment-appropriate policies
- **Ingress Configuration**: Domain and TLS management

### ✅ Automated Rollback on Failures
- **Health Monitoring**: Continuous application health checks
- **Failure Detection**: Multiple trigger conditions
- **Automatic Recovery**: Rollback to last known good state
- **Notification System**: Slack/email alerts

### ✅ Comprehensive Monitoring
- **Application Metrics**: Custom Prometheus exporters
- **Infrastructure Metrics**: Node, pod, and cluster metrics
- **Cost Tracking**: Kubecost integration
- **Alerting Rules**: Proactive issue detection

## 🔧 Customization

### Adding New Applications
1. Create Helm chart in `helm-charts/`
2. Add ArgoCD application in `argocd/applications/`
3. Configure environment-specific values
4. Update App of Apps manifest

### Modifying Rollback Policies
1. Edit `argocd/rollback-policies.yaml`
2. Update monitoring thresholds
3. Configure notification channels
4. Test rollback scenarios

### Environment Configuration
1. Update values in `environments/*/`
2. Commit changes to Git
3. ArgoCD will automatically sync
4. Monitor deployment progress

## 📚 Documentation

- **Operations Guide**: `GITOPS_OPERATIONS.md`
- **Validation Scripts**: `validate-*.sh`
- **Rollback Procedures**: `argocd/manual-rollback.sh`
- **Monitoring Setup**: `argocd/monitor-rollbacks.sh`

## 🆘 Troubleshooting

### Common Issues
1. **Sync Failures**: Check Git repository access and Helm chart syntax
2. **Health Issues**: Verify resource limits and dependencies
3. **Rollback Problems**: Check application history and permissions
4. **Access Issues**: Verify RBAC and network policies

### Support
- Platform Engineering: `#platform-engineering`
- ML Engineering: `#ml-engineering`
- Documentation: `GITOPS_OPERATIONS.md`

## 🎯 Requirements Fulfilled

- **4.2**: ✅ GitOps-based deployment automation with ArgoCD
- **4.3**: ✅ Environment-specific configuration management
- **4.4**: ✅ Automated rollback on deployment failures

The GitOps pipeline provides a complete, production-ready deployment solution for the EMR to EKS migration with comprehensive monitoring, automated rollback, and environment management capabilities.