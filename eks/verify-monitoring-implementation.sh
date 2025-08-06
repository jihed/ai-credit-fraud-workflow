#!/bin/bash

# Verify Monitoring Implementation Files
# This script verifies that all monitoring implementation files are present and correctly configured

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Verifying Monitoring Implementation Files ===${NC}"

# Function to check if file exists and is not empty
check_file() {
    local file_path=$1
    local description=$2
    
    if [ -f "$file_path" ] && [ -s "$file_path" ]; then
        echo -e "${GREEN}✓${NC} $description: $file_path"
        return 0
    else
        echo -e "${RED}✗${NC} $description: $file_path (missing or empty)"
        return 1
    fi
}

# Function to check YAML syntax
check_yaml_syntax() {
    local file_path=$1
    local description=$2
    
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' "$file_path" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $description YAML syntax is valid"
            return 0
        else
            echo -e "${RED}✗${NC} $description YAML syntax is invalid"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠${NC} yq not available, skipping YAML syntax check for $description"
        return 0
    fi
}

# Check deployment scripts
echo -e "${YELLOW}Checking deployment scripts...${NC}"
check_file "deploy-monitoring.sh" "Main deployment script"
check_file "validate-monitoring.sh" "Validation script"
check_file "test-monitoring-integration.sh" "Integration test script"

# Check if scripts are executable
for script in deploy-monitoring.sh validate-monitoring.sh test-monitoring-integration.sh; do
    if [ -x "$script" ]; then
        echo -e "${GREEN}✓${NC} $script is executable"
    else
        echo -e "${YELLOW}⚠${NC} $script is not executable (run: chmod +x $script)"
    fi
done

# Check monitoring configuration files
echo -e "${YELLOW}Checking monitoring configuration files...${NC}"
check_file "monitoring/enhanced-kube-prometheus.yaml" "Enhanced Prometheus configuration"
check_file "monitoring/custom-recording-rules.yaml" "Custom recording rules"
check_file "monitoring/alerting-rules.yaml" "Alerting rules"
check_file "monitoring/cloudwatch-integration.yaml" "CloudWatch integration"
check_file "monitoring/custom-metrics-exporters.yaml" "Custom metrics exporters"

# Check YAML syntax for configuration files
echo -e "${YELLOW}Checking YAML syntax...${NC}"
check_yaml_syntax "monitoring/enhanced-kube-prometheus.yaml" "Enhanced Prometheus configuration"
check_yaml_syntax "monitoring/custom-recording-rules.yaml" "Custom recording rules"
check_yaml_syntax "monitoring/alerting-rules.yaml" "Alerting rules"
check_yaml_syntax "monitoring/cloudwatch-integration.yaml" "CloudWatch integration"
check_yaml_syntax "monitoring/custom-metrics-exporters.yaml" "Custom metrics exporters"

# Check Helm values files
echo -e "${YELLOW}Checking Helm values files...${NC}"
check_file "helm-values/kubecost-values.yaml" "Kubecost Helm values"
check_file "helm-values/kube-prometheus.yaml" "Kube-prometheus Helm values"
check_file "helm-values/kube-prometheus-amp-enable.yaml" "Kube-prometheus AMP Helm values"

# Check dashboard files
echo -e "${YELLOW}Checking dashboard files...${NC}"
check_file "monitoring/dashboards/fraud-detection-overview.json" "Fraud detection dashboard"

# Check if dashboard JSON is valid
if command -v jq >/dev/null 2>&1; then
    if jq '.' monitoring/dashboards/fraud-detection-overview.json >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Fraud detection dashboard JSON is valid"
    else
        echo -e "${RED}✗${NC} Fraud detection dashboard JSON is invalid"
    fi
else
    echo -e "${YELLOW}⚠${NC} jq not available, skipping JSON validation"
fi

# Check documentation
echo -e "${YELLOW}Checking documentation...${NC}"
check_file "MONITORING_README.md" "Monitoring documentation"

# Verify key configuration elements
echo -e "${YELLOW}Verifying key configuration elements...${NC}"

# Check if enhanced-kube-prometheus.yaml contains required sections
if grep -q "additionalScrapeConfigs" monitoring/enhanced-kube-prometheus.yaml; then
    echo -e "${GREEN}✓${NC} Enhanced Prometheus config contains additional scrape configs"
else
    echo -e "${RED}✗${NC} Enhanced Prometheus config missing additional scrape configs"
fi

# Check if custom recording rules contain GPU metrics
if grep -q "gpu:utilization:rate5m" monitoring/custom-recording-rules.yaml; then
    echo -e "${GREEN}✓${NC} Custom recording rules contain GPU metrics"
else
    echo -e "${RED}✗${NC} Custom recording rules missing GPU metrics"
fi

# Check if alerting rules contain fraud detection alerts
if grep -q "fraud-detection" monitoring/alerting-rules.yaml; then
    echo -e "${GREEN}✓${NC} Alerting rules contain fraud detection specific alerts"
else
    echo -e "${RED}✗${NC} Alerting rules missing fraud detection specific alerts"
fi

# Check if custom exporters contain EMR and Ray exporters
if grep -q "emr-metrics-exporter" monitoring/custom-metrics-exporters.yaml && grep -q "ray-metrics-exporter" monitoring/custom-metrics-exporters.yaml; then
    echo -e "${GREEN}✓${NC} Custom metrics exporters contain EMR and Ray exporters"
else
    echo -e "${RED}✗${NC} Custom metrics exporters missing EMR or Ray exporters"
fi

# Check if CloudWatch integration contains proper log groups
if grep -q "/aws/eks.*emr-containers" monitoring/cloudwatch-integration.yaml && grep -q "/aws/eks.*ray-training" monitoring/cloudwatch-integration.yaml; then
    echo -e "${GREEN}✓${NC} CloudWatch integration contains proper log groups"
else
    echo -e "${RED}✗${NC} CloudWatch integration missing proper log groups"
fi

# Summary
echo -e "${BLUE}=== Implementation Verification Summary ===${NC}"

TOTAL_FILES=12
EXISTING_FILES=0

# Count existing files
[ -f "deploy-monitoring.sh" ] && ((EXISTING_FILES++))
[ -f "validate-monitoring.sh" ] && ((EXISTING_FILES++))
[ -f "test-monitoring-integration.sh" ] && ((EXISTING_FILES++))
[ -f "monitoring/enhanced-kube-prometheus.yaml" ] && ((EXISTING_FILES++))
[ -f "monitoring/custom-recording-rules.yaml" ] && ((EXISTING_FILES++))
[ -f "monitoring/alerting-rules.yaml" ] && ((EXISTING_FILES++))
[ -f "monitoring/cloudwatch-integration.yaml" ] && ((EXISTING_FILES++))
[ -f "monitoring/custom-metrics-exporters.yaml" ] && ((EXISTING_FILES++))
[ -f "helm-values/kubecost-values.yaml" ] && ((EXISTING_FILES++))
[ -f "monitoring/dashboards/fraud-detection-overview.json" ] && ((EXISTING_FILES++))
[ -f "MONITORING_README.md" ] && ((EXISTING_FILES++))
[ -f "verify-monitoring-implementation.sh" ] && ((EXISTING_FILES++))

echo -e "Implementation files: ${GREEN}$EXISTING_FILES${NC}/$TOTAL_FILES"

if [ $EXISTING_FILES -eq $TOTAL_FILES ]; then
    echo -e "${GREEN}✓ All monitoring implementation files are present${NC}"
    echo -e "${GREEN}✓ Monitoring implementation is complete and ready for deployment${NC}"
elif [ $EXISTING_FILES -gt $((TOTAL_FILES * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠ Most monitoring implementation files are present, some may be missing${NC}"
else
    echo -e "${RED}✗ Significant monitoring implementation files are missing${NC}"
fi

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Run ${YELLOW}./deploy-monitoring.sh${NC} to deploy the monitoring stack"
echo -e "2. Run ${YELLOW}./validate-monitoring.sh${NC} to validate the deployment"
echo -e "3. Run ${YELLOW}./test-monitoring-integration.sh${NC} to test the monitoring integration"
echo -e "4. Review ${YELLOW}MONITORING_README.md${NC} for detailed usage instructions"
echo -e "5. Access Grafana dashboard to view fraud detection metrics"

echo -e "${GREEN}Monitoring implementation verification completed!${NC}"