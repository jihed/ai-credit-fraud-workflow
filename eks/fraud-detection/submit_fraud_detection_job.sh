#!/bin/bash

#--------------------------------------------
# Fraud Detection Feature Engineering Job Submission Script
# EMR on EKS with RAPIDS GPU Acceleration
#--------------------------------------------

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#--------------------------------------------
# DEFAULT CONFIGURATION
#--------------------------------------------
JOB_NAME="fraud-detection-feature-engineering-$(date +%Y%m%d-%H%M%S)"
EMR_EKS_RELEASE_LABEL="emr-7.0.0-spark-rapids-latest"
AWS_REGION="${AWS_REGION:-us-west-2}"
NUM_EXECUTORS="${NUM_EXECUTORS:-12}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Docker image configuration
DEFAULT_IMAGE="public.ecr.aws/data-on-eks/fraud-detection-rapids:latest"
FRAUD_DETECTION_IMAGE="${FRAUD_DETECTION_IMAGE:-$DEFAULT_IMAGE}"

#--------------------------------------------
# PARAMETER VALIDATION AND INPUT
#--------------------------------------------
validate_parameters() {
    log "Validating parameters..."
    
    # Check if required environment variables are set
    if [[ -z "$EMR_VIRTUAL_CLUSTER_ID" ]]; then
        error "EMR_VIRTUAL_CLUSTER_ID environment variable is required"
        exit 1
    fi
    
    if [[ -z "$EMR_EXECUTION_ROLE_ARN" ]]; then
        error "EMR_EXECUTION_ROLE_ARN environment variable is required"
        exit 1
    fi
    
    if [[ -z "$S3_BUCKET" ]]; then
        error "S3_BUCKET environment variable is required"
        exit 1
    fi
    
    if [[ -z "$CLOUDWATCH_LOG_GROUP" ]]; then
        error "CLOUDWATCH_LOG_GROUP environment variable is required"
        exit 1
    fi
    
    # Validate S3 bucket access
    if ! aws s3 ls "s3://${S3_BUCKET}" > /dev/null 2>&1; then
        error "Cannot access S3 bucket: ${S3_BUCKET}"
        exit 1
    fi
    
    success "Parameter validation completed"
}

# Interactive parameter collection if not provided via environment
collect_parameters() {
    log "Collecting job parameters..."
    
    # EMR Virtual Cluster ID
    if [[ -z "$EMR_VIRTUAL_CLUSTER_ID" ]]; then
        read -p "Enter EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
    fi
    
    # EMR Execution Role ARN
    if [[ -z "$EMR_EXECUTION_ROLE_ARN" ]]; then
        read -p "Enter EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
    fi
    
    # CloudWatch Log Group
    if [[ -z "$CLOUDWATCH_LOG_GROUP" ]]; then
        read -p "Enter CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
    fi
    
    # S3 Bucket
    if [[ -z "$S3_BUCKET" ]]; then
        read -p "Enter S3 Bucket name (without s3:// prefix): " S3_BUCKET
    fi
    
    # Data paths
    if [[ -z "$CUSTOMERS_S3_PATH" ]]; then
        read -p "Enter customers data S3 path [s3://${S3_BUCKET}/data/customers/]: " CUSTOMERS_S3_PATH
        CUSTOMERS_S3_PATH="${CUSTOMERS_S3_PATH:-s3://${S3_BUCKET}/data/customers/}"
    fi
    
    if [[ -z "$TERMINALS_S3_PATH" ]]; then
        read -p "Enter terminals data S3 path [s3://${S3_BUCKET}/data/terminals/]: " TERMINALS_S3_PATH
        TERMINALS_S3_PATH="${TERMINALS_S3_PATH:-s3://${S3_BUCKET}/data/terminals/}"
    fi
    
    if [[ -z "$TRANSACTIONS_S3_PATH" ]]; then
        read -p "Enter transactions data S3 path [s3://${S3_BUCKET}/data/transactions/]: " TRANSACTIONS_S3_PATH
        TRANSACTIONS_S3_PATH="${TRANSACTIONS_S3_PATH:-s3://${S3_BUCKET}/data/transactions/}"
    fi
    
    if [[ -z "$OUTPUT_S3_PATH" ]]; then
        read -p "Enter output S3 path [s3://${S3_BUCKET}/output/fraud-detection/]: " OUTPUT_S3_PATH
        OUTPUT_S3_PATH="${OUTPUT_S3_PATH:-s3://${S3_BUCKET}/output/fraud-detection/}"
    fi
    
    # Optional parameters
    read -p "Enter number of executors [${NUM_EXECUTORS}]: " input_executors
    NUM_EXECUTORS="${input_executors:-$NUM_EXECUTORS}"
    
    read -p "Enter Docker image URI [${FRAUD_DETECTION_IMAGE}]: " input_image
    FRAUD_DETECTION_IMAGE="${input_image:-$FRAUD_DETECTION_IMAGE}"
    
    read -p "Enter environment [${ENVIRONMENT}]: " input_env
    ENVIRONMENT="${input_env:-$ENVIRONMENT}"
}

#--------------------------------------------
# S3 UPLOAD FUNCTIONS
#--------------------------------------------
upload_scripts_to_s3() {
    log "Uploading scripts and templates to S3..."
    
    SCRIPTS_S3_PATH="s3://${S3_BUCKET}/${EMR_VIRTUAL_CLUSTER_ID}/${JOB_NAME}/scripts"
    
    # Upload Python script
    aws s3 cp fraud_detection_feature_engineering.py "${SCRIPTS_S3_PATH}/"
    
    # Upload pod templates
    aws s3 cp driver-pod-template.yaml "${SCRIPTS_S3_PATH}/"
    aws s3 cp executor-pod-template.yaml "${SCRIPTS_S3_PATH}/"
    
    # Upload job template
    aws s3 cp fraud-detection-job-template.json "${SCRIPTS_S3_PATH}/"
    
    success "Scripts uploaded to ${SCRIPTS_S3_PATH}"
}

#--------------------------------------------
# JOB SUBMISSION
#--------------------------------------------
submit_job() {
    log "Submitting fraud detection feature engineering job..."
    
    # Create job configuration from template
    local job_config=$(cat fraud-detection-job-template.json | \
        sed "s|\${EMR_VIRTUAL_CLUSTER_ID}|${EMR_VIRTUAL_CLUSTER_ID}|g" | \
        sed "s|\${EMR_EXECUTION_ROLE_ARN}|${EMR_EXECUTION_ROLE_ARN}|g" | \
        sed "s|\${SCRIPTS_S3_PATH}|${SCRIPTS_S3_PATH}|g" | \
        sed "s|\${CUSTOMERS_S3_PATH}|${CUSTOMERS_S3_PATH}|g" | \
        sed "s|\${TERMINALS_S3_PATH}|${TERMINALS_S3_PATH}|g" | \
        sed "s|\${TRANSACTIONS_S3_PATH}|${TRANSACTIONS_S3_PATH}|g" | \
        sed "s|\${OUTPUT_S3_PATH}|${OUTPUT_S3_PATH}|g" | \
        sed "s|\${FRAUD_DETECTION_IMAGE}|${FRAUD_DETECTION_IMAGE}|g" | \
        sed "s|\${NUM_EXECUTORS}|${NUM_EXECUTORS}|g" | \
        sed "s|\${CLOUDWATCH_LOG_GROUP}|${CLOUDWATCH_LOG_GROUP}|g" | \
        sed "s|\${S3_BUCKET}|s3://${S3_BUCKET}|g" | \
        sed "s|\${ENVIRONMENT}|${ENVIRONMENT}|g")
    
    # Submit job to EMR on EKS
    local job_run_id=$(aws emr-containers start-job-run \
        --region "${AWS_REGION}" \
        --cli-input-json "${job_config}" \
        --query 'id' \
        --output text)
    
    if [[ $? -eq 0 ]]; then
        success "Job submitted successfully!"
        log "Job Run ID: ${job_run_id}"
        log "Job Name: ${JOB_NAME}"
        log "Virtual Cluster ID: ${EMR_VIRTUAL_CLUSTER_ID}"
        
        # Provide monitoring commands
        echo ""
        log "Monitor your job with the following commands:"
        echo "  aws emr-containers describe-job-run --virtual-cluster-id ${EMR_VIRTUAL_CLUSTER_ID} --id ${job_run_id}"
        echo "  aws logs tail ${CLOUDWATCH_LOG_GROUP} --follow"
        echo ""
        log "Check job status in AWS Console:"
        echo "  https://console.aws.amazon.com/emr/home?region=${AWS_REGION}#/containers/clusters/${EMR_VIRTUAL_CLUSTER_ID}/job-runs/${job_run_id}"
        
        return 0
    else
        error "Job submission failed"
        return 1
    fi
}

#--------------------------------------------
# MAIN EXECUTION
#--------------------------------------------
main() {
    log "Starting fraud detection feature engineering job submission..."
    
    # Check if running in interactive mode
    if [[ -t 0 ]]; then
        collect_parameters
    fi
    
    validate_parameters
    upload_scripts_to_s3
    submit_job
    
    success "Job submission completed successfully!"
}

# Help function
show_help() {
    cat << EOF
Fraud Detection Feature Engineering Job Submission Script

Usage: $0 [OPTIONS]

Environment Variables:
  EMR_VIRTUAL_CLUSTER_ID    EMR Virtual Cluster ID (required)
  EMR_EXECUTION_ROLE_ARN    EMR Execution Role ARN (required)
  S3_BUCKET                 S3 bucket name for data and scripts (required)
  CLOUDWATCH_LOG_GROUP      CloudWatch log group name (required)
  
  CUSTOMERS_S3_PATH         S3 path to customers data
  TERMINALS_S3_PATH         S3 path to terminals data  
  TRANSACTIONS_S3_PATH      S3 path to transactions data
  OUTPUT_S3_PATH            S3 path for output data
  
  NUM_EXECUTORS             Number of Spark executors (default: 12)
  FRAUD_DETECTION_IMAGE     Docker image URI
  ENVIRONMENT               Environment name (default: dev)
  AWS_REGION                AWS region (default: us-west-2)

Options:
  -h, --help               Show this help message

Examples:
  # Interactive mode
  $0
  
  # With environment variables
  export EMR_VIRTUAL_CLUSTER_ID="your-cluster-id"
  export EMR_EXECUTION_ROLE_ARN="your-role-arn"
  export S3_BUCKET="your-bucket"
  export CLOUDWATCH_LOG_GROUP="/emr-on-eks-logs/your-cluster/emr-ml-team-a/"
  $0

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac