#!/bin/bash

# Wrapper script for Terraform cleanup
# This script delegates to the terraform directory

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}🧹 EMR to EKS Migration Platform Cleanup${NC}"
echo -e "${YELLOW}⚠️  This will destroy all infrastructure resources!${NC}"
echo -e "${BLUE}Delegating to terraform directory...${NC}"

# Change to terraform directory and run cleanup
cd terraform
./terraform-cleanup.sh