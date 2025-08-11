#!/bin/bash

# Build and Push RAPIDS-enabled EMR Docker Image with Validation
# This script builds a custom EMR image with RAPIDS support, validates it, and pushes to ECR

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

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
ECR_REPOSITORY="fraud-detection/emr-rapids"
IMAGE_TAG=${IMAGE_TAG:-latest}
DOCKERFILE="Dockerfile.rapids"
LOCAL_IMAGE_NAME="$ECR_REPOSITORY:$IMAGE_TAG"
VALIDATE_CONTAINER=${VALIDATE_CONTAINER:-true}

print_header "Custom EMR RAPIDS Image Builder (extends official EMR RAPIDS image)"
print_status "Base Image: public.ecr.aws/emr-on-eks/spark-rapids:emr-6.9.0-spark-rapids-latest"
print_status "AWS Region: $AWS_REGION"
print_status "ECR Repository: $ECR_REPOSITORY"
print_status "Image Tag: $IMAGE_TAG"
print_status "Dockerfile: $DOCKERFILE"
print_status "Container Validation: $VALIDATE_CONTAINER"

# Get AWS account ID
if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    print_error "Failed to get AWS account ID. Please check AWS CLI configuration."
    exit 1
fi

ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"
print_status "ECR URI: $ECR_URI"

# Function to cleanup on exit
cleanup() {
    print_status "Cleaning up test containers..."
    docker rm -f rapids-validation-container 2>/dev/null || true
    
    # Clean up buildx builder if we created it
    if docker buildx inspect rapids-builder > /dev/null 2>&1; then
        print_status "Cleaning up buildx builder..."
        docker buildx rm rapids-builder 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi

    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured. Please configure AWS credentials."
        exit 1
    fi

    # Check required files exist
    if [ ! -f "$DOCKERFILE" ]; then
        print_error "Dockerfile not found: $DOCKERFILE"
        exit 1
    fi

    if [ ! -f "test_container.py" ]; then
        print_error "Container validation script not found: test_container.py"
        print_error "Please ensure test_container.py exists in the current directory"
        exit 1
    fi

    if [ ! -f "src/rapids_test_job.py" ]; then
        print_error "RAPIDS test script not found: src/rapids_test_job.py"
        exit 1
    fi

    # Check Docker buildx availability for cross-platform builds
    if docker buildx version > /dev/null 2>&1; then
        print_status "✅ Docker buildx available for cross-platform builds"
    else
        print_warning "⚠️  Docker buildx not available - cross-platform builds limited"
        print_warning "Consider updating Docker to enable buildx for better cross-platform support"
    fi

    print_status "✅ All prerequisites met"
}

# Validate required configuration files
validate_config_files() {
    print_status "Validating configuration files..."
    
    # Check if spark-rapids-defaults.conf exists
    if [ ! -f "spark-rapids-defaults.conf" ]; then
        print_warning "spark-rapids-defaults.conf not found, creating default configuration..."
        cat > spark-rapids-defaults.conf << 'EOF'
# Spark RAPIDS Default Configuration
spark.plugins=com.nvidia.spark.SQLPlugin
spark.rapids.sql.enabled=true
spark.rapids.sql.python.gpu.enabled=true
spark.executor.resource.gpu.vendor=nvidia.com
spark.executor.resource.gpu.amount=1
spark.task.resource.gpu.amount=0.25
spark.rapids.memory.pinnedPool.size=2G
spark.rapids.memory.gpu.pool=ASYNC
spark.rapids.memory.gpu.allocFraction=0.6
spark.rapids.sql.concurrentGpuTasks=2
spark.sql.adaptive.enabled=true
spark.sql.adaptive.coalescePartitions.enabled=true
EOF
        print_status "✅ Created default spark-rapids-defaults.conf"
    fi
    
    print_status "✅ Configuration files validated"
}

# Create ECR repository if needed
setup_ecr_repository() {
    print_status "Setting up ECR repository..."
    
    if ! aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION > /dev/null 2>&1; then
        print_status "Creating ECR repository: $ECR_REPOSITORY"
        aws ecr create-repository \
            --repository-name $ECR_REPOSITORY \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        print_status "✅ Created ECR repository"
    else
        print_status "✅ ECR repository already exists"
    fi
}

