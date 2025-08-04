#!/bin/bash

# Load tests runner
# Tests inference service capacity and performance under load

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports/load"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo -e "${BLUE}Running Load Tests...${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Reports: $REPORTS_DIR"
echo ""

# Set environment variables
export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
export TEST_REPORTS_DIR="$REPORTS_DIR"

# Configuration (can be overridden by environment variables)
INFERENCE_SERVICE_URL=${INFERENCE_SERVICE_URL:-"http://localhost:8000"}
MAX_CONCURRENT_USERS=${MAX_CONCURRENT_USERS:-50}
TEST_DURATION=${TEST_DURATION:-300}
TARGET_RPS=${TARGET_RPS:-100}

echo -e "${YELLOW}Configuration:${NC}"
echo "Service URL: $INFERENCE_SERVICE_URL"
echo "Max concurrent users: $MAX_CONCURRENT_USERS"
echo "Test duration: ${TEST_DURATION}s"
echo "Target RPS: $TARGET_RPS"
echo ""

# Check if service is available (optional)
if command -v curl &> /dev/null; then
    echo "Checking service availability..."
    if curl -s --connect-timeout 5 "$INFERENCE_SERVICE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Service is reachable${NC}"
    else
        echo -e "${YELLOW}⚠ Service not reachable - tests will use mocked responses${NC}"
    fi
    echo ""
fi

# Export configuration for the test script
export INFERENCE_SERVICE_URL
export MAX_CONCURRENT_USERS
export TEST_DURATION
export TARGET_RPS

# Run load tests
cd "$SCRIPT_DIR"
python3 load/test_inference_capacity.py

echo -e "${GREEN}✓ Load tests completed${NC}"
echo "Reports saved to: $REPORTS_DIR"
echo ""
echo "Generated files:"
ls -la "$REPORTS_DIR"