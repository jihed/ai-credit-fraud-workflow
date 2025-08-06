#---------------------------------------------------------------
# Ray Cluster for Distributed ML Training
#---------------------------------------------------------------

# Namespace for Ray cluster
resource "kubernetes_namespace" "ray_system" {
  count = var.enable_ray_cluster ? 1 : 0
  
  metadata {
    name = "ray-system"
    labels = {
      name = "ray-system"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "ml_team_a" {
  metadata {
    name = "ml-team-a"
    labels = {
      name = "ml-team-a"
    }
  }

  depends_on = [module.eks]
}

# Ray Cluster Custom Resource
resource "kubernetes_manifest" "ray_cluster" {
  count = 0  # Temporarily disabled until Ray operator is ready
  
  manifest = {
    apiVersion = "ray.io/v1alpha1"
    kind       = "RayCluster"
    metadata = {
      name      = "fraud-detection-cluster"
      namespace = kubernetes_namespace.ml_team_a.metadata[0].name
    }
    spec = {
      rayVersion = "2.9.3"
      headGroupSpec = {
        replicas = 1
        rayStartParams = {
          "dashboard-host" = "0.0.0.0"
          "dashboard-port" = "8265"
        }
        template = {
          spec = {
            containers = [
              {
                name  = "ray-head"
                image = "rayproject/ray-ml:2.9.3-gpu"
                ports = [
                  {
                    containerPort = 6379
                    name          = "gcs"
                  },
                  {
                    containerPort = 8265
                    name          = "dashboard"
                  },
                  {
                    containerPort = 10001
                    name          = "client"
                  }
                ]
                resources = {
                  requests = {
                    cpu    = "2"
                    memory = "8Gi"
                  }
                  limits = {
                    cpu    = "4"
                    memory = "16Gi"
                  }
                }
              }
            ]
            nodeSelector = {
              "workload-type" = "cpu"
            }
          }
        }
      }
      workerGroupSpecs = [
        {
          replicas    = var.ray_cluster_workers
          minReplicas = 1
          maxReplicas = 4
          groupName   = "gpu-workers"
          rayStartParams = {}
          template = {
            spec = {
              containers = [
                {
                  name  = "ray-worker"
                  image = "rayproject/ray-ml:2.9.3-gpu"
                  resources = {
                    requests = {
                      cpu               = "4"
                      memory            = "16Gi"
                      "nvidia.com/gpu"  = "1"
                    }
                    limits = {
                      cpu               = "8"
                      memory            = "32Gi"
                      "nvidia.com/gpu"  = "1"
                    }
                  }
                }
              ]
              nodeSelector = {
                "workload-type" = "gpu"
              }
              tolerations = [
                {
                  key      = "nvidia.com/gpu"
                  operator = "Exists"
                  effect   = "NoSchedule"
                }
              ]
            }
          }
        }
      ]
    }
  }

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.ml_team_a
  ]
}

# Service for Ray head
resource "kubernetes_service" "ray_head" {
  count = 0  # Temporarily disabled until Ray operator is ready
  
  metadata {
    name      = "fraud-detection-cluster-head-svc"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
  }

  spec {
    selector = {
      "ray.io/cluster"    = "fraud-detection-cluster"
      "ray.io/node-type"  = "head"
    }

    port {
      name        = "client"
      port        = 10001
      target_port = 10001
    }

    port {
      name        = "dashboard"
      port        = 8265
      target_port = 8265
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_manifest.ray_cluster]
}

# ConfigMap for Ray cluster configuration
resource "kubernetes_config_map" "ray_config" {
  count = var.enable_ray_cluster ? 1 : 0
  
  metadata {
    name      = "ray-cluster-config"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
  }

  data = {
    "ray_config.yaml" = yamlencode({
      cluster_name = "fraud-detection-cluster"
      ray_version  = "2.9.3"
      gpu_enabled  = true
      worker_nodes = var.ray_cluster_workers
    })
  }

  depends_on = [kubernetes_namespace.ml_team_a]
}