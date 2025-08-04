#!/bin/bash

# Performance tests runner
# Benchmarks GPU vs CPU performance across different workloads

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports/performance"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo -e "${BLUE}Running Performance Benchmarks...${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Reports: $REPORTS_DIR"
echo ""

# Set environment variables
export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
export TEST_REPORTS_DIR="$REPORTS_DIR"

# Configuration
export BENCHMARK_DATA_SIZES="10000,50000,100000"
export BENCHMARK_OUTPUT_DIR="$REPORTS_DIR"
export BENCHMARK_SAVE_DETAILED="true"

echo -e "${YELLOW}Configuration:${NC}"
echo "Data sizes: $BENCHMARK_DATA_SIZES"
echo "Output directory: $BENCHMARK_OUTPUT_DIR"
echo ""

# Run performance benchmarks
cd "$SCRIPT_DIR"
python3 performance/benchmark_gpu_vs_cpu.py

echo -e "${GREEN}✓ Performance benchmarks completed${NC}"
echo "Reports saved to: $REPORTS_DIR"
echo ""
echo "Generated files:"
ls -la "$REPORTS_DIR"