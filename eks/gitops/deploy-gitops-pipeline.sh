#!/bin/bash

# Deploy Complete GitOps Pipeline with ArgoCD for EMR to EKS Migration
# This script deploys the entire GitOps infrastructure and applications

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Complete GitOps Pipeline for EMR to EKS Migration${NC}"

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"data-on-eks"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
GIT_REPO_URL=${GIT_REPO_URL:-"https://github.com/your-org/emr-to-eks-migration.git"}
SKIP_ARGOCD_INSTALL=${SKIP_ARGOCD_INSTALL:-"false"}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for condition
wait_for_condition() {
    local condition="$1"
    local timeout="${2:-300}"
    local interval="${3:-10}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition"; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -e "${YELLOW}Waiting for condition... (${elapsed}s/${timeout}s)${NC}"
    done
    
    echo -e "${RED}Timeout waiting for condition: $condition${NC}"
    return 1
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}kubectl is required but not installed${NC}"
    exit 1
fi

if ! command_exists helm; then
    echo -e "${RED}helm is required but not installed${NC}"
    exit 1
fi

# Verify cluster connection
echo -e "${YELLOW}🔗 Verifying cluster connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to cluster: $(kubectl config current-context)${NC}"

# Step 1: Install ArgoCD (if not skipped)
if [ "$SKIP_ARGOCD_INSTALL" != "true" ]; then
    echo -e "${BLUE}📦 Step 1: Installing ArgoCD...${NC}"
    cd argocd
    chmod +x install-argocd.sh
    ./install-argocd.sh
    cd ..
    
    # Wait for ArgoCD to be ready
    echo -e "${YELLOW}⏳ Waiting for ArgoCD to be ready...${NC}"
    wait_for_condition "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | grep -q Running" 600
else
    echo -e "${YELLOW}⏭️  Skipping ArgoCD installation${NC}"
fi

# Step 2: Build and push Docker images (if needed)
echo -e "${BLUE}🐳 Step 2: Preparing Docker images...${NC}"
if [ -f "../inference-service/Dockerfile" ]; then
    echo -e "${YELLOW}Building fraud-inference Docker image...${NC}"
    cd ../inference-service
    
    # Build the image
    docker build -t fraud-inference:latest .
    
    # Tag for registry (update with your registry)
    # docker tag fraud-inference:latest your-registry/fraud-inference:latest
    # docker push your-registry/fraud-inference:latest
    
    cd ../emr-spark-rapids/gitops
    echo -e "${GREEN}✅ Docker image prepared${NC}"
else
    echo -e "${YELLOW}⚠️  Inference service Dockerfile not found, skipping image build${NC}"
fi

# Step 3: Update Helm chart dependencies
echo -e "${BLUE}📊 Step 3: Updating Helm chart dependencies...${NC}"
cd helm-charts/monitoring-stack
helm dependency update
cd ../..

# Step 4: Deploy ArgoCD applications
echo -e "${BLUE}🎯 Step 4: Deploying ArgoCD applications...${NC}"
cd argocd
chmod +x deploy-applications.sh
export GIT_REPO_URL
./deploy-applications.sh
cd ..

# Step 5: Configure automated rollback
echo -e "${BLUE}🔄 Step 5: Configuring automated rollback...${NC}"
cd argocd
chmod +x configure-rollback.sh
./configure-rollback.sh
cd ..

# Step 6: Wait for applications to be synced
echo -e "${YELLOW}⏳ Waiting for applications to be synced...${NC}"
wait_for_condition "kubectl get application monitoring-stack -n argocd -o jsonpath='{.status.sync.status}' | grep -q Synced" 600 30
wait_for_condition "kubectl get application fraud-inference -n argocd -o jsonpath='{.status.sync.status}' | grep -q Synced" 600 30

# Step 7: Verify deployments
echo -e "${BLUE}✅ Step 7: Verifying deployments...${NC}"

# Check ArgoCD applications
echo -e "${YELLOW}Checking ArgoCD applications...${NC}"
kubectl get applications -n argocd

# Check monitoring stack
echo -e "${YELLOW}Checking monitoring stack...${NC}"
kubectl get pods -n kube-prometheus-stack | head -10

# Check fraud inference service
echo -e "${YELLOW}Checking fraud inference service...${NC}"
kubectl get pods -n fraud-detection

# Step 8: Create comprehensive validation script
echo -e "${BLUE}📝 Step 8: Creating validation script...${NC}"
cat <<'EOF' > validate-gitops-deployment.sh
#!/bin/bash

# Comprehensive GitOps Deployment Validation
# This script validates the entire GitOps pipeline deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== GitOps Pipeline Validation ===${NC}"

# Function to check resource status
check_resource_status() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local expected_status=$4
    
    local actual_status=$(kubectl get $resource_type $resource_name -n $namespace -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$actual_status" = "$expected_status" ] || [ "$actual_status" = "Running" ] || [ "$actual_status" = "Active" ]; then
        echo -e "${GREEN}✅${NC} $resource_type/$resource_name in $namespace: $actual_status"
        return 0
    else
        echo -e "${RED}❌${NC} $resource_type/$resource_name in $namespace: $actual_status (expected: $expected_status)"
        return 1
    fi
}

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Check ArgoCD installation
echo -e "${YELLOW}🔍 Checking ArgoCD installation...${NC}"
((TOTAL_CHECKS++))
if kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} ArgoCD namespace exists"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}❌${NC} ArgoCD namespace not found"
fi

((TOTAL_CHECKS++))
if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} ArgoCD server deployment exists"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}❌${NC} ArgoCD server deployment not found"
fi

# Check ArgoCD applications
echo -e "${YELLOW}🎯 Checking ArgoCD applications...${NC}"
APPLICATIONS=("emr-to-eks-migration" "monitoring-stack" "fraud-inference")

for app in "${APPLICATIONS[@]}"; do
    ((TOTAL_CHECKS++))
    if kubectl get application $app -n argocd >/dev/null 2>&1; then
        SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            echo -e "${GREEN}✅${NC} Application $app: Synced & Healthy"
            ((PASSED_CHECKS++))
        else
            echo -e "${YELLOW}⚠️${NC} Application $app: Sync=$SYNC_STATUS, Health=$HEALTH_STATUS"
        fi
    else
        echo -e "${RED}❌${NC} Application $app not found"
    fi
done

# Check monitoring stack components
echo -e "${YELLOW}📊 Checking monitoring stack components...${NC}"
MONITORING_COMPONENTS=("prometheus" "grafana" "alertmanager")

for component in "${MONITORING_COMPONENTS[@]}"; do
    ((TOTAL_CHECKS++))
    PODS=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=$component --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=$component --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$PODS" -gt 0 ] && [ "$RUNNING_PODS" -eq "$PODS" ]; then
        echo -e "${GREEN}✅${NC} $component: $RUNNING_PODS/$PODS pods running"
        ((PASSED_CHECKS++))
    else
        echo -e "${RED}❌${NC} $component: $RUNNING_PODS/$PODS pods running"
    fi
done

# Check fraud inference service
echo -e "${YELLOW}🎯 Checking fraud inference service...${NC}"
((TOTAL_CHECKS++))
INFERENCE_PODS=$(kubectl get pods -n fraud-detection -l app.kubernetes.io/name=fraud-inference --no-headers 2>/dev/null | wc -l)
INFERENCE_RUNNING=$(kubectl get pods -n fraud-detection -l app.kubernetes.io/name=fraud-inference --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$INFERENCE_PODS" -gt 0 ] && [ "$INFERENCE_RUNNING" -eq "$INFERENCE_PODS" ]; then
    echo -e "${GREEN}✅${NC} Fraud inference service: $INFERENCE_RUNNING/$INFERENCE_PODS pods running"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}❌${NC} Fraud inference service: $INFERENCE_RUNNING/$INFERENCE_PODS pods running"
fi

# Check Helm releases
echo -e "${YELLOW}📦 Checking Helm releases...${NC}"
((TOTAL_CHECKS++))
if helm list -n kube-prometheus-stack | grep -q "deployed"; then
    echo -e "${GREEN}✅${NC} Monitoring stack Helm release deployed"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}❌${NC} Monitoring stack Helm release not found"
fi

# Check rollback configuration
echo -e "${YELLOW}🔄 Checking rollback configuration...${NC}"
((TOTAL_CHECKS++))
if kubectl get configmap rollback-policies -n argocd >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Rollback policies configured"
    ((PASSED_CHECKS++))
else
    echo -e "${RED}❌${NC} Rollback policies not found"
fi

# Summary
echo -e "${BLUE}=== Validation Summary ===${NC}"
echo -e "Passed checks: ${GREEN}$PASSED_CHECKS${NC}/$TOTAL_CHECKS"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}🎉 All validations passed! GitOps pipeline is fully operational.${NC}"
    exit 0
elif [ $PASSED_CHECKS -gt $((TOTAL_CHECKS * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠️  Most validations passed, but some issues detected.${NC}"
    exit 1
else
    echo -e "${RED}❌ Significant issues detected with GitOps pipeline.${NC}"
    exit 2
fi
EOF

chmod +x validate-gitops-deployment.sh

# Step 9: Create operational documentation
echo -e "${BLUE}📚 Step 9: Creating operational documentation...${NC}"
cat <<EOF > GITOPS_OPERATIONS.md
# GitOps Operations Guide

## Overview
This document provides operational guidance for the ArgoCD-based GitOps pipeline for EMR to EKS migration.

## Architecture
- **ArgoCD**: GitOps controller managing application deployments
- **Helm Charts**: Package management for applications
- **Environment-specific configurations**: Dev, Staging, Production
- **Automated rollback**: Failure detection and automatic recovery

## Applications Managed
1. **monitoring-stack**: Prometheus, Grafana, Kubecost, custom exporters
2. **fraud-inference**: ML inference service with auto-scaling
3. **emr-to-eks-migration**: App of Apps managing the entire platform

## Access Information

### ArgoCD UI
\`\`\`bash
# Get ArgoCD server URL
kubectl get svc argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
\`\`\`

### Grafana Dashboard
\`\`\`bash
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80
\`\`\`

## Common Operations

### Deploy New Version
1. Update image tag in Git repository
2. ArgoCD will automatically sync (if auto-sync enabled)
3. Monitor deployment in ArgoCD UI

### Manual Sync
\`\`\`bash
# Sync specific application
kubectl patch application fraud-inference -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'

# Or use ArgoCD CLI
argocd app sync fraud-inference
\`\`\`

### Rollback Application
\`\`\`bash
# Automatic rollback (if monitoring detects issues)
./argocd/monitor-rollbacks.sh

# Manual rollback
./argocd/manual-rollback.sh fraud-inference [revision]
\`\`\`

### Check Application Status
\`\`\`bash
# List all applications
kubectl get applications -n argocd

# Get detailed status
kubectl describe application fraud-inference -n argocd
\`\`\`

### Update Configuration
1. Modify values in \`gitops/environments/\${ENVIRONMENT}/\` directory
2. Commit changes to Git
3. ArgoCD will detect and sync changes

## Troubleshooting

### Application Stuck in Syncing
\`\`\`bash
# Check application events
kubectl describe application <app-name> -n argocd

# Force refresh
kubectl patch application <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
\`\`\`

### Sync Failures
1. Check ArgoCD server logs: \`kubectl logs -n argocd deployment/argocd-server\`
2. Verify Git repository access
3. Check Helm chart syntax: \`helm template <chart-path>\`

### Rollback Issues
1. Check rollback monitor logs: \`tail -f /tmp/rollback-monitor.log\`
2. Verify application history: \`kubectl get application <app-name> -n argocd -o jsonpath='{.status.history}'\`

## Monitoring and Alerting

### Key Metrics to Monitor
- Application sync status
- Application health status
- Deployment success rate
- Rollback frequency

### Alerts Configuration
- Sync failures
- Health degradation
- Rollback triggers
- Resource exhaustion

## Security Considerations

### RBAC
- ArgoCD project-level permissions
- Kubernetes namespace isolation
- Service account restrictions

### Secrets Management
- Use Kubernetes secrets for sensitive data
- Consider external secret management (AWS Secrets Manager, Vault)
- Rotate credentials regularly

## Backup and Recovery

### ArgoCD Configuration
\`\`\`bash
# Backup ArgoCD applications
kubectl get applications -n argocd -o yaml > argocd-applications-backup.yaml

# Backup ArgoCD configuration
kubectl get configmap argocd-cm -n argocd -o yaml > argocd-config-backup.yaml
\`\`\`

### Application State
- Git repository serves as source of truth
- Helm releases can be recreated from charts
- Persistent data requires separate backup strategy

## Performance Tuning

### ArgoCD Optimization
- Adjust sync timeout settings
- Configure resource limits
- Enable parallel processing

### Application Optimization
- Use resource requests/limits
- Configure HPA appropriately
- Monitor resource utilization

## Maintenance

### Regular Tasks
- Update ArgoCD version
- Review and update Helm charts
- Clean up old application revisions
- Monitor resource usage

### Scheduled Maintenance
- Plan maintenance windows
- Communicate changes to stakeholders
- Test rollback procedures

## Support Contacts
- Platform Engineering: #platform-engineering
- ML Engineering: #ml-engineering
- On-call: oncall@yourorg.com
EOF

# Final validation
echo -e "${BLUE}✅ Step 10: Running final validation...${NC}"
./validate-gitops-deployment.sh

echo -e "${GREEN}🎉 GitOps Pipeline Deployment Completed Successfully!${NC}"

echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo -e "✅ ArgoCD installed and configured"
echo -e "✅ Helm charts created for all components"
echo -e "✅ Applications deployed via GitOps"
echo -e "✅ Automated rollback configured"
echo -e "✅ Environment-specific configurations ready"
echo -e "✅ Monitoring and observability deployed"

echo -e "${BLUE}=== Access Information ===${NC}"
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -z "$ARGOCD_SERVER" ]; then
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
fi

if [ -n "$ARGOCD_SERVER" ]; then
    echo -e "${YELLOW}ArgoCD UI: http://$ARGOCD_SERVER${NC}"
else
    echo -e "${YELLOW}ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
fi

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Unable to retrieve")
echo -e "${YELLOW}ArgoCD Username: admin${NC}"
echo -e "${YELLOW}ArgoCD Password: $ARGOCD_PASSWORD${NC}"

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Access ArgoCD UI and verify all applications are synced"
echo -e "2. Configure Git repository webhooks for automatic sync"
echo -e "3. Set up monitoring alerts and notifications"
echo -e "4. Review and customize environment-specific configurations"
echo -e "5. Test rollback procedures"

echo -e "${BLUE}=== Documentation ===${NC}"
echo -e "📚 Operations Guide: GITOPS_OPERATIONS.md"
echo -e "🔧 Validation Script: ./validate-gitops-deployment.sh"
echo -e "🔄 Rollback Scripts: ./argocd/manual-rollback.sh, ./argocd/monitor-rollbacks.sh"