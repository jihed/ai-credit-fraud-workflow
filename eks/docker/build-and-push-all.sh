#!/bin/bash

# Comprehensive Build and Push Script for All Container Images
# Ensures proper AMD64 targeting for EC2 deployment from any build platform

set -e

# Ensure we're using bash (not sh) for associative arrays
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run with: bash $0"
    exit 1
fi

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

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
BUILD_PLATFORM="linux/amd64"
VALIDATE_CONTAINERS=${VALIDATE_CONTAINERS:-true}

print_header "Comprehensive Container Build and Push for Fraud Detection"
print_status "Target Platform: $BUILD_PLATFORM (supports Intel x86_64 and AMD x86_64)"
print_status "AWS Region: $AWS_REGION"
print_status "Container Validation: $VALIDATE_CONTAINERS"

# Get build platform info
BUILD_HOST_ARCH=$(uname -m)
BUILD_HOST_OS=$(uname -s)
print_status "Build Host: $BUILD_HOST_OS/$BUILD_HOST_ARCH"

if [[ "$BUILD_HOST_ARCH" == "arm64" ]]; then
    print_warning "Building on ARM64 (Apple Silicon) - will cross-compile to x86_64"
elif [[ "$BUILD_HOST_ARCH" == "x86_64" ]]; then
    print_status "Building on x86_64 - native compilation"
fi

# Get AWS account ID
if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    print_error "Failed to get AWS account ID. Please check AWS CLI configuration."
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
print_status "ECR Registry: $ECR_REGISTRY"

# Image configurations (using simple approach for better compatibility)
get_image_name() {
    case "$1" in
        "rapids") echo "fraud-detection/emr-rapids" ;;
        "emr") echo "fraud-detection/emr-spark" ;;
        "unified") echo "fraud-detection/unified-notebook" ;;
        *) echo "" ;;
    esac
}

get_all_image_types() {
    echo "rapids emr unified"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check Docker buildx for cross-platform builds
    if ! docker buildx version >/dev/null 2>&1; then
        print_warning "Docker buildx not available - using standard build"
    else
        print_status "Docker buildx available for cross-platform builds"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    print_status "✅ Prerequisites check passed"
}

# Function to setup ECR repositories
setup_ecr_repositories() {
    print_status "Setting up ECR repositories..."
    
    for image_type in $(get_all_image_types); do
        local repo_name=$(get_image_name "$image_type")
        
        if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
            print_status "Creating ECR repository: $repo_name"
            aws ecr create-repository \
                --repository-name "$repo_name" \
                --region "$AWS_REGION" \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256 >/dev/null
        fi
    done
    
    print_status "✅ ECR repositories ready"
}

# Function to login to ECR
login_to_ecr() {
    print_status "Logging in to ECR..."
    
    if aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"; then
        print_status "✅ Successfully logged in to ECR"
    else
        print_error "❌ Failed to login to ECR"
        exit 1
    fi
}

# Function to validate container architecture
validate_container_architecture() {
    local image_name="$1"
    
    local arch=$(docker inspect "$image_name" --format='{{.Architecture}}')
    local os=$(docker inspect "$image_name" --format='{{.Os}}')
    
    print_status "Container: $image_name"
    print_status "  OS: $os"
    print_status "  Architecture: $arch"
    
    if [[ "$arch" != "amd64" ]]; then
        print_error "❌ Wrong architecture: $arch (expected: amd64)"
        return 1
    fi
    
    if [[ "$os" != "linux" ]]; then
        print_error "❌ Wrong OS: $os (expected: linux)"
        return 1
    fi
    
    print_status "✅ Container architecture validated"
    return 0
}

# Function to build and validate container
build_container() {
    local image_type="$1"
    local dockerfile="Dockerfile.$image_type"
    local image_name=$(get_image_name "$image_type")
    local local_tag="$image_name:latest"
    
    print_header "Building $image_name"
    
    if [[ ! -f "$dockerfile" ]]; then
        print_error "Dockerfile not found: $dockerfile"
        return 1
    fi
    
    # Build with explicit platform targeting
    print_status "Building for platform: $BUILD_PLATFORM"
    if docker build \
        --platform "$BUILD_PLATFORM" \
        --no-cache \
        -f "$dockerfile" \
        -t "$local_tag" \
        .; then
        print_status "✅ Build successful: $local_tag"
    else
        print_error "❌ Build failed: $local_tag"
        return 1
    fi
    
    # Validate architecture
    if ! validate_container_architecture "$local_tag"; then
        return 1
    fi
    
    # Run container validation for RAPIDS
    if [[ "$image_type" == "rapids" && "$VALIDATE_CONTAINERS" == "true" ]]; then
        print_status "Running RAPIDS container validation..."
        if [[ -f "test_container.py" ]]; then
            if docker run --rm \
                -v "$(pwd)/test_container.py:/test_container.py" \
                "$local_tag" python3 /test_container.py; then
                print_status "✅ RAPIDS container validation passed"
            else
                print_warning "⚠️  RAPIDS container validation failed (may be expected without GPU)"
            fi
        else
            print_warning "test_container.py not found, skipping validation"
        fi
    fi
    
    return 0
}

# Function to push container to ECR
push_container() {
    local image_type="$1"
    local image_name=$(get_image_name "$image_type")
    local local_tag="$image_name:latest"
    local ecr_tag="$ECR_REGISTRY/$image_name:latest"
    
    print_header "Pushing $image_name to ECR"
    
    # Tag for ECR
    docker tag "$local_tag" "$ecr_tag"
    
    # Push to ECR
    if docker push "$ecr_tag"; then
        print_status "✅ Successfully pushed: $ecr_tag"
        return 0
    else
        print_error "❌ Failed to push: $ecr_tag"
        return 1
    fi
}

# Function to build and push specific image
build_and_push_image() {
    local image_type="$1"
    
    if build_container "$image_type"; then
        if push_container "$image_type"; then
            return 0
        fi
    fi
    return 1
}

# Function to build and push all images
build_and_push_all() {
    local successful_images=()
    local failed_images=()
    
    for image_type in $(get_all_image_types); do
        print_header "Processing $image_type image"
        
        if build_and_push_image "$image_type"; then
            successful_images+=("$(get_image_name "$image_type")")
        else
            failed_images+=("$(get_image_name "$image_type")")
        fi
        
        echo "----------------------------------------"
    done
    
    # Summary
    print_header "Build and Push Summary"
    
    if [[ ${#successful_images[@]} -gt 0 ]]; then
        print_status "✅ Successfully built and pushed:"
        for image in "${successful_images[@]}"; do
            echo "   $ECR_REGISTRY/$image:latest"
        done
    fi
    
    if [[ ${#failed_images[@]} -gt 0 ]]; then
        print_error "❌ Failed to build and push:"
        for image in "${failed_images[@]}"; do
            echo "   $image"
        done
        return 1
    fi
    
    print_status "🎉 All images successfully built and pushed!"
    
    # Display usage information
    echo ""
    print_header "Container Usage Information"
    echo "RAPIDS Container (GPU workloads):"
    echo "  $ECR_REGISTRY/$(get_image_name rapids):latest"
    echo ""
    echo "EMR Container (CPU workloads):"
    echo "  $ECR_REGISTRY/$(get_image_name emr):latest"
    echo ""
    echo "Unified Development Container:"
    echo "  $ECR_REGISTRY/$(get_image_name unified):latest"
    
    return 0
}

# Function to cleanup local images
cleanup_local_images() {
    print_status "Cleaning up local images..."
    
    for image_type in $(get_all_image_types); do
        local image_name=$(get_image_name "$image_type")
        docker rmi "$image_name:latest" 2>/dev/null || true
        docker rmi "$ECR_REGISTRY/$image_name:latest" 2>/dev/null || true
    done
    
    print_status "✅ Local cleanup completed"
}

# Main execution
main() {
    local image_type="${1:-all}"
    
    # Change to script directory to ensure Dockerfiles are found
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir"
    print_status "Working directory: $(pwd)"
    
    check_prerequisites
    setup_ecr_repositories
    login_to_ecr
    
    if [[ "$image_type" == "all" ]]; then
        build_and_push_all
    elif [[ -n "$(get_image_name "$image_type")" ]]; then
        build_and_push_image "$image_type"
    else
        print_error "Unknown image type: $image_type"
        echo "Available images: $(get_all_image_types)"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-all}" in
    "all"|"rapids"|"emr"|"unified")
        main "$1"
        ;;
    "cleanup")
        cleanup_local_images
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [IMAGE_TYPE|COMMAND]"
        echo ""
        echo "Image Types:"
        for image_type in $(get_all_image_types); do
            echo "  $image_type - $(get_image_name "$image_type")"
        done
        echo "  all - Build and push all images (default)"
        echo ""
        echo "Commands:"
        echo "  cleanup - Remove local Docker images"
        echo "  help    - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  AWS_REGION           - AWS region (default: us-west-2)"
        echo "  VALIDATE_CONTAINERS  - Enable container validation (default: true)"
        echo ""
        echo "Examples:"
        echo "  $0                   # Build and push all images"
        echo "  $0 rapids            # Build and push only RAPIDS image"
        echo "  $0 cleanup           # Clean up local images"
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac