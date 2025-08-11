#!/bin/bash

# Build all Docker images for fraud detection
# Consolidated build script with proper error handling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}

# Get AWS account ID
if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    print_error "Failed to get AWS account ID. Please check AWS CLI configuration."
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

print_header "Fraud Detection Docker Image Builder"
print_status "AWS Account ID: $AWS_ACCOUNT_ID"
print_status "ECR Registry: $ECR_REGISTRY"
print_status "AWS Region: $AWS_REGION"

# Image configurations
UNIFIED_IMAGE="fraud-detection/unified-notebook"
EMR_IMAGE="fraud-detection/emr-spark"
RAPIDS_IMAGE="fraud-detection/emr-rapids"

# Function to get image name by type
get_image_name() {
    case "$1" in
        "unified") echo "$UNIFIED_IMAGE" ;;
        "emr") echo "$EMR_IMAGE" ;;
        "rapids") echo "$RAPIDS_IMAGE" ;;
        *) echo "" ;;
    esac
}

# Function to get all image types
get_all_image_types() {
    echo "unified emr rapids"
}

# Function to create ECR repository
create_ecr_repo() {
    local repo_name=$1
    
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Creating ECR repository: $repo_name"
        aws ecr create-repository \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 >/dev/null
        print_status "✅ Created ECR repository: $repo_name"
    else
        print_status "✅ ECR repository $repo_name already exists"
    fi
}

# Function to prepare build context
prepare_build_context() {
    print_status "Preparing build context..."
    
    # Ensure notebooks and src directories exist
    if [ ! -d "notebooks" ]; then
        print_warning "notebooks directory not found, creating empty one"
        mkdir -p notebooks
    fi
    
    if [ ! -d "src" ]; then
        print_warning "src directory not found, creating empty one"
        mkdir -p src
    fi
    
    print_status "✅ Build context ready"
}

# Function to validate RAPIDS container
validate_rapids_container() {
    local image_name=$1
    local tag=$2
    
    print_status "Validating RAPIDS container functionality..."
    
    # Check if validation files exist
    if [ ! -f "test_container.py" ]; then
        print_warning "test_container.py not found, skipping container validation"
        return 0
    fi
    
    # Run container validation
    if docker run --name rapids-validation-test --rm \
        -v "$(pwd)/test_container.py:/test_container.py" \
        "$image_name:$tag" python3 /test_container.py; then
        print_status "✅ RAPIDS container validation passed"
        return 0
    else
        print_error "❌ RAPIDS container validation failed"
        return 1
    fi
}

# Function to build and push image
build_and_push() {
    local dockerfile=$1
    local image_name=$2
    local tag=${3:-latest}
    
    print_header "Building $image_name from $dockerfile"
    
    # Create ECR repository
    create_ecr_repo "$image_name"
    
    # Build image for AMD64/x86_64 (EC2 compatible)
    print_status "Building Docker image for AMD64 platform..."
    if docker build --platform linux/amd64 --no-cache -f "$dockerfile" -t "$image_name:$tag" .; then
        print_status "✅ Successfully built $image_name:$tag"
        
        # Verify the image architecture
        ARCH=$(docker inspect "$image_name:$tag" --format='{{.Architecture}}')
        print_status "Image architecture: $ARCH"
        if [ "$ARCH" != "amd64" ]; then
            print_error "❌ Image built for wrong architecture: $ARCH (expected: amd64)"
            return 1
        fi
    else
        print_error "❌ Failed to build $image_name:$tag"
        return 1
    fi
    
    # Special validation for RAPIDS image
    if [[ "$image_name" == *"rapids"* ]]; then
        if ! validate_rapids_container "$image_name" "$tag"; then
            print_error "❌ RAPIDS container validation failed"
            return 1
        fi
    fi
    
    # Tag for ECR
    local ecr_image="$ECR_REGISTRY/$image_name:$tag"
    print_status "Tagging for ECR: $ecr_image"
    docker tag "$image_name:$tag" "$ecr_image"
    
    # Push to ECR
    print_status "Pushing to ECR..."
    if docker push "$ecr_image"; then
        print_status "✅ Successfully pushed $ecr_image"
        return 0
    else
        print_error "❌ Failed to push $ecr_image"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_status "✅ All prerequisites met"
}

# Function to login to registries
login_to_registries() {
    print_status "Logging in to container registries..."
    
    # Login to ECR
    if aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"; then
        print_status "✅ Logged in to ECR"
    else
        print_error "❌ Failed to login to ECR"
        exit 1
    fi
    
    # Login to public ECR
    if aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws; then
        print_status "✅ Logged in to public ECR"
    else
        print_warning "⚠️  Failed to login to public ECR (may affect EMR/RAPIDS builds)"
    fi
}

# Function to build specific image
build_single() {
    local image_type=$1
    
    if [ -z "$image_type" ]; then
        print_error "Please specify an image type to build"
        echo "Available images:"
        for image_type in $(get_all_image_types); do
            echo "  - $image_type ($(get_image_name "$image_type"))"
        done
        exit 1
    fi
    
    local image_name=$(get_image_name "$image_type")
    if [ -z "$image_name" ]; then
        print_error "Unknown image type: $image_type"
        exit 1
    fi
    
    local dockerfile="Dockerfile.$image_type"
    
    if [ ! -f "$dockerfile" ]; then
        print_error "Dockerfile not found: $dockerfile"
        exit 1
    fi
    
    check_prerequisites
    login_to_registries
    prepare_build_context
    
    if build_and_push "$dockerfile" "$image_name" "latest"; then
        print_status "🎉 Successfully built $image_name"
        echo
        print_status "Image URI: $ECR_REGISTRY/$image_name:latest"
    else
        print_error "❌ Failed to build $image_name"
        exit 1
    fi
}

# Function to build all images
build_all() {
    check_prerequisites
    login_to_registries
    prepare_build_context
    
    local failed_images=()
    local successful_images=()
    
    for image_type in $(get_all_image_types); do
        local dockerfile="Dockerfile.$image_type"
        local image_name=$(get_image_name "$image_type")
        
        if [ ! -f "$dockerfile" ]; then
            print_warning "Skipping $image_type: $dockerfile not found"
            continue
        fi
        
        if build_and_push "$dockerfile" "$image_name" "latest"; then
            successful_images+=("$image_name")
        else
            failed_images+=("$image_name")
        fi
        
        echo "----------------------------------------"
    done
    
    # Summary
    echo
    print_header "Build Summary"
    
    if [ ${#successful_images[@]} -gt 0 ]; then
        print_status "✅ Successfully built and pushed:"
        for image in "${successful_images[@]}"; do
            echo "   - $ECR_REGISTRY/$image:latest"
        done
    fi
    
    if [ ${#failed_images[@]} -gt 0 ]; then
        print_error "❌ Failed to build:"
        for image in "${failed_images[@]}"; do
            echo "   - $image"
        done
        exit 1
    fi
    
    print_status "🎉 All images built and pushed successfully!"
    
    # Display image URIs for JupyterHub configuration
    echo
    print_header "Image URIs for JupyterHub Configuration"
    for image in "${successful_images[@]}"; do
        echo "$image: $ECR_REGISTRY/$image:latest"
    done
}

# Function to clean up local images
cleanup() {
    print_status "Cleaning up local Docker images..."
    
    for image_type in $(get_all_image_types); do
        local image_name=$(get_image_name "$image_type")
        docker rmi "$image_name:latest" 2>/dev/null || true
        docker rmi "$ECR_REGISTRY/$image_name:latest" 2>/dev/null || true
    done
    
    print_status "✅ Cleanup completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build [IMAGE_TYPE]  Build specific image or all images"
    echo "  clean              Remove local Docker images"
    echo "  help               Show this help message"
    echo ""
    echo "Image Types:"
    for image_type in $(get_all_image_types); do
        echo "  $image_type - $(get_image_name "$image_type")"
    done
    echo ""
    echo "Examples:"
    echo "  $0 build           # Build all images"
    echo "  $0 build unified   # Build only unified notebook image"
    echo "  $0 clean           # Clean up local images"
}

# Main execution
case "${1:-build}" in
    "build")
        if [ -n "$2" ]; then
            build_single "$2"
        else
            build_all
        fi
        ;;
    "clean")
        cleanup
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac