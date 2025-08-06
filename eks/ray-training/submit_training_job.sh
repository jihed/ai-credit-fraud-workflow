#!/bin/bash
"""
Submit Ray XGBoost Training Job
Script to submit and manage Ray-based XGBoost training jobs on EKS

Requirements implemented:
- 2.2: GPU-accelerated training job submission
- 2.3: Model artifact management
- 2.4: Training job monitoring and logging
"""

set -e

# Default configuration
NAMESPACE="ray-ml"
JOB_NAME="ray-xgboost-fraud-training"
CONFIG_NAME="training-config"
SCRIPTS_CONFIG_NAME="ray-training-scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Ray XGBoost Training Job Submission Script

Usage: $0 [OPTIONS] COMMAND

Commands:
    submit          Submit a new training job
    status          Check training job status
    logs            View training job logs
    delete          Delete training job
    monitor         Monitor training progress
    list            List all training jobs
    cleanup         Clean up completed jobs

Options:
    -n, --namespace NAMESPACE       Kubernetes namespace (default: ray-ml)
    -j, --job-name JOB_NAME        Job name (default: ray-xgboost-fraud-training)
    -b, --s3-bucket BUCKET         S3 bucket for data and models
    -d, --data-prefix PREFIX       S3 prefix for training data
    -m, --model-prefix PREFIX      S3 prefix for model output
    -w, --workers NUM              Number of Ray workers (default: 4)
    -r, --rounds NUM               Number of boosting rounds (default: 100)
    -g, --gpu                      Enable GPU training (default: true)
    -f, --max-files NUM            Maximum training files (default: 50)
    --max-depth NUM                XGBoost max depth (default: 6)
    --learning-rate RATE           Learning rate (default: 0.1)
    --scale-pos-weight WEIGHT      Scale positive weight (default: 10)
    --ray-address ADDRESS          Ray cluster address
    --aws-region REGION            AWS region (default: us-west-2)
    --timeout SECONDS              Job timeout in seconds (default: 14400)
    -h, --help                     Show this help message

Examples:
    # Submit training job with custom parameters
    $0 submit -b my-fraud-bucket -d processed-data/features -w 8 -r 200

    # Check job status
    $0 status

    # View job logs
    $0 logs

    # Monitor training progress
    $0 monitor

    # Clean up completed jobs
    $0 cleanup
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -j|--job-name)
                JOB_NAME="$2"
                shift 2
                ;;
            -b|--s3-bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            -d|--data-prefix)
                DATA_PREFIX="$2"
                shift 2
                ;;
            -m|--model-prefix)
                MODEL_PREFIX="$2"
                shift 2
                ;;
            -w|--workers)
                NUM_WORKERS="$2"
                shift 2
                ;;
            -r|--rounds)
                NUM_BOOST_ROUND="$2"
                shift 2
                ;;
            -g|--gpu)
                USE_GPU="true"
                shift
                ;;
            -f|--max-files)
                MAX_TRAINING_FILES="$2"
                shift 2
                ;;
            --max-depth)
                MAX_DEPTH="$2"
                shift 2
                ;;
            --learning-rate)
                LEARNING_RATE="$2"
                shift 2
                ;;
            --scale-pos-weight)
                SCALE_POS_WEIGHT="$2"
                shift 2
                ;;
            --ray-address)
                RAY_ADDRESS="$2"
                shift 2
                ;;
            --aws-region)
                AWS_REGION="$2"
                shift 2
                ;;
            --timeout)
                JOB_TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                COMMAND="$1"
                shift
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check namespace
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace $NAMESPACE does not exist, creating..."
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Check Ray cluster
    if ! kubectl get raycluster -n "$NAMESPACE" &> /dev/null; then
        log_warning "No Ray cluster found in namespace $NAMESPACE"
        log_info "Please ensure Ray cluster is deployed before submitting training jobs"
    fi
    
    log_success "Prerequisites validated"
}

