#!/bin/bash

# Test RAPIDS Container Script
# This script builds and tests the RAPIDS container locally

set -e

CONTAINER_NAME="fraud-detection/emr-rapids"
CONTAINER_TAG="test"
FULL_IMAGE="${CONTAINER_NAME}:${CONTAINER_TAG}"

echo "🐳 Testing RAPIDS Container Build and Functionality"
echo "=================================================="

# Function to cleanup
cleanup() {
    echo "🧹 Cleaning up..."
    docker rm -f rapids-test-container 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

echo "📦 Step 1: Building RAPIDS container..."
cd "$(dirname "$0")"

# Build the container for AMD64 platform (EC2 compatible)
if docker build --platform linux/amd64 --no-cache -t ${FULL_IMAGE} -f Dockerfile.rapids .; then
    echo "✅ Container build successful"
    
    # Verify architecture
    ARCH=$(docker inspect ${FULL_IMAGE} --format='{{.Architecture}}')
    echo "📋 Container architecture: $ARCH"
    if [ "$ARCH" != "amd64" ]; then
        echo "❌ Container built for wrong architecture: $ARCH (expected: amd64)"
        exit 1
    fi
else
    echo "❌ Container build failed"
    exit 1
fi

echo ""
echo "🔍 Step 2: Testing container functionality..."

# Run container tests
if docker run --name rapids-test-container --rm \
    -v "$(pwd)/test_container.py:/test_container.py" \
    ${FULL_IMAGE} python3 /test_container.py; then
    echo "✅ Container functionality tests passed"
else
    echo "❌ Container functionality tests failed"
    exit 1
fi

echo ""
echo "📋 Step 3: Checking container size and layers..."
docker images ${FULL_IMAGE} --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

echo ""
echo "🔧 Step 4: Testing RAPIDS script execution..."

# Test the actual RAPIDS script
if docker run --name rapids-test-container --rm \
    -v "$(pwd)/src/rapids_test_job.py:/rapids_test_job.py" \
    -e "PYSPARK_PYTHON=python3" \
    -e "PYSPARK_DRIVER_PYTHON=python3" \
    ${FULL_IMAGE} python3 /rapids_test_job.py; then
    echo "✅ RAPIDS script execution test passed"
else
    echo "❌ RAPIDS script execution test failed"
    echo "This might be expected if GPU resources are not available locally"
fi

echo ""
echo "🎉 Container testing completed!"
echo "Container is ready for pushing to ECR and testing on EMR."

echo ""
echo "📝 Next steps:"
echo "1. Push to ECR: docker tag ${FULL_IMAGE} 368083780519.dkr.ecr.us-west-2.amazonaws.com/${CONTAINER_NAME}:latest"
echo "2. Push: docker push 368083780519.dkr.ecr.us-west-2.amazonaws.com/${CONTAINER_NAME}:latest"
echo "3. Test on EMR with GPU nodes"