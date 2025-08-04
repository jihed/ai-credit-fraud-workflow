#!/bin/bash

# Main test runner for the complete EMR to EKS migration testing suite
# Runs all test categories: integration, performance, load, and CI/CD

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create reports directory
mkdir -p "$REPORTS_DIR"/{integration,performance,load,ci-cd}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EMR to EKS Migration - Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Start time: $(date)"
echo "Reports directory: $REPORTS_DIR"
echo ""

# Function to run a test category
run_test_category() {
    local category=$1
    local description=$2
    local command=$3
    
    echo -e "${YELLOW}Running $description...${NC}"
    echo "Command: $command"
    echo ""
    
    if eval "$command"; then
        echo -e "${GREEN}✓ $description completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python 3 is required but not installed${NC}"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip3 &> /dev/null; then
        echo -e "${RED}pip3 is required but not installed${NC}"
        exit 1
    fi
    
    # Install test dependencies if requirements.txt exists
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        echo "Installing test dependencies..."
        pip3 install -r "$SCRIPT_DIR/requirements.txt" --quiet
    fi
    
    # Check kubectl (optional, for Kubernetes tests)
    if command -v kubectl &> /dev/null; then
        echo "kubectl found: $(kubectl version --client --short 2>/dev/null || echo 'version check failed')"
    else
        echo -e "${YELLOW}kubectl not found - Kubernetes tests will be mocked${NC}"
    fi
    
    # Check docker (optional, for container tests)
    if command -v docker &> /dev/null; then
        echo "Docker found: $(docker --version)"
    else
        echo -e "${YELLOW}Docker not found - container tests will be mocked${NC}"
    fi
    
    echo -e "${GREEN}✓ Prerequisites check completed${NC}"
    echo ""
}

# Function to generate summary report
generate_summary_report() {
    local summary_file="$REPORTS_DIR/test_summary_$TIMESTAMP.txt"
    
    echo "Generating summary report..."
    
    cat > "$summary_file" << EOF
EMR to EKS Migration - Test Suite Summary
=========================================
Execution Date: $(date)
Total Duration: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds

Test Categories:
EOF
    
    # Add results for each category
    if [ -f "$REPORTS_DIR/integration/test_results.json" ]; then
        echo "✓ Integration Tests: COMPLETED" >> "$summary_file"
    else
        echo "✗ Integration Tests: FAILED" >> "$summary_file"
    fi
    
    if [ -f "$REPORTS_DIR/performance/benchmark_results.json" ]; then
        echo "✓ Performance Tests: COMPLETED" >> "$summary_file"
    else
        echo "✗ Performance Tests: FAILED" >> "$summary_file"
    fi
    
    if [ -f "$REPORTS_DIR/load/load_test_results.json" ]; then
        echo "✓ Load Tests: COMPLETED" >> "$summary_file"
    else
        echo "✗ Load Tests: FAILED" >> "$summary_file"
    fi
    
    if [ -f "$REPORTS_DIR/ci-cd/cicd_test_results.json" ]; then
        echo "✓ CI/CD Tests: COMPLETED" >> "$summary_file"
    else
        echo "✗ CI/CD Tests: FAILED" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

Report Locations:
- Integration: $REPORTS_DIR/integration/
- Performance: $REPORTS_DIR/performance/
- Load Testing: $REPORTS_DIR/load/
- CI/CD Pipeline: $REPORTS_DIR/ci-cd/

For detailed results, check the individual report files in each category directory.
EOF
    
    echo "Summary report generated: $summary_file"
}

# Main execution
main() {
    local exit_code=0
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables for tests
    export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"
    export TEST_REPORTS_DIR="$REPORTS_DIR"
    export TEST_TIMESTAMP="$TIMESTAMP"
    
    # Run test categories
    echo -e "${BLUE}Starting test execution...${NC}"
    echo ""
    
    # 1. Integration Tests
    if run_test_category "integration" "Integration Tests" \
        "cd '$SCRIPT_DIR' && python3 -m pytest integration/test_complete_pipeline.py -v --tb=short --junitxml='$REPORTS_DIR/integration/junit_results.xml'"; then
        echo ""
    else
        exit_code=1
    fi
    
    # 2. Performance Tests
    if run_test_category "performance" "Performance Benchmarks" \
        "cd '$SCRIPT_DIR' && python3 performance/benchmark_gpu_vs_cpu.py"; then
        echo ""
    else
        exit_code=1
    fi
    
    # 3. Load Tests
    if run_test_category "load" "Load Testing" \
        "cd '$SCRIPT_DIR' && python3 load/test_inference_capacity.py"; then
        echo ""
    else
        exit_code=1
    fi
    
    # 4. CI/CD Pipeline Tests
    if run_test_category "ci-cd" "CI/CD Pipeline Tests" \
        "cd '$SCRIPT_DIR' && python3 ci-cd/test_pipeline.py"; then
        echo ""
    else
        exit_code=1
    fi
    
    # Generate summary report
    generate_summary_report
    
    # Final summary
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Suite Execution Complete${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "End time: $(date)"
    echo "Total duration: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
    echo "Reports location: $REPORTS_DIR"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ All test categories completed successfully${NC}"
    else
        echo -e "${RED}✗ Some test categories failed - check individual reports${NC}"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Review detailed reports in $REPORTS_DIR"
    echo "2. Address any failing tests"
    echo "3. Re-run specific test categories if needed:"
    echo "   - Integration: ./run_integration_tests.sh"
    echo "   - Performance: ./run_performance_tests.sh"
    echo "   - Load: ./run_load_tests.sh"
    echo "   - CI/CD: ./run_cicd_tests.sh"
    
    exit $exit_code
}

# Handle script interruption
trap 'echo -e "\n${RED}Test execution interrupted${NC}"; exit 130' INT TERM

# Run main function
main "$@"