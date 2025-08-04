#!/bin/bash

# Production Readiness Validation Runner
# This script runs comprehensive production readiness validation for the EMR to EKS migration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Default configuration
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-data-on-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-fraud-detection}"
INFERENCE_SERVICE_URL="${INFERENCE_SERVICE_URL:-http://localhost:8000}"
APPLY_OPTIMIZATIONS="${APPLY_OPTIMIZATIONS:-false}"

# Create reports directory
mkdir -p "$REPORTS_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Production Readiness Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Start time: $(date)"
echo "Cluster: $EKS_CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Namespace: $KUBERNETES_NAMESPACE"
echo "Reports directory: $REPORTS_DIR"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python 3 is required but not installed${NC}"
        exit 1
    fi
    
    # Check required Python packages
    python3 -c "import boto3, kubernetes, requests, pandas, numpy" 2>/dev/null || {
        echo -e "${YELLOW}Installing required Python packages...${NC}"
        pip3 install boto3 kubernetes requests pandas numpy --quiet
    }
    
    # Check AWS CLI (optional)
    if command -v aws &> /dev/null; then
        echo "AWS CLI found: $(aws --version)"
        
        # Check AWS credentials
        if aws sts get-caller-identity &> /dev/null; then
            echo -e "${GREEN}✓ AWS credentials configured${NC}"
        else
            echo -e "${YELLOW}⚠ AWS credentials not configured - some tests may fail${NC}"
        fi
    else
        echo -e "${YELLOW}AWS CLI not found - some tests may be limited${NC}"
    fi
    
    # Check kubectl (optional)
    if command -v kubectl &> /dev/null; then
        echo "kubectl found: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
        
        # Check cluster connectivity
        if kubectl cluster-info &> /dev/null; then
            echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"
        else
            echo -e "${YELLOW}⚠ Kubernetes cluster not accessible - some tests will be mocked${NC}"
        fi
    else
        echo -e "${YELLOW}kubectl not found - Kubernetes tests will be mocked${NC}"
    fi
    
    echo -e "${GREEN}✓ Prerequisites check completed${NC}"
    echo ""
}

# Function to validate infrastructure readiness
validate_infrastructure() {
    echo -e "${YELLOW}Validating infrastructure readiness...${NC}"
    
    # Check EKS cluster status
    if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
        echo "Checking EKS cluster status..."
        
        CLUSTER_STATUS=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
            echo -e "${GREEN}✓ EKS cluster $EKS_CLUSTER_NAME is active${NC}"
        else
            echo -e "${YELLOW}⚠ EKS cluster status: $CLUSTER_STATUS${NC}"
        fi
    fi
    
    # Check namespace exists
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        if kubectl get namespace "$KUBERNETES_NAMESPACE" &> /dev/null; then
            echo -e "${GREEN}✓ Namespace $KUBERNETES_NAMESPACE exists${NC}"
        else
            echo -e "${YELLOW}⚠ Namespace $KUBERNETES_NAMESPACE not found${NC}"
        fi
        
        # Check key deployments
        INFERENCE_DEPLOYMENT=$(kubectl get deployment fraud-inference -n "$KUBERNETES_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$INFERENCE_DEPLOYMENT" -gt 0 ]; then
            echo -e "${GREEN}✓ Inference service deployment found${NC}"
        else
            echo -e "${YELLOW}⚠ Inference service deployment not found${NC}"
        fi
    fi
    
    echo ""
}

# Function to run the validation
run_validation() {
    echo -e "${YELLOW}Running production readiness validation...${NC}"
    
    # Set environment variables
    export EKS_CLUSTER_NAME="$EKS_CLUSTER_NAME"
    export AWS_REGION="$AWS_REGION"
    export KUBERNETES_NAMESPACE="$KUBERNETES_NAMESPACE"
    export INFERENCE_SERVICE_URL="$INFERENCE_SERVICE_URL"
    export APPLY_OPTIMIZATIONS="$APPLY_OPTIMIZATIONS"
    export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"
    
    # Run the validation script
    cd "$SCRIPT_DIR"
    
    if python3 production-readiness-validation.py \
        --region "$AWS_REGION" \
        --cluster-name "$EKS_CLUSTER_NAME" \
        --namespace "$KUBERNETES_NAMESPACE" \
        --inference-url "$INFERENCE_SERVICE_URL" \
        $([ "$APPLY_OPTIMIZATIONS" = "true" ] && echo "--apply-optimizations"); then
        
        echo -e "${GREEN}✓ Production readiness validation completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Production readiness validation failed${NC}"
        return 1
    fi
}

# Function to generate summary
generate_summary() {
    echo -e "${YELLOW}Generating validation summary...${NC}"
    
    # Find the latest report file
    LATEST_REPORT=$(find "$REPORTS_DIR" -name "production_readiness_report_*.json" -type f -exec ls -t {} + | head -n1)
    
    if [ -n "$LATEST_REPORT" ] && [ -f "$LATEST_REPORT" ]; then
        echo "Latest report: $LATEST_REPORT"
        
        # Extract key metrics using jq if available
        if command -v jq &> /dev/null; then
            echo ""
            echo -e "${BLUE}=== Validation Summary ===${NC}"
            
            CONFIDENCE_SCORE=$(jq -r '.overall_summary.overall_confidence_score // "N/A"' "$LATEST_REPORT")
            PERFORMANCE_GRADE=$(jq -r '.overall_summary.performance_grade // "N/A"' "$LATEST_REPORT")
            AUTOSCALING_GRADE=$(jq -r '.overall_summary.autoscaling_grade // "N/A"' "$LATEST_REPORT")
            COST_OPTIMIZATION=$(jq -r '.overall_summary.cost_optimization_potential // "N/A"' "$LATEST_REPORT")
            
            echo "Overall Confidence Score: $CONFIDENCE_SCORE%"
            echo "Performance Grade: $PERFORMANCE_GRADE"
            echo "Auto-scaling Grade: $AUTOSCALING_GRADE"
            echo "Cost Optimization Potential: $COST_OPTIMIZATION%"
            
            echo ""
            echo -e "${BLUE}=== Key Recommendations ===${NC}"
            jq -r '.recommendations[]' "$LATEST_REPORT" 2>/dev/null | head -5 | while read -r rec; do
                echo "• $rec"
            done
        else
            echo "Install jq for detailed summary parsing: brew install jq"
        fi
    else
        echo -e "${YELLOW}No report file found${NC}"
    fi
}

# Function to display next steps
display_next_steps() {
    echo ""
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo "1. Review the detailed validation report"
    echo "2. Address any failing validation checks"
    echo "3. Implement recommended optimizations"
    echo "4. Set up continuous monitoring and alerting"
    echo "5. Plan gradual production traffic migration"
    echo ""
    echo -e "${BLUE}=== Useful Commands ===${NC}"
    echo "View latest report:"
    echo "  cat \$(find $REPORTS_DIR -name 'production_readiness_report_*.json' -type f -exec ls -t {} + | head -n1)"
    echo ""
    echo "Re-run validation with optimizations:"
    echo "  APPLY_OPTIMIZATIONS=true $0"
    echo ""
    echo "Monitor cluster resources:"
    echo "  kubectl top nodes"
    echo "  kubectl top pods -n $KUBERNETES_NAMESPACE"
}

# Main execution
main() {
    local exit_code=0
    
    # Check prerequisites
    check_prerequisites
    
    # Validate infrastructure
    validate_infrastructure
    
    # Run validation
    if run_validation; then
        echo ""
        echo -e "${GREEN}✓ Production readiness validation completed successfully${NC}"
    else
        exit_code=1
        echo ""
        echo -e "${RED}✗ Production readiness validation failed${NC}"
    fi
    
    # Generate summary
    generate_summary
    
    # Display next steps
    display_next_steps
    
    # Final summary
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Validation Complete${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "End time: $(date)"
    echo "Total duration: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
    echo "Reports location: $REPORTS_DIR"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Production readiness validation successful${NC}"
    else
        echo -e "${RED}✗ Production readiness validation failed - check logs${NC}"
    fi
    
    exit $exit_code
}

# Handle script interruption
trap 'echo -e "\n${RED}Validation interrupted${NC}"; exit 130' INT TERM

# Run main function
main "$@"