# Create or update configuration
create_config() {
    log_info "Creating training configuration..."
    
    # Set defaults if not provided
    S3_BUCKET=${S3_BUCKET:-"your-fraud-detection-bucket"}
    DATA_PREFIX=${DATA_PREFIX:-"processed-data/features"}
    MODEL_PREFIX=${MODEL_PREFIX:-"models/xgboost"}
    NUM_WORKERS=${NUM_WORKERS:-"4"}
    NUM_BOOST_ROUND=${NUM_BOOST_ROUND:-"100"}
    USE_GPU=${USE_GPU:-"true"}
    MAX_TRAINING_FILES=${MAX_TRAINING_FILES:-"50"}
    MAX_DEPTH=${MAX_DEPTH:-"6"}
    LEARNING_RATE=${LEARNING_RATE:-"0.1"}
    SCALE_POS_WEIGHT=${SCALE_POS_WEIGHT:-"10"}
    RAY_ADDRESS=${RAY_ADDRESS:-"ray://fraud-training-cluster-head-svc.ray-ml.svc.cluster.local:10001"}
    AWS_REGION=${AWS_REGION:-"us-west-2"}
    
    # Create ConfigMap
    kubectl create configmap "$CONFIG_NAME" -n "$NAMESPACE" \
        --from-literal=s3_bucket="$S3_BUCKET" \
        --from-literal=data_prefix="$DATA_PREFIX" \
        --from-literal=model_output_prefix="$MODEL_PREFIX" \
        --from-literal=num_workers="$NUM_WORKERS" \
        --from-literal=num_boost_round="$NUM_BOOST_ROUND" \
        --from-literal=use_gpu="$USE_GPU" \
        --from-literal=max_training_files="$MAX_TRAINING_FILES" \
        --from-literal=max_depth="$MAX_DEPTH" \
        --from-literal=learning_rate="$LEARNING_RATE" \
        --from-literal=scale_pos_weight="$SCALE_POS_WEIGHT" \
        --from-literal=ray_address="$RAY_ADDRESS" \
        --from-literal=aws_region="$AWS_REGION" \
        --from-literal=enable_cloudwatch="true" \
        --from-literal=cloudwatch_log_group="/aws/eks/ray-training" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Training configuration created/updated"
}

# Create scripts ConfigMap
create_scripts_config() {
    log_info "Creating training scripts configuration..."
    
    # Check if script files exist
    if [[ ! -f "ray_xgboost_trainer.py" ]]; then
        log_error "ray_xgboost_trainer.py not found in current directory"
        exit 1
    fi
    
    if [[ ! -f "training_monitor.py" ]]; then
        log_error "training_monitor.py not found in current directory"
        exit 1
    fi
    
    # Create ConfigMap from files
    kubectl create configmap "$SCRIPTS_CONFIG_NAME" -n "$NAMESPACE" \
        --from-file=ray_xgboost_trainer.py \
        --from-file=training_monitor.py \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Training scripts configuration created/updated"
}

# Submit training job
submit_job() {
    log_info "Submitting Ray XGBoost training job..."
    
    validate_prerequisites
    create_config
    create_scripts_config
    
    # Generate unique job name with timestamp
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    UNIQUE_JOB_NAME="${JOB_NAME}-${TIMESTAMP}"
    
    # Create job manifest
    cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${UNIQUE_JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ray-training
    workload: fraud-detection
    job-type: xgboost-training
    timestamp: "${TIMESTAMP}"
spec:
  template:
    metadata:
      labels:
        app: ray-training
        workload: fraud-detection
        job-type: xgboost-training
    spec:
      restartPolicy: Never
      containers:
      - name: ray-training-job
        image: rayproject/ray-ml:2.8.0-gpu
        imagePullPolicy: IfNotPresent
        command: ["python"]
        args: ["/app/ray_xgboost_trainer.py", 
               "--s3-bucket", "\$(S3_BUCKET)",
               "--data-prefix", "\$(DATA_PREFIX)",
               "--model-output-prefix", "\$(MODEL_OUTPUT_PREFIX)",
               "--num-workers", "\$(NUM_WORKERS)",
               "--num-boost-round", "\$(NUM_BOOST_ROUND)",
               "--max-training-files", "\$(MAX_TRAINING_FILES)",
               "--max-depth", "\$(MAX_DEPTH)",
               "--learning-rate", "\$(LEARNING_RATE)",
               "--scale-pos-weight", "\$(SCALE_POS_WEIGHT)",
               "--ray-address", "\$(RAY_ADDRESS)"]
        envFrom:
        - configMapRef:
            name: ${CONFIG_NAME}
        env:
        - name: RAY_DISABLE_IMPORT_WARNING
          value: "1"
        - name: PYTHONPATH
          value: "/app"
        - name: AWS_DEFAULT_REGION
          valueFrom:
            configMapKeyRef:
              name: ${CONFIG_NAME}
              key: aws_region
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
        volumeMounts:
        - name: training-scripts
          mountPath: /app
          readOnly: true
        - name: tmp-storage
          mountPath: /tmp
      volumes:
      - name: training-scripts
        configMap:
          name: ${SCRIPTS_CONFIG_NAME}
          defaultMode: 0755
      - name: tmp-storage
        emptyDir:
          sizeLimit: 10Gi
      nodeSelector:
        NodeGroupType: core
  backoffLimit: 2
  ttlSecondsAfterFinished: 7200
  activeDeadlineSeconds: ${JOB_TIMEOUT:-14400}
EOF
    
    log_success "Training job ${UNIQUE_JOB_NAME} submitted successfully"
    log_info "Use '$0 status -j ${UNIQUE_JOB_NAME}' to check job status"
    log_info "Use '$0 logs -j ${UNIQUE_JOB_NAME}' to view job logs"
}

# Check job status
check_status() {
    log_info "Checking training job status..."
    
    if [[ -z "$JOB_NAME" ]]; then
        # List all training jobs
        kubectl get jobs -n "$NAMESPACE" -l app=ray-training --sort-by=.metadata.creationTimestamp
    else
        # Check specific job
        kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o wide
        echo
        kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o wide
    fi
}

# View job logs
view_logs() {
    log_info "Viewing training job logs..."
    
    if [[ -z "$JOB_NAME" ]]; then
        log_error "Job name is required for viewing logs"
        exit 1
    fi
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$POD_NAME" ]]; then
        log_error "No pod found for job $JOB_NAME"
        exit 1
    fi
    
    log_info "Showing logs for pod: $POD_NAME"
    kubectl logs -n "$NAMESPACE" "$POD_NAME" -f
}

# Monitor training progress
monitor_training() {
    log_info "Monitoring training progress..."
    
    if [[ -z "$JOB_NAME" ]]; then
        log_error "Job name is required for monitoring"
        exit 1
    fi
    
    # Monitor job status and logs
    while true; do
        clear
        echo "=== Training Job Monitor ==="
        echo "Job: $JOB_NAME"
        echo "Namespace: $NAMESPACE"
        echo "Time: $(date)"
        echo
        
        # Job status
        echo "=== Job Status ==="
        kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o wide 2>/dev/null || echo "Job not found"
        echo
        
        # Pod status
        echo "=== Pod Status ==="
        kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o wide 2>/dev/null || echo "No pods found"
        echo
        
        # Recent logs
        echo "=== Recent Logs ==="
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$POD_NAME" ]]; then
            kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=10 2>/dev/null || echo "No logs available"
        else
            echo "No pod available for logs"
        fi
        
        echo
        echo "Press Ctrl+C to exit monitoring"
        sleep 30
    done
}

# Delete training job
delete_job() {
    log_info "Deleting training job..."
    
    if [[ -z "$JOB_NAME" ]]; then
        log_error "Job name is required for deletion"
        exit 1
    fi
    
    kubectl delete job "$JOB_NAME" -n "$NAMESPACE"
    log_success "Training job $JOB_NAME deleted"
}

# List all training jobs
list_jobs() {
    log_info "Listing all training jobs..."
    
    echo "=== Active Jobs ==="
    kubectl get jobs -n "$NAMESPACE" -l app=ray-training --sort-by=.metadata.creationTimestamp
    
    echo
    echo "=== Job Pods ==="
    kubectl get pods -n "$NAMESPACE" -l app=ray-training --sort-by=.metadata.creationTimestamp
}

# Cleanup completed jobs
cleanup_jobs() {
    log_info "Cleaning up completed training jobs..."
    
    # Delete completed jobs older than 2 hours
    kubectl get jobs -n "$NAMESPACE" -l app=ray-training -o json | \
    jq -r '.items[] | select(.status.conditions[]?.type == "Complete") | select((now - (.status.completionTime | fromdateiso8601)) > 7200) | .metadata.name' | \
    while read job; do
        if [[ -n "$job" ]]; then
            log_info "Deleting completed job: $job"
            kubectl delete job "$job" -n "$NAMESPACE"
        fi
    done
    
    # Delete failed jobs older than 1 hour
    kubectl get jobs -n "$NAMESPACE" -l app=ray-training -o json | \
    jq -r '.items[] | select(.status.conditions[]?.type == "Failed") | select((now - (.status.conditions[] | select(.type == "Failed") | .lastTransitionTime | fromdateiso8601)) > 3600) | .metadata.name' | \
    while read job; do
        if [[ -n "$job" ]]; then
            log_info "Deleting failed job: $job"
            kubectl delete job "$job" -n "$NAMESPACE"
        fi
    done
    
    log_success "Cleanup completed"
}

# Main function
main() {
    parse_args "$@"
    
    case "$COMMAND" in
        submit)
            submit_job
            ;;
        status)
            check_status
            ;;
        logs)
            view_logs
            ;;
        monitor)
            monitor_training
            ;;
        delete)
            delete_job
            ;;
        list)
            list_jobs
            ;;
        cleanup)
            cleanup_jobs
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"