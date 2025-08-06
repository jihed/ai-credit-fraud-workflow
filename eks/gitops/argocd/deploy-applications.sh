#!/bin/bash

# Deploy ArgoCD Applications for EMR to EKS Migration
# This script deploys all ArgoCD applications for the GitOps pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Deploying ArgoCD Applications for EMR to EKS Migration${NC}"

# Configuration
ARGOCD_NAMESPACE="argocd"
ENVIRONMENT=${ENVIRONMENT:-"production"}
GIT_REPO_URL=${GIT_REPO_URL:-"https://github.com/your-org/emr-to-eks-migration.git"}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}kubectl is required but not installed${NC}"
    exit 1
fi

# Verify ArgoCD is installed
echo -e "${YELLOW}Verifying ArgoCD installation...${NC}"
if ! kubectl get namespace ${ARGOCD_NAMESPACE} >/dev/null 2>&1; then
    echo -e "${RED}ArgoCD namespace not found. Please install ArgoCD first using install-argocd.sh${NC}"
    exit 1
fi

if ! kubectl get deployment argocd-server -n ${ARGOCD_NAMESPACE} >/dev/null 2>&1; then
    echo -e "${RED}ArgoCD server not found. Please install ArgoCD first using install-argocd.sh${NC}"
    exit 1
fi

# Update Git repository URL in application manifests
echo -e "${YELLOW}Updating Git repository URL in application manifests...${NC}"
find applications/ -name "*.yaml" -type f -exec sed -i.bak "s|https://github.com/your-org/emr-to-eks-migration.git|${GIT_REPO_URL}|g" {} \;
find . -name "*.bak" -delete

# Deploy the App of Apps
echo -e "${YELLOW}Deploying App of Apps...${NC}"
sed "s|https://github.com/your-org/emr-to-eks-migration.git|${GIT_REPO_URL}|g" app-of-apps.yaml | kubectl apply -f -

# Wait for App of Apps to be synced
echo -e "${YELLOW}Waiting for App of Apps to be synced...${NC}"
kubectl wait --for=condition=Synced application/emr-to-eks-migration -n ${ARGOCD_NAMESPACE} --timeout=300s || true

# Deploy individual applications
echo -e "${YELLOW}Deploying individual applications...${NC}"

# Deploy monitoring stack
echo -e "${YELLOW}Deploying monitoring stack application...${NC}"
kubectl apply -f applications/monitoring-stack-app.yaml

# Deploy fraud inference service
echo -e "${YELLOW}Deploying fraud inference application...${NC}"
kubectl apply -f applications/fraud-inference-app.yaml

# Wait for applications to be created
echo -e "${YELLOW}Waiting for applications to be created...${NC}"
sleep 30

# Check application status
echo -e "${YELLOW}Checking application status...${NC}"
kubectl get applications -n ${ARGOCD_NAMESPACE}

# Sync applications if needed
echo -e "${YELLOW}Syncing applications...${NC}"
if command_exists argocd; then
    # Get ArgoCD server URL and login
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$ARGOCD_SERVER" ]; then
        ARGOCD_SERVER=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
    
    if [ -n "$ARGOCD_SERVER" ]; then
        ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        
        echo -e "${YELLOW}Logging into ArgoCD...${NC}"
        argocd login $ARGOCD_SERVER --username admin --password $ARGOCD_PASSWORD --insecure
        
        echo -e "${YELLOW}Syncing applications...${NC}"
        argocd app sync emr-to-eks-migration --timeout 600
        argocd app sync monitoring-stack --timeout 600
        argocd app sync fraud-inference --timeout 600
    else
        echo -e "${YELLOW}ArgoCD server URL not available, skipping CLI sync${NC}"
    fi
else
    echo -e "${YELLOW}ArgoCD CLI not available, applications will sync automatically${NC}"
fi

# Create validation script
echo -e "${YELLOW}Creating application validation script...${NC}"
cat <<'EOF' > validate-applications.sh
#!/bin/bash

echo "=== ArgoCD Applications Validation ==="

# Check ArgoCD applications
echo "Checking ArgoCD applications..."
kubectl get applications -n argocd

echo ""
echo "=== Application Details ==="

# Check each application status
for app in emr-to-eks-migration monitoring-stack fraud-inference; do
    echo "Application: $app"
    kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null && echo " - Sync Status"
    kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null && echo " - Health Status"
    echo ""
done

echo "=== Deployed Resources ==="

# Check monitoring stack resources
echo "Monitoring Stack Resources:"
kubectl get pods -n kube-prometheus-stack | head -10

echo ""
echo "Fraud Inference Resources:"
kubectl get pods -n fraud-detection

echo ""
echo "=== ArgoCD Access Information ==="
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "$ARGOCD_SERVER" ]; then
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

if [ -n "$ARGOCD_SERVER" ]; then
    echo "ArgoCD Server URL: http://$ARGOCD_SERVER"
else
    echo "ArgoCD Server URL: kubectl port-forward svc/argocd-server -n argocd 8080:443"
fi

echo "Username: admin"
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
EOF

chmod +x validate-applications.sh

echo -e "${GREEN}ArgoCD applications deployment completed!${NC}"
echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Run ${YELLOW}./validate-applications.sh${NC} to check application status"
echo -e "2. Access ArgoCD UI to monitor deployments"
echo -e "3. Check individual application health and sync status"
echo -e "4. Configure automated sync policies as needed"

echo -e "${BLUE}=== Application URLs ===${NC}"
echo -e "ArgoCD UI: Access via LoadBalancer or port-forward"
echo -e "Grafana: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80"
echo -e "Fraud Inference: Check ingress configuration for external access"