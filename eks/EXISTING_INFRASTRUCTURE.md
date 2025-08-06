# Working with Existing Infrastructure

If you already have EKS infrastructure deployed, you can use these scripts to add the fraud detection platform components to your existing setup.

## 🔄 Quick Start with Existing Infrastructure

```bash
# 1. Import existing resources
./terraform-import.sh

# 2. Apply missing components
terraform apply

# 3. Validate everything
./terraform-validate.sh
```

## 📋 What the Import Script Does

The `terraform-import.sh` script will:

1. **Find your existing EKS cluster** automatically
2. **Configure kubectl** to connect to it
3. **Import existing resources** into Terraform state
4. **Update terraform.tfvars** with your cluster settings
5. **Show you what's missing** via `terraform plan`

## 🎯 Scenarios Supported

### Scenario 1: Existing EKS Cluster Only
If you have an EKS cluster but no ML platform components:

```bash
# Import and add ML components
./terraform-import.sh
terraform apply
```

### Scenario 2: Existing EKS with Some Components
If you have EKS with some components already deployed:

```bash
# Import what exists, add what's missing
./terraform-import.sh
terraform plan  # Review what will be added
terraform apply
```

### Scenario 3: Full Existing Setup
If you have everything but want to manage it with Terraform:

```bash
# Import everything into Terraform state
./terraform-import.sh
# Most resources should already exist
```

## 🔧 Manual Configuration

If the automatic import doesn't work, you can manually configure:

### 1. Set Your Cluster Name
Edit `terraform.tfvars`:

```hcl
name = "your-existing-cluster-name"
region = "your-aws-region"

# Enable only what you want to add
enable_jupyterhub = true
enable_ray_cluster = false  # if you already have this
enable_inference_service = true
```

### 2. Configure kubectl
```bash
aws eks update-kubeconfig --region your-region --name your-cluster-name
```

### 3. Run Terraform
```bash
terraform init
terraform plan  # See what will be created
terraform apply
```

## 🚨 Important Notes

### Before Running Scripts

1. **Backup your existing setup** (export configurations)
2. **Test in a non-production environment** first
3. **Review terraform plan** carefully before applying

### What Gets Preserved

- ✅ Your existing EKS cluster
- ✅ Existing node groups
- ✅ Existing applications
- ✅ Existing networking

### What Gets Added

- 🆕 JupyterHub (if enabled)
- 🆕 Ray cluster (if enabled)
- 🆕 Inference service (if enabled)
- 🆕 Monitoring dashboards (if enabled)
- 🆕 GPU monitoring (if enabled)
- 🆕 Cost monitoring (if enabled)

## 🔍 Validation

After importing and applying:

```bash
# Check everything is working
./terraform-validate.sh

# Check specific components
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
```

## 🧹 Rollback if Needed

If something goes wrong:

```bash
# Remove only the new components
terraform destroy -target=helm_release.jupyterhub
terraform destroy -target=kubernetes_manifest.ray_cluster

# Or remove everything Terraform manages
terraform destroy
```

## 💡 Tips

1. **Start Small**: Enable only one component at a time
2. **Test First**: Use a development cluster to test the process
3. **Monitor Resources**: Watch for any resource conflicts
4. **Keep Backups**: Export existing configurations before changes

## 🆘 Troubleshooting

### Import Script Issues
```bash
# If cluster not found automatically
./terraform-import.sh
# Then manually enter your cluster name when prompted
```

### Resource Conflicts
```bash
# Check what's already deployed
kubectl get all --all-namespaces

# Remove conflicting resources manually if needed
kubectl delete deployment conflicting-app -n namespace
```

### State Issues
```bash
# If Terraform state gets confused
terraform refresh
terraform plan
```

This approach lets you gradually adopt the fraud detection platform on your existing infrastructure!