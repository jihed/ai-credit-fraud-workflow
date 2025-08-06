#!/bin/bash

# Build Docker images for JARK stack fraud detection notebooks
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Image configurations
declare -A IMAGES=(
    ["emr-spark-rapids"]="fraud-detection/emr-spark-rapids"
    ["ray-ml"]="fraud-detection/ray-ml"
    ["unified-dev"]="fraud-detection/unified-dev"
)

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    local repo_name=$1
    
    print_status "Checking ECR repository: $repo_name"
    
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Creating ECR repository: $repo_name"
        aws ecr create-repository \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
    else
        print_status "ECR repository $repo_name already exists"
    fi
}

# Function to build and push Docker image
build_and_push() {
    local dockerfile_dir=$1
    local image_name=$2
    local tag=${3:-latest}
    
    print_status "Building image: $image_name:$tag"
    
    # Build the image
    docker build -t "$image_name:$tag" "$dockerfile_dir"
    
    if [ $? -eq 0 ]; then
        print_status "Successfully built $image_name:$tag"
    else
        print_error "Failed to build $image_name:$tag"
        return 1
    fi
    
    # Tag for ECR
    local ecr_image="$ECR_REGISTRY/$image_name:$tag"
    docker tag "$image_name:$tag" "$ecr_image"
    
    # Push to ECR
    print_status "Pushing to ECR: $ecr_image"
    docker push "$ecr_image"
    
    if [ $? -eq 0 ]; then
        print_status "Successfully pushed $ecr_image"
    else
        print_error "Failed to push $ecr_image"
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting Docker image build process..."
    
    # Check prerequisites
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Login to ECR
    print_status "Logging in to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to login to ECR"
        exit 1
    fi
    
    # Build and push each image
    for dockerfile_dir in "${!IMAGES[@]}"; do
        image_name="${IMAGES[$dockerfile_dir]}"
        
        print_status "Processing $dockerfile_dir -> $image_name"
        
        # Create ECR repository
        create_ecr_repo "$image_name"
        
        # Copy notebooks to the build context
        if [ -d "notebooks" ]; then
            cp -r notebooks "$dockerfile_dir/"
        else
            mkdir -p "$dockerfile_dir/notebooks"
        fi
        
        # Create empty src directory if it doesn't exist
        mkdir -p "$dockerfile_dir/src"
        
        # Build and push
        if build_and_push "$dockerfile_dir" "$image_name" "latest"; then
            print_status "✅ Successfully processed $image_name"
        else
            print_error "❌ Failed to process $image_name"
            exit 1
        fi
        
        # Clean up copied files
        rm -rf "$dockerfile_dir/notebooks" "$dockerfile_dir/src"
    done
    
    print_status "🎉 All images built and pushed successfully!"
    
    # Display image URIs
    echo
    echo "=== Image URIs ==="
    for dockerfile_dir in "${!IMAGES[@]}"; do
        image_name="${IMAGES[$dockerfile_dir]}"
        echo "$image_name: $ECR_REGISTRY/$image_name:latest"
    done
    
    echo
    print_status "Update your Terraform configuration with these image URIs"
}

# Handle script arguments
case "${1:-}" in
    "clean")
        print_status "Cleaning up Docker images..."
        for dockerfile_dir in "${!IMAGES[@]}"; do
            image_name="${IMAGES[$dockerfile_dir]}"
            docker rmi "$image_name:latest" 2>/dev/null || true
            docker rmi "$ECR_REGISTRY/$image_name:latest" 2>/dev/null || true
        done
        print_status "Cleanup completed"
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [clean]"
        echo "  clean: Remove local Docker images"
        exit 1
        ;;
esac