# Build the Docker image with cross-platform support
build_image() {
    print_header "Building Docker Image with Cross-Platform Support"
    
    # Check if buildx is available for multi-platform builds
    if docker buildx version > /dev/null 2>&1; then
        print_status "Docker buildx detected - enabling cross-platform build support"
        
        # Create and use a new builder instance if it doesn't exist
        if ! docker buildx inspect rapids-builder > /dev/null 2>&1; then
            print_status "Creating new buildx builder instance..."
            docker buildx create --name rapids-builder --use
        else
            docker buildx use rapids-builder
        fi
        
        # Build for multiple platforms (primarily AMD64 for EC2, but ARM64 for future compatibility)
        print_status "Building $LOCAL_IMAGE_NAME from $DOCKERFILE for multiple platforms..."
        if docker buildx build \
            --platform linux/amd64 \
            --build-arg TARGETPLATFORM=linux/amd64 \
            --no-cache \
            -f $DOCKERFILE \
            -t $LOCAL_IMAGE_NAME \
            --load \
            .; then
            print_status "✅ Successfully built Docker image for AMD64 platform"
        else
            print_error "❌ Failed to build Docker image with buildx"
            exit 1
        fi
    else
        print_warning "Docker buildx not available, falling back to standard build"
        print_status "Building $LOCAL_IMAGE_NAME from $DOCKERFILE for AMD64/x86_64 (EC2 compatible)..."
        # Force AMD64 platform for EC2 compatibility, even when building on Apple Silicon
        if docker build --platform linux/amd64 --no-cache -f $DOCKERFILE -t $LOCAL_IMAGE_NAME .; then
            print_status "✅ Successfully built Docker image for AMD64 platform"
        else
            print_error "❌ Failed to build Docker image"
            exit 1
        fi
    fi
    
    # Verify the image architecture
    ARCH=$(docker inspect $LOCAL_IMAGE_NAME --format='{{.Architecture}}')
    print_status "Image architecture: $ARCH"
    if [ "$ARCH" != "amd64" ]; then
        print_error "❌ Image built for wrong architecture: $ARCH (expected: amd64)"
        exit 1
    fi
    
    # Show image details
    print_status "Image details:"
    docker images $LOCAL_IMAGE_NAME --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

# Validate container functionality
validate_container() {
    if [ "$VALIDATE_CONTAINER" != "true" ]; then
        print_warning "Container validation skipped (VALIDATE_CONTAINER=false)"
        return 0
    fi
    
    print_header "Validating Container Functionality"
    
    # Test 1: Basic container validation
    print_status "Running container validation tests..."
    if docker run --name rapids-validation-container --rm \
        -v "$(pwd)/test_container.py:/test_container.py" \
        $LOCAL_IMAGE_NAME python3 /test_container.py; then
        print_status "✅ Container validation tests passed"
    else
        print_error "❌ Container validation tests failed"
        print_error "Container has issues that need to be fixed before pushing to ECR"
        exit 1
    fi
    
    # Test 2: RAPIDS script execution test
    print_status "Testing RAPIDS script execution..."
    if docker run --name rapids-validation-container --rm \
        -v "$(pwd)/src/rapids_test_job.py:/rapids_test_job.py" \
        -e "PYSPARK_PYTHON=python3" \
        -e "PYSPARK_DRIVER_PYTHON=python3" \
        $LOCAL_IMAGE_NAME python3 /rapids_test_job.py; then
        print_status "✅ RAPIDS script execution test passed"
    else
        print_warning "⚠️  RAPIDS script execution test failed"
        print_warning "This might be expected if GPU resources are not available locally"
        print_warning "The container will still be pushed, but verify GPU functionality on EMR"
    fi
    
    print_status "✅ Container validation completed"
}

# Push image to ECR
push_to_ecr() {
    print_header "Pushing to ECR"
    
    # Login to ECR
    print_status "Logging in to ECR..."
    if aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com; then
        print_status "✅ Successfully logged in to ECR"
    else
        print_error "❌ Failed to login to ECR"
        exit 1
    fi

    # Tag the image for ECR
    print_status "Tagging image for ECR: $ECR_URI"
    docker tag $LOCAL_IMAGE_NAME $ECR_URI

    # Push to ECR
    print_status "Pushing image to ECR..."
    if docker push $ECR_URI; then
        print_status "✅ Successfully pushed image to ECR"
    else
        print_error "❌ Failed to push image to ECR"
        exit 1
    fi
}

# Display success information
show_success_info() {
    print_header "Build Completed Successfully!"
    
    echo ""
    print_status "📋 Image Details:"
    echo "   ECR URI: $ECR_URI"
    echo "   Repository: $ECR_REPOSITORY"
    echo "   Tag: $IMAGE_TAG"
    echo "   AWS Account: $AWS_ACCOUNT_ID"
    echo "   Region: $AWS_REGION"

    echo ""
    print_status "🔧 To use this image in EMR on EKS jobs:"
    echo "   spark.kubernetes.container.image: $ECR_URI"

    echo ""
    print_status "📝 Next steps:"
    echo "1. Update your EMR job templates to use this image"
    echo "2. Test RAPIDS functionality on EMR with GPU nodes"
    echo "3. Monitor job execution and GPU utilization"
    echo "4. Update Terraform configuration if needed"
    echo "5. Image is built for AMD64 platform (EC2 compatible)"
    
    echo ""
    print_status "🧪 Testing commands:"
    echo "   # Test locally:"
    echo "   docker run --rm $LOCAL_IMAGE_NAME python3 -c \"from pyspark.sql import SparkSession; print('Spark available')\""
    echo ""
    echo "   # Test on EMR:"
    echo "   python3 -c \"from emr_eks_utils import submit_rapids_test; submit_rapids_test('$ECR_URI')\""
}

# Main execution
main() {
    check_prerequisites
    validate_config_files
    setup_ecr_repository
    build_image
    validate_container
    push_to_ecr
    show_success_info
}

# Handle command line arguments
case "${1:-build}" in
    "build")
        main
        ;;
    "validate-only")
        check_prerequisites
        validate_config_files
        build_image
        validate_container
        print_status "✅ Validation completed. Use 'build' to push to ECR."
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  build          Build, validate, and push image to ECR (default)"
        echo "  validate-only  Build and validate image locally without pushing"
        echo "  help           Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  AWS_REGION           AWS region (default: us-west-2)"
        echo "  IMAGE_TAG            Docker image tag (default: latest)"
        echo "  VALIDATE_CONTAINER   Enable container validation (default: true)"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac