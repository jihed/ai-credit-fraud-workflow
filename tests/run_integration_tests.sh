#!/bin/bash

# Integration tests runner
# Tests the complete data pipeline from ingestion to inference

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports/integration"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo -e "${BLUE}Running Integration Tests...${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Reports: $REPORTS_DIR"
echo ""

# Set environment variables
export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
export TEST_REPORTS_DIR="$REPORTS_DIR"

# Run integration tests with pytest
cd "$SCRIPT_DIR"
python3 -m pytest integration/test_complete_pipeline.py \
    -v \
    --tb=short \
    --junitxml="$REPORTS_DIR/junit_results_$TIMESTAMP.xml" \
    --html="$REPORTS_DIR/report_$TIMESTAMP.html" \
    --self-contained-html \
    --cov=integration \
    --cov-report=html:"$REPORTS_DIR/coverage_$TIMESTAMP" \
    --cov-report=term

echo -e "${GREEN}✓ Integration tests completed${NC}"
echo "Reports saved to: $REPORTS_DIR"