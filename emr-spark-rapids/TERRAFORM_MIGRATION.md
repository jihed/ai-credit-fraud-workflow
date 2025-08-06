# Terraform Directory Migration

This document describes the reorganization of Terraform files into a dedicated directory structure.

## Changes Made

### Directory Structure
```
emr-spark-rapids/
├── terraform/                 # 🆕 All Terraform infrastructure code
│   ├── .terraform/           # Terraform state and provider cache
│   ├── helm-values/          # Moved from root
│   ├── k8s/                  # Moved from root
│   ├── *.tf                  # All Terraform configuration files
│   ├── terraform.tfvars      # Variable values
│   ├── terraform.tfstate*    # State files
│   ├── terraform-*.sh        # Management scripts
│   └── README.md             # Terraform-specific documentation
├── cost-optimization/        # Unchanged
├── fraud-detection/          # Unchanged
├── gitops/                   # Unchanged
├── monitoring/               # Unchanged
├── notebook-templates/       # Unchanged
├── ray-training/             # Unchanged
├── security/                 # Unchanged
├── upload-sample-data.sh     # Unchanged - data operations
├── test-upload.sh           # Unchanged - data operations
├── deploy.sh                # 🆕 Wrapper script
├── validate.sh              # 🆕 Wrapper script
├── cleanup.sh               # 🆕 Wrapper script
└── README.md                # Updated for new structure
```

### Files Moved to `terraform/`
- All `*.tf` files (infrastructure configuration)
- `terraform.tfvars` (configuration variables)
- `terraform.tfstate*` (state files)
- `.terraform/` and `.terraform.lock.hcl` (Terraform cache)
- `terraform-*.sh` scripts (management scripts)
- `helm-values/` directory (Helm configurations)
- `k8s/` directory (Kubernetes manifests)

### Files Remaining in Root
- Data operation scripts (`upload-sample-data.sh`, `test-upload.sh`)
- Component directories (`cost-optimization/`, `fraud-detection/`, etc.)
- Documentation files (`README.md`, `EXISTING_INFRASTRUCTURE.md`, etc.)

### New Wrapper Scripts
- `deploy.sh` - Delegates to `terraform/terraform-deploy.sh`
- `validate.sh` - Delegates to `terraform/terraform-validate.sh`
- `cleanup.sh` - Delegates to `terraform/terraform-cleanup.sh`

## Updated Usage

### Infrastructure Deployment
```bash
# Option 1: Use wrapper scripts (recommended)
./deploy.sh
./validate.sh

# Option 2: Direct terraform commands
cd terraform
./terraform-deploy.sh
./terraform-validate.sh
```

### Data Operations (unchanged)
```bash
# Upload sample data
./upload-sample-data.sh

# Test data upload
./test-upload.sh
```

### Configuration
Edit `terraform/terraform.tfvars` for infrastructure settings:
```hcl
name = "emr-spark-rapids"
region = "us-west-2"
enable_jupyterhub = true
# ... other settings
```

## Benefits of This Structure

### 1. **Separation of Concerns**
- **Infrastructure**: All Terraform code in dedicated directory
- **Data Operations**: Scripts remain in root for easy access
- **Components**: Feature-specific directories unchanged

### 2. **Better Organization**
- Clear distinction between infrastructure and application code
- Easier to navigate and understand project structure
- Terraform-specific documentation in dedicated location

### 3. **Improved Maintainability**
- Infrastructure changes isolated to terraform directory
- State files and configuration co-located
- Easier to manage Terraform versions and providers

### 4. **Team Collaboration**
- Clear ownership boundaries
- Easier to set up CI/CD pipelines
- Better Git workflow organization

## Migration Impact

### ✅ No Breaking Changes
- All functionality preserved
- Wrapper scripts maintain backward compatibility
- Data operations unchanged

### ✅ Enhanced Workflow
- Cleaner project structure
- Better documentation organization
- Easier onboarding for new team members

### ✅ Future-Proof
- Ready for advanced Terraform features (remote state, workspaces)
- Easier to implement GitOps workflows
- Better suited for enterprise environments

## Quick Start After Migration

1. **Deploy Infrastructure**:
   ```bash
   ./deploy.sh
   ```

2. **Upload Sample Data**:
   ```bash
   ./upload-sample-data.sh
   ```

3. **Validate Deployment**:
   ```bash
   ./validate.sh
   ```

4. **Access Services**:
   ```bash
   cd terraform
   terraform output quick_start_commands
   ```

## Troubleshooting

### Path Issues
If you encounter path-related errors:
1. Ensure you're in the correct directory
2. Use wrapper scripts from root directory
3. Use direct scripts from terraform directory

### State File Issues
State files are now in `terraform/` directory:
- `terraform/terraform.tfstate`
- `terraform/terraform.tfstate.backup`

### Configuration Issues
Configuration file is now at:
- `terraform/terraform.tfvars`

## Next Steps

1. **Test the new structure** with your existing deployment
2. **Update any CI/CD pipelines** to use new paths
3. **Consider implementing** remote state for production
4. **Explore advanced features** like Terraform workspaces

The migration maintains full backward compatibility while providing a cleaner, more maintainable structure for the EMR to EKS migration platform.