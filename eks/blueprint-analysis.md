# Data-on-EKS Blueprint Analysis

## Latest Version Information
- **Latest Release**: v1.2.0 (Published: July 21, 2025)
- **Repository**: https://github.com/awslabs/data-on-eks
- **Blueprint Path**: `analytics/terraform/emr-eks-karpenter`

## EMR EKS Karpenter Blueprint Details

### Key Features
- **EKS Version**: 1.33 (latest supported)
- **EMR Version**: 7.9.0 (latest)
- **Karpenter Version**: 1.2.1
- **Base AMI**: Amazon Linux 2023 (AL2023)

### Pre-configured Add-ons
- **Karpenter**: Enabled with spot termination handling
- **AWS Load Balancer Controller**: Available via eks-blueprints-addons
- **EBS CSI Driver**: With GP3 encrypted storage class
- **AWS for FluentBit**: For logging
- **FSx for Lustre CSI Driver**: Optional (disabled by default)
- **Metrics Server**: Available via eks-blueprints-addons

### Pre-configured Karpenter NodePools
1. **spark-with-ebs**: C5 instances (4-36 CPU cores)
2. **spark-compute-optimized**: C5d instances with local storage
3. **spark-graviton-memory-optimized**: R6gd ARM64 instances
4. **spark-memory-optimized**: R5d instances

### GPU Support Requirements
- **Current State**: No GPU NodePools pre-configured
- **Required Addition**: G5/G6 GPU instances for RAPIDS
- **NVIDIA GPU Operator**: Not included in current blueprint

### Breaking Changes in v1.2.0
- Preparation for v2.0 with focus on data workloads only
- AI/ML blueprints being moved to separate AI-on-EKS repository
- No breaking changes affecting EMR EKS Karpenter blueprint

### Required Customizations for Fraud Detection
1. Add GPU NodePool configuration for G5/G6 instances
2. Enable NVIDIA GPU Operator add-on
3. Configure EMR virtual cluster with GPU support
4. Add Ray cluster support (not included in blueprint)

## Terraform Module Versions
- **EKS Module**: terraform-aws-modules/eks/aws ~> 20.33
- **EKS Blueprints Addons**: aws-ia/eks-blueprints-addons/aws ~> 1.20
- **EKS Data Addons**: aws-ia/eks-data-addons/aws 1.37.1
- **EMR Module**: terraform-aws-modules/emr/aws//modules/virtual-cluster 2.4.2

## Provider Requirements
- **Terraform**: >= 1.3.2
- **AWS Provider**: ~> 5.95
- **Helm Provider**: ~> 2.17
- **Kubernetes Provider**: >= 2.10
- **Kubectl Provider**: >= 1.14