#!/bin/bash

#--------------------------------------------
# Docker Image Build Script for Fraud Detection with RAPIDS
# Builds and pushes custom Docker image to ECR
#--------------------------------------------

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
# CONFIGURATION
#--------------------------------------------
IMAGE_NAME="fraud-detection-rapids"
IMAGE_TAG="${IMAGE_TAG:-latest}"
AWS_REGION="${AWS_REGION:-us-west-2}"
PLATFORM="${PLATFORM:-linux/amd64}"

# ECR configuration
ECR_REGISTRY="${ECR_REGISTRY}"
ECR_REPOSITORY="${ECR_REPOSITORY:-data-on-eks/${IMAGE_NAME}}"

#--------------------------------------------
# FUNCTIONS
#--------------------------------------------
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check if buildx is available for multi-platform builds
    if ! docker buildx version &> /dev/null; then
        warning "Docker buildx not available, using standard build"
        USE_BUILDX=false
    else
        USE_BUILDX=true
    fi
    
    success "Prerequisites check completed"
}

get_ecr_details() {
    if [[ -z "$ECR_REGISTRY" ]]; then
        log "Getting ECR registry details..."
        
        # Get AWS account ID
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        if [[ $? -ne 0 ]]; then
            error "Failed to get AWS account ID"
            exit 1
        fi
        
        ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        log "Using ECR registry: ${ECR_REGISTRY}"
    fi
    
    FULL_IMAGE_NAME="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
}

create_ecr_repository() {
    log "Creating ECR repository if it doesn't exist..."
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" --region "${AWS_REGION}" &> /dev/null; then
        log "ECR repository ${ECR_REPOSITORY} already exists"
    else
        log "Creating ECR repository: ${ECR_REPOSITORY}"
        aws ecr create-repository \
            --repository-name "${ECR_REPOSITORY}" \
            --region "${AWS_REGION}" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        
        if [[ $? -eq 0 ]]; then
            success "ECR repository created successfully"
        else
            error "Failed to create ECR repository"
            exit 1
        fi
    fi
}

login_to_ecr() {
    log "Logging in to ECR..."
    
    # Login to public ECR for base image
    aws ecr-public get-login-password --region us-east-1 | \
        docker login --username AWS --password-stdin public.ecr.aws
    
    if [[ $? -ne 0 ]]; then
        error "Failed to login to public ECR"
        exit 1
    fi
    
    # Login to private ECR
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_REGISTRY}"
    
    if [[ $? -eq 0 ]]; then
        success "Successfully logged in to ECR"
    else
        error "Failed to login to ECR"
        exit 1
    fi
}

build_image() {
    log "Building Docker image: ${FULL_IMAGE_NAME}"
    
    # Build arguments
    BUILD_ARGS=(
        --build-arg RAPIDS_VERSION=23.12
        --build-arg PYTHON_VERSION=3.9
        --build-arg CUDA_VERSION=11.8
        --tag "${FULL_IMAGE_NAME}"
        --file Dockerfile.rapids
    )
    
    if [[ "$USE_BUILDX" == "true" ]]; then
        log "Using Docker buildx for multi-platform build"
        
        # Create builder if it doesn't exist
        if ! docker buildx inspect fraud-detection-builder &> /dev/null; then
            docker buildx create --name fraud-detection-builder --use
        else
            docker buildx use fraud-detection-builder
        fi
        
        # Build with buildx
        docker buildx build \
            "${BUILD_ARGS[@]}" \
            --platform "${PLATFORM}" \
            --push \
            .
    else
        log "Using standard Docker build"
        
        # Standard build
        docker build "${BUILD_ARGS[@]}" .
        
        # Push image
        docker push "${FULL_IMAGE_NAME}"
    fi
    
    if [[ $? -eq 0 ]]; then
        success "Docker image built and pushed successfully"
        log "Image URI: ${FULL_IMAGE_NAME}"
    else
        error "Failed to build or push Docker image"
        exit 1
    fi
}

scan_image() {
    log "Starting ECR image scan..."
    
    aws ecr start-image-scan \
        --repository-name "${ECR_REPOSITORY}" \
        --image-id imageTag="${IMAGE_TAG}" \
        --region "${AWS_REGION}" &> /dev/null
    
    if [[ $? -eq 0 ]]; then
        log "Image scan initiated. Check AWS Console for results."
    else
        warning "Failed to start image scan (may already be in progress)"
    fi
}

cleanup() {
    log "Cleaning up..."
    
    # Remove builder if created
    if [[ "$USE_BUILDX" == "true" ]] && docker buildx inspect fraud-detection-builder &> /dev/null; then
        docker buildx rm fraud-detection-builder &> /dev/null || true
    fi
    
    # Clean up dangling images
    docker image prune -f &> /dev/null || true
    
    log "Cleanup completed"
}

#--------------------------------------------
# MAIN EXECUTION
#--------------------------------------------
main() {
    log "Starting Docker image build for fraud detection with RAPIDS..."
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    check_prerequisites
    get_ecr_details
    create_ecr_repository
    login_to_ecr
    build_image
    scan_image
    
    success "Docker image build completed successfully!"
    echo ""
    log "Image details:"
    echo "  Registry: ${ECR_REGISTRY}"
    echo "  Repository: ${ECR_REPOSITORY}"
    echo "  Tag: ${IMAGE_TAG}"
    echo "  Full URI: ${FULL_IMAGE_NAME}"
    echo ""
    log "Use this image URI in your EMR on EKS job configuration:"
    echo "  export FRAUD_DETECTION_IMAGE=\"${FULL_IMAGE_NAME}\""
}

# Help function
show_help() {
    cat << EOF
Docker Image Build Script for Fraud Detection with RAPIDS

Usage: $0 [OPTIONS]

Environment Variables:
  ECR_REGISTRY              ECR registry URL (auto-detected if not provided)
  ECR_REPOSITORY            ECR repository name (default: data-on-eks/fraud-detection-rapids)
  IMAGE_TAG                 Docker image tag (default: latest)
  AWS_REGION                AWS region (default: us-west-2)
  PLATFORM                  Target platform (default: linux/amd64)

Options:
  -h, --help               Show this help message

Examples:
  # Basic build
  $0
  
  # Custom repository and tag
  export ECR_REPOSITORY="my-repo/fraud-detection"
  export IMAGE_TAG="v1.0.0"
  $0
  
  # Different region
  export AWS_REGION="us-east-1"
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