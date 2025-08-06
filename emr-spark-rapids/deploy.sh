#!/bin/bash

# Wrapper script for Terraform deployment
# This script delegates to the terraform directory

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 EMR to EKS Migration Platform Deployment${NC}"
echo -e "${BLUE}Delegating to terraform directory...${NC}"

# Change to terraform directory and run deployment
cd terraform
./terraform-deploy.sh

echo -e "${GREEN}✅ Deployment completed!${NC}"
echo -e "${BLUE}💡 Next steps:${NC}"
echo "1. Upload sample data: ./upload-sample-data.sh"
echo "2. Validate deployment: cd terraform && ./terraform-validate.sh"
echo "3. Get access info: cd terraform && terraform output quick_start_commands"