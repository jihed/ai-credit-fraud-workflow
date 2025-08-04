#---------------------------------------------------------------
# Karpenter Cost Optimization Configuration
# Note: Karpenter is already enabled in addons.tf, this file provides
# additional cost optimization configurations for Karpenter
#---------------------------------------------------------------

# Additional Karpenter NodePool for cost-optimized workloads
resource "kubectl_manifest" "cost_optimized_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "cost-optimized-nodepool"
    }
    spec = {
      # Template for cost-optimized nodes
      template = {
        metadata = {
          labels = {
            "node-type" = "cost-optimized"
            "NodeGroupType" = "cost-optimized-karpenter"
          }
        }
        spec = {
          # Prioritize spot instances for maximum cost savings
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["m5", "m5a", "m5n", "m5ad", "m5dn", "c5", "c5a", "c5n", "c5ad", "c5d"]
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = ["large", "xlarge", "2xlarge", "4xlarge"]
            }
          ]
          
          # Node class reference
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "cost-optimized-nodeclass"
          }
          
          # Taints for cost-optimized workloads
          taints = [
            {
              key    = "cost-optimized"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
        }
      }
      
      # Disruption settings for cost optimization
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "30s"
        expireAfter         = "2160h" # 90 days
      }
      
      # Resource limits
      limits = {
        cpu = 1000
      }
      
      # Weight for scheduling preference
      weight = 10
    }
  })

  depends_on = [module.eks_blueprints_addons]
}

# EC2NodeClass for cost-optimized nodes
resource "kubectl_manifest" "cost_optimized_nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "cost-optimized-nodeclass"
    }
    spec = {
      # AMI selection
      amiFamily = "AL2"
      
      # Subnet selection (use existing private subnets)
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.name
          }
        }
      ]
      
      # Security group selection
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.name
          }
        }
      ]
      
      # Instance store policy for cost optimization
      instanceStorePolicy = "RAID0"
      
      # User data for cost optimization
      userData = base64encode(<<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${module.eks.cluster_name}
        
        # Enable cost optimization features
        echo 'vm.swappiness=1' >> /etc/sysctl.conf
        echo 'net.core.somaxconn=65535' >> /etc/sysctl.conf
        sysctl -p
        
        # Configure log rotation for cost optimization
        cat > /etc/logrotate.d/docker-containers << 'EOF'
        /var/lib/docker/containers/*/*.log {
          rotate 5
          daily
          compress
          size=10M
          missingok
          delaycompress
          copytruncate
        }
        EOF
      EOT
      )
      
      # Tags for cost tracking
      tags = merge(local.tags, {
        "cost-center" = "ml-workloads"
        "node-type"   = "cost-optimized"
      })
    }
  })

  depends_on = [module.eks_blueprints_addons]
}

# Spot instance termination handler for graceful handling
resource "helm_release" "aws_node_termination_handler" {
  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  version    = "0.24.0"
  namespace  = "kube-system"

  values = [
    yamlencode({
      # Use IMDS mode for spot instance termination detection
      enableSpotInterruptionDraining    = true
      enableRebalanceMonitoring         = true
      enableScheduledEventDraining      = true
      enableRebalanceDraining           = true
      
      # Webhook configuration for SQS mode (optional)
      enableSqsTerminationDraining = false
      
      # Node selector for all nodes
      nodeSelector = {}
      
      # Tolerations to run on all nodes including GPU nodes
      tolerations = [
        {
          operator = "Exists"
        }
      ]
      
      # DaemonSet configuration
      daemonsetTolerations = [
        {
          operator = "Exists"
        }
      ]
      
      # Resource configuration
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
      
      # Logging configuration
      logLevel = "info"
      
      # Metrics
      enablePrometheusServer = true
      prometheusServerPort   = 9092
      
      # Service monitor
      serviceMonitor = {
        create = true
      }
    })
  ]

  depends_on = [module.eks_blueprints_addons]
}