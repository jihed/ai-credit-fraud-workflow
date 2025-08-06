#!/bin/bash

# Wrapper script for Terraform validation
# This script delegates to the terraform directory

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 EMR to EKS Migration Platform Validation${NC}"
echo -e "${BLUE}Delegating to terraform directory...${NC}"

# Change to terraform directory and run validation
cd terraform
./terraform-validate.sh