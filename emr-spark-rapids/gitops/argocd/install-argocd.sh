#!/bin/bash

# Install ArgoCD for GitOps deployment pipeline
# This script installs ArgoCD on the EKS cluster for EMR to EKS migration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Installing ArgoCD for EMR to EKS Migration GitOps Pipeline${NC}"

# Configuration
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="v2.12.7"
CLUSTER_NAME=${CLUSTER_NAME:-"data-on-eks"}
AWS_REGION=${AWS_REGION:-"us-west-2"}

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

if ! command_exists helm; then
    echo -e "${RED}helm is required but not installed${NC}"
    exit 1
fi

# Verify cluster connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Create ArgoCD namespace
echo -e "${YELLOW}Creating ArgoCD namespace...${NC}"
kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using official manifests
echo -e "${YELLOW}Installing ArgoCD ${ARGOCD_VERSION}...${NC}"
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for ArgoCD to be ready
echo -e "${YELLOW}Waiting for ArgoCD components to be ready...${NC}"
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n ${ARGOCD_NAMESPACE}
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n ${ARGOCD_NAMESPACE}
kubectl wait --for=condition=available --timeout=600s deployment/argocd-dex-server -n ${ARGOCD_NAMESPACE}

# Patch ArgoCD server service to use LoadBalancer (for easy access)
echo -e "${YELLOW}Configuring ArgoCD server service...${NC}"
kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p '{"spec": {"type": "LoadBalancer"}}'

# Configure ArgoCD for insecure mode (for LoadBalancer access)
echo -e "${YELLOW}Configuring ArgoCD server for LoadBalancer access...${NC}"
kubectl patch deployment argocd-server -n ${ARGOCD_NAMESPACE} --type='merge' -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}'

# Wait for ArgoCD server to restart
kubectl rollout status deployment/argocd-server -n ${ARGOCD_NAMESPACE} --timeout=300s

# Get ArgoCD admin password
echo -e "${YELLOW}Retrieving ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Install ArgoCD CLI (optional)
echo -e "${YELLOW}Installing ArgoCD CLI...${NC}"
if command_exists brew; then
    brew install argocd || echo "ArgoCD CLI installation failed, continuing..."
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
else
    echo -e "${YELLOW}Please install ArgoCD CLI manually from: https://argo-cd.readthedocs.io/en/stable/cli_installation/${NC}"
fi

# Create ArgoCD configuration for the EMR to EKS project
echo -e "${YELLOW}Creating ArgoCD project configuration...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: emr-to-eks-migration
  namespace: ${ARGOCD_NAMESPACE}
spec:
  description: EMR to EKS Migration Project
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  roles:
  - name: admin
    description: Admin role for EMR to EKS migration
    policies:
    - p, proj:emr-to-eks-migration:admin, applications, *, emr-to-eks-migration/*, allow
    - p, proj:emr-to-eks-migration:admin, repositories, *, *, allow
    groups:
    - argocd-admins
EOF

# Create RBAC configuration
echo -e "${YELLOW}Configuring RBAC for ArgoCD...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    g, argocd-admins, role:admin
EOF

# Create ArgoCD ingress (optional, for production use)
echo -e "${YELLOW}Creating ArgoCD ingress configuration...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
  - host: argocd.${CLUSTER_NAME}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

# Wait for LoadBalancer to be ready
echo -e "${YELLOW}Waiting for ArgoCD LoadBalancer to be ready...${NC}"
sleep 30

# Get ArgoCD server URL
ARGOCD_SERVER=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "$ARGOCD_SERVER" ]; then
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

# Create validation script
echo -e "${YELLOW}Creating ArgoCD validation script...${NC}"
cat <<'EOF' > validate-argocd.sh
#!/bin/bash

echo "=== ArgoCD Validation ==="

# Check ArgoCD components
echo "Checking ArgoCD components..."
kubectl get pods -n argocd

# Check ArgoCD service
echo "Checking ArgoCD service..."
kubectl get svc argocd-server -n argocd

# Check ArgoCD applications
echo "Checking ArgoCD applications..."
kubectl get applications -n argocd

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

chmod +x validate-argocd.sh

echo -e "${GREEN}ArgoCD installation completed successfully!${NC}"
echo -e "${BLUE}=== ArgoCD Access Information ===${NC}"

if [ -n "$ARGOCD_SERVER" ]; then
    echo -e "${YELLOW}ArgoCD Server URL: http://$ARGOCD_SERVER${NC}"
else
    echo -e "${YELLOW}ArgoCD Server URL: kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
fi

echo -e "${YELLOW}Username: admin${NC}"
echo -e "${YELLOW}Password: $ARGOCD_PASSWORD${NC}"
echo -e "${YELLOW}Run ./validate-argocd.sh to verify the installation${NC}"

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Access ArgoCD UI using the URL and credentials above"
echo -e "2. Create ArgoCD applications for your components"
echo -e "3. Configure Git repositories for GitOps deployment"
echo -e "4. Set up automated sync policies"