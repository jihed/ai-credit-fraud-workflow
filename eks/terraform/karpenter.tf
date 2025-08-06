#---------------------------------------------------------------
# Karpenter Node Access Entry
#---------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons with GPU Support
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "1.37.1"

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_karpenter_resources = true

  karpenter_resources_helm_config = {
    # CPU-optimized NodePool for Spark drivers and system components
    spark-cpu-optimized = {
      values = [
        <<-EOT
      name: spark-cpu-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
        userData: |
          #!/bin/bash
          /etc/eks/bootstrap.sh ${module.eks.cluster_name}
      nodePool:
        labels:
          - type: karpenter
          - provisioner: spark-cpu-optimized
          - NodeGroupType: SparkCPUOptimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c", "r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5", "c5d", "r5", "r5d"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }

    # GPU NodePool for RAPIDS workloads
    spark-gpu-rapids = {
      values = [
        <<-EOT
      name: spark-gpu-rapids
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
        userData: |
          #!/bin/bash
          /etc/eks/bootstrap.sh ${module.eks.cluster_name}
      nodePool:
        labels:
          - type: karpenter
          - provisioner: spark-gpu-rapids
          - NodeGroupType: SparkGPURapids
          - nvidia.com/gpu: "true"
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["g"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["g5", "g6"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["4xlarge", "8xlarge", "12xlarge"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["4"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        taints:
          - key: nvidia.com/gpu
            value: "true"
            effect: NoSchedule
        weight: 50
      EOT
      ]
    }

    # Memory-optimized NodePool for large datasets
    spark-memory-optimized = {
      values = [
        <<-EOT
      name: spark-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
        userData: |
          #!/bin/bash
          /etc/eks/bootstrap.sh ${module.eks.cluster_name}
      nodePool:
        labels:
          - type: karpenter
          - provisioner: spark-memory-optimized
          - NodeGroupType: SparkMemoryOptimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r5", "r5d", "r6i"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["8", "16", "32", "48"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["4"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
          expireAfter: 720h
        weight: 75
      EOT
      ]
    }
  }

  depends_on = [module.eks_blueprints_addons]
}