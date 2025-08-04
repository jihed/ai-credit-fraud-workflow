#!/bin/bash
# Deployment script for fraud detection inference service
# Task 8: Deploy inference service with auto-scaling
# Requirements: 3.3 (auto-scaling), 3.4 (rolling updates)

set -euo pipefail

# Configuration
NAMESPACE="fraud-detection"
DEPLOYMENT_NAME="fraud-inference"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REPO="${IMAGE_REPO:-fraud-detection/inference}"
KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-300s}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600s}"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace $NAMESPACE does not exist, creating it..."
        kubectl apply -f namespace.yaml
    fi
    
    log_success "Prerequisites check passed"
}

# Validate deployment configuration
validate_deployment() {
    log_info "Validating deployment configuration..."
    
    # Validate YAML files
    local yaml_files=("namespace.yaml" "deployment.yaml" "ingress.yaml" "hpa-advanced.yaml")
    
    for file in "${yaml_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file $file not found"
            exit 1
        fi
        
        # Validate YAML syntax
        if ! kubectl apply --dry-run=client -f "$file" &> /dev/null; then
            log_error "Invalid YAML syntax in $file"
            exit 1
        fi
    done
    
    log_success "Deployment configuration validation passed"
}

# Deploy or update the inference service
deploy_service() {
    log_info "Deploying fraud detection inference service..."
    
    # Apply namespace first
    log_info "Creating/updating namespace..."
    kubectl apply -f namespace.yaml
    
    # Apply ConfigMap and ServiceAccount
    log_info "Applying configuration..."
    kubectl apply -f deployment.yaml --selector="kind!=Deployment,kind!=HorizontalPodAutoscaler"
    
    # Check if this is an initial deployment or update
    if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_info "Updating existing deployment with rolling update strategy..."
        update_deployment
    else
        log_info "Creating new deployment..."
        create_deployment
    fi
    
    # Apply HPA and other resources
    log_info "Applying auto-scaling configuration..."
    kubectl apply -f hpa-advanced.yaml
    
    # Apply ingress and service discovery
    log_info "Applying load balancer and service discovery..."
    kubectl apply -f ingress.yaml
    
    log_success "Deployment completed successfully"
}

# Create new deployment
create_deployment() {
    log_info "Creating new deployment..."
    
    # Apply deployment
    kubectl apply -f deployment.yaml
    
    # Wait for deployment to be ready
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout="$KUBECTL_TIMEOUT" deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
    
    # Verify pods are running
    verify_deployment
}

# Update existing deployment with rolling update
update_deployment() {
    log_info "Performing rolling update..."
    
    # Get current image
    local current_image
    current_image=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
    log_info "Current image: $current_image"
    
    # Update image if specified
    if [[ "$IMAGE_TAG" != "latest" ]]; then
        local new_image="$IMAGE_REPO:$IMAGE_TAG"
        log_info "Updating to new image: $new_image"
        kubectl set image deployment/"$DEPLOYMENT_NAME" inference="$new_image" -n "$NAMESPACE"
    else
        # Apply deployment configuration changes
        kubectl apply -f deployment.yaml
    fi
    
    # Monitor rolling update
    log_info "Monitoring rolling update progress..."
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout="$ROLLOUT_TIMEOUT"
    
    # Verify the update was successful
    verify_deployment
    
    log_success "Rolling update completed successfully"
}

# Verify deployment health
verify_deployment() {
    log_info "Verifying deployment health..."
    
    # Check deployment status
    local ready_replicas
    ready_replicas=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    local desired_replicas
    desired_replicas=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    
    if [[ "$ready_replicas" != "$desired_replicas" ]]; then
        log_error "Deployment not healthy: $ready_replicas/$desired_replicas replicas ready"
        return 1
    fi
    
    # Check pod health
    log_info "Checking pod health..."
    local unhealthy_pods
    unhealthy_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" --field-selector=status.phase!=Running --no-headers | wc -l)
    
    if [[ "$unhealthy_pods" -gt 0 ]]; then
        log_warning "$unhealthy_pods unhealthy pods found"
        kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME"
    fi
    
    # Test service endpoints
    test_service_endpoints
    
    log_success "Deployment verification completed"
}

# Test service endpoints
test_service_endpoints() {
    log_info "Testing service endpoints..."
    
    # Port forward to test service
    local port=8080
    kubectl port-forward -n "$NAMESPACE" service/fraud-inference-internal "$port":8000 &
    local port_forward_pid=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    # Test health endpoint
    if curl -f -s "http://localhost:$port/health" > /dev/null; then
        log_success "Health endpoint is responding"
    else
        log_error "Health endpoint is not responding"
        kill $port_forward_pid 2>/dev/null || true
        return 1
    fi
    
    # Test metrics endpoint
    if curl -f -s "http://localhost:$port/metrics" > /dev/null; then
        log_success "Metrics endpoint is responding"
    else
        log_warning "Metrics endpoint is not responding"
    fi
    
    # Clean up port forward
    kill $port_forward_pid 2>/dev/null || true
    
    log_success "Service endpoint tests completed"
}

# Rollback deployment if needed
rollback_deployment() {
    log_warning "Rolling back deployment..."
    
    # Get previous revision
    local previous_revision
    previous_revision=$(kubectl rollout history deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --revision=0 | tail -2 | head -1 | awk '{print $1}')
    
    if [[ -n "$previous_revision" ]]; then
        log_info "Rolling back to revision $previous_revision"
        kubectl rollout undo deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --to-revision="$previous_revision"
        kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout="$ROLLOUT_TIMEOUT"
        log_success "Rollback completed"
    else
        log_error "No previous revision found for rollback"
        return 1
    fi
}

# Monitor deployment
monitor_deployment() {
    log_info "Monitoring deployment..."
    
    # Show deployment status
    kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o wide
    
    # Show pod status
    kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o wide
    
    # Show HPA status
    kubectl get hpa -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME"
    
    # Show service status
    kubectl get service -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME"
    
    # Show recent events
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Main function
main() {
    trap cleanup EXIT
    
    log_info "Starting fraud detection inference service deployment..."
    log_info "Namespace: $NAMESPACE"
    log_info "Deployment: $DEPLOYMENT_NAME"
    log_info "Image: $IMAGE_REPO:$IMAGE_TAG"
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            validate_deployment
            deploy_service
            monitor_deployment
            ;;
        "rollback")
            rollback_deployment
            monitor_deployment
            ;;
        "monitor")
            monitor_deployment
            ;;
        "test")
            test_service_endpoints
            ;;
        "verify")
            verify_deployment
            ;;
        *)
            echo "Usage: $0 {deploy|rollback|monitor|test|verify}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Deploy or update the inference service (default)"
            echo "  rollback - Rollback to previous deployment version"
            echo "  monitor  - Show current deployment status"
            echo "  test     - Test service endpoints"
            echo "  verify   - Verify deployment health"
            echo ""
            echo "Environment variables:"
            echo "  IMAGE_TAG        - Docker image tag (default: latest)"
            echo "  IMAGE_REPO       - Docker image repository (default: fraud-detection/inference)"
            echo "  KUBECTL_TIMEOUT  - Kubectl operation timeout (default: 300s)"
            echo "  ROLLOUT_TIMEOUT  - Rollout operation timeout (default: 600s)"
            exit 1
            ;;
    esac
    
    log_success "Operation completed successfully"
}

# Run main function with all arguments
main "$@"