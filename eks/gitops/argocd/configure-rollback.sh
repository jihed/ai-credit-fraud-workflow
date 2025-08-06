#!/bin/bash

# Configure Automated Rollback for ArgoCD Applications
# This script sets up automated rollback policies and monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Configuring Automated Rollback for ArgoCD Applications${NC}"

# Configuration
ARGOCD_NAMESPACE="argocd"
SLACK_TOKEN=${SLACK_TOKEN:-""}
EMAIL_USERNAME=${EMAIL_USERNAME:-""}
EMAIL_PASSWORD=${EMAIL_PASSWORD:-""}

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
    echo -e "${RED}ArgoCD namespace not found. Please install ArgoCD first${NC}"
    exit 1
fi

# Apply rollback policies
echo -e "${YELLOW}Applying rollback policies...${NC}"
kubectl apply -f rollback-policies.yaml

# Configure ArgoCD for automated rollback
echo -e "${YELLOW}Configuring ArgoCD for automated rollback...${NC}"

# Update ArgoCD ConfigMap for rollback settings
kubectl patch configmap argocd-cm -n ${ARGOCD_NAMESPACE} --type merge -p '{
  "data": {
    "application.instanceLabelKey": "argocd.argoproj.io/instance",
    "server.rbac.log.enforce.enable": "true",
    "timeout.hard.reconciliation": "0",
    "timeout.reconciliation": "180s",
    "application.rollback.enabled": "true",
    "application.rollback.maxHistory": "10"
  }
}'

# Install ArgoCD Rollouts (for advanced deployment strategies)
echo -e "${YELLOW}Installing ArgoCD Rollouts...${NC}"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Wait for Rollouts controller to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argo-rollouts -n argo-rollouts

# Create rollback monitoring script
echo -e "${YELLOW}Creating rollback monitoring script...${NC}"
cat <<'EOF' > monitor-rollbacks.sh
#!/bin/bash

# Monitor ArgoCD Applications for Rollback Conditions
# This script continuously monitors applications and triggers rollbacks when needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ARGOCD_NAMESPACE="argocd"
CHECK_INTERVAL=${CHECK_INTERVAL:-60}  # Check every 60 seconds
LOG_FILE="/tmp/rollback-monitor.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to check application health
check_application_health() {
    local app_name=$1
    local health_status=$(kubectl get application $app_name -n $ARGOCD_NAMESPACE -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    local sync_status=$(kubectl get application $app_name -n $ARGOCD_NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    
    echo "$health_status,$sync_status"
}

# Function to get pod readiness ratio
get_pod_readiness_ratio() {
    local namespace=$1
    local label_selector=$2
    
    local total_pods=$(kubectl get pods -n $namespace -l $label_selector --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n $namespace -l $label_selector --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ $total_pods -eq 0 ]; then
        echo "0"
    else
        echo "scale=2; $ready_pods / $total_pods" | bc -l
    fi
}

# Function to trigger rollback
trigger_rollback() {
    local app_name=$1
    local reason=$2
    
    log_message "🔄 Triggering rollback for $app_name - Reason: $reason"
    
    # Get previous successful revision
    local previous_revision=$(kubectl get application $app_name -n $ARGOCD_NAMESPACE -o jsonpath='{.status.history[1].revision}' 2>/dev/null || echo "")
    
    if [ -n "$previous_revision" ]; then
        # Rollback to previous revision
        kubectl patch application $app_name -n $ARGOCD_NAMESPACE --type merge -p "{
          \"spec\": {
            \"source\": {
              \"targetRevision\": \"$previous_revision\"
            }
          }
        }"
        
        # Sync the application
        kubectl patch application $app_name -n $ARGOCD_NAMESPACE --type merge -p '{
          "operation": {
            "sync": {
              "prune": true,
              "dryRun": false
            }
          }
        }'
        
        log_message "✅ Rollback initiated for $app_name to revision $previous_revision"
    else
        log_message "❌ No previous revision found for $app_name, manual intervention required"
    fi
}

# Function to check fraud-inference specific conditions
check_fraud_inference() {
    local app_name="fraud-inference"
    local namespace="fraud-detection"
    
    # Check application health
    local health_sync=$(check_application_health $app_name)
    local health_status=$(echo $health_sync | cut -d',' -f1)
    local sync_status=$(echo $health_sync | cut -d',' -f2)
    
    # Check pod readiness
    local readiness_ratio=$(get_pod_readiness_ratio $namespace "app.kubernetes.io/name=fraud-inference")
    
    # Rollback conditions
    if [ "$health_status" = "Degraded" ] || [ "$sync_status" = "OutOfSync" ]; then
        trigger_rollback $app_name "Health: $health_status, Sync: $sync_status"
        return
    fi
    
    # Check if less than 50% of pods are ready
    if (( $(echo "$readiness_ratio < 0.5" | bc -l) )); then
        trigger_rollback $app_name "Pod readiness ratio: $readiness_ratio"
        return
    fi
    
    log_message "✅ $app_name is healthy - Health: $health_status, Sync: $sync_status, Readiness: $readiness_ratio"
}

# Function to check monitoring-stack specific conditions
check_monitoring_stack() {
    local app_name="monitoring-stack"
    local namespace="kube-prometheus-stack"
    
    # Check application health
    local health_sync=$(check_application_health $app_name)
    local health_status=$(echo $health_sync | cut -d',' -f1)
    local sync_status=$(echo $health_sync | cut -d',' -f2)
    
    # Check critical components
    local prometheus_ready=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local grafana_ready=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local alertmanager_ready=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    # Rollback conditions
    if [ "$health_status" = "Degraded" ] || [ "$sync_status" = "OutOfSync" ]; then
        trigger_rollback $app_name "Health: $health_status, Sync: $sync_status"
        return
    fi
    
    # Check if critical components are down
    if [ $prometheus_ready -eq 0 ] || [ $grafana_ready -eq 0 ] || [ $alertmanager_ready -eq 0 ]; then
        trigger_rollback $app_name "Critical components down - Prometheus: $prometheus_ready, Grafana: $grafana_ready, Alertmanager: $alertmanager_ready"
        return
    fi
    
    log_message "✅ $app_name is healthy - Health: $health_status, Sync: $sync_status, Components ready"
}

# Main monitoring loop
main() {
    log_message "🚀 Starting ArgoCD rollback monitoring"
    
    while true; do
        log_message "🔍 Checking application health..."
        
        # Check each application
        check_fraud_inference
        check_monitoring_stack
        
        log_message "⏰ Waiting $CHECK_INTERVAL seconds before next check..."
        sleep $CHECK_INTERVAL
    done
}

# Handle script termination
trap 'log_message "🛑 Rollback monitoring stopped"; exit 0' SIGTERM SIGINT

# Start monitoring
main
EOF

chmod +x monitor-rollbacks.sh

# Create systemd service for rollback monitoring (optional)
echo -e "${YELLOW}Creating systemd service for rollback monitoring...${NC}"
cat <<EOF > /tmp/argocd-rollback-monitor.service
[Unit]
Description=ArgoCD Rollback Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/monitor-rollbacks.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}To install the systemd service, run:${NC}"
echo -e "${BLUE}sudo cp /tmp/argocd-rollback-monitor.service /etc/systemd/system/${NC}"
echo -e "${BLUE}sudo systemctl daemon-reload${NC}"
echo -e "${BLUE}sudo systemctl enable argocd-rollback-monitor${NC}"
echo -e "${BLUE}sudo systemctl start argocd-rollback-monitor${NC}"

# Create manual rollback script
echo -e "${YELLOW}Creating manual rollback script...${NC}"
cat <<'EOF' > manual-rollback.sh
#!/bin/bash

# Manual Rollback Script for ArgoCD Applications
# Usage: ./manual-rollback.sh <application-name> [revision]

set -e

APP_NAME=$1
TARGET_REVISION=$2
ARGOCD_NAMESPACE="argocd"

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <application-name> [revision]"
    echo "Available applications:"
    kubectl get applications -n $ARGOCD_NAMESPACE -o name | sed 's/application.argoproj.io\///'
    exit 1
fi

# Get current and previous revisions
CURRENT_REVISION=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.sync.revision}')
PREVIOUS_REVISION=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.history[1].revision}')

echo "Current revision: $CURRENT_REVISION"
echo "Previous revision: $PREVIOUS_REVISION"

# Use provided revision or default to previous
if [ -z "$TARGET_REVISION" ]; then
    TARGET_REVISION=$PREVIOUS_REVISION
fi

if [ -z "$TARGET_REVISION" ]; then
    echo "No target revision specified and no previous revision found"
    exit 1
fi

echo "Rolling back $APP_NAME to revision: $TARGET_REVISION"

# Confirm rollback
read -p "Are you sure you want to rollback? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 0
fi

# Perform rollback
kubectl patch application $APP_NAME -n $ARGOCD_NAMESPACE --type merge -p "{
  \"spec\": {
    \"source\": {
      \"targetRevision\": \"$TARGET_REVISION\"
    }
  }
}"

# Sync the application
kubectl patch application $APP_NAME -n $ARGOCD_NAMESPACE --type merge -p '{
  "operation": {
    "sync": {
      "prune": true,
      "dryRun": false
    }
  }
}'

echo "Rollback initiated. Check ArgoCD UI for progress."
EOF

chmod +x manual-rollback.sh

# Create validation script for rollback configuration
echo -e "${YELLOW}Creating rollback validation script...${NC}"
cat <<'EOF' > validate-rollback-config.sh
#!/bin/bash

echo "=== ArgoCD Rollback Configuration Validation ==="

ARGOCD_NAMESPACE="argocd"

# Check ArgoCD configuration
echo "Checking ArgoCD configuration..."
kubectl get configmap argocd-cm -n $ARGOCD_NAMESPACE -o jsonpath='{.data.application\.rollback\.enabled}' && echo " - Rollback enabled"

# Check rollback policies
echo "Checking rollback policies..."
kubectl get configmap rollback-policies -n $ARGOCD_NAMESPACE >/dev/null 2>&1 && echo "✅ Rollback policies configured" || echo "❌ Rollback policies not found"

# Check ArgoCD Rollouts
echo "Checking ArgoCD Rollouts..."
kubectl get deployment argo-rollouts -n argo-rollouts >/dev/null 2>&1 && echo "✅ ArgoCD Rollouts installed" || echo "❌ ArgoCD Rollouts not found"

# Check notification configuration
echo "Checking notification configuration..."
kubectl get configmap argocd-notifications-cm -n $ARGOCD_NAMESPACE >/dev/null 2>&1 && echo "✅ Notifications configured" || echo "❌ Notifications not configured"

# Check applications
echo "Checking applications..."
kubectl get applications -n $ARGOCD_NAMESPACE

echo ""
echo "=== Rollback Scripts ==="
ls -la monitor-rollbacks.sh manual-rollback.sh 2>/dev/null || echo "Scripts not found in current directory"

echo ""
echo "=== Manual Rollback Usage ==="
echo "./manual-rollback.sh <application-name> [revision]"
echo ""
echo "=== Monitoring ==="
echo "To start monitoring: ./monitor-rollbacks.sh"
echo "To check logs: tail -f /tmp/rollback-monitor.log"
EOF

chmod +x validate-rollback-config.sh

echo -e "${GREEN}Automated rollback configuration completed!${NC}"
echo -e "${BLUE}=== Configuration Summary ===${NC}"
echo -e "✅ Rollback policies applied"
echo -e "✅ ArgoCD configured for rollback"
echo -e "✅ ArgoCD Rollouts installed"
echo -e "✅ Monitoring script created"
echo -e "✅ Manual rollback script created"

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Run ${YELLOW}./validate-rollback-config.sh${NC} to verify configuration"
echo -e "2. Start monitoring: ${YELLOW}./monitor-rollbacks.sh${NC}"
echo -e "3. Configure notification tokens in rollback-policies.yaml"
echo -e "4. Test rollback: ${YELLOW}./manual-rollback.sh <app-name>${NC}"

echo -e "${BLUE}=== Monitoring ===${NC}"
echo -e "Monitor logs: ${YELLOW}tail -f /tmp/rollback-monitor.log${NC}"
echo -e "Check application status: ${YELLOW}kubectl get applications -n argocd${NC}"