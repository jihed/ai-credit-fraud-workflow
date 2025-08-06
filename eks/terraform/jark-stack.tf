#---------------------------------------------------------------
# JARK Stack Components (Deployed via Helm)
#---------------------------------------------------------------

#---------------------------------------------------------------
# JupyterHub Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  
  metadata {
    name = "jupyterhub"
    labels = {
      name = "jupyterhub"
    }
  }

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# JupyterHub Helm Release
#---------------------------------------------------------------
resource "helm_release" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  
  name       = "jupyterhub"
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  version    = "3.2.1"
  namespace  = kubernetes_namespace.jupyterhub[0].metadata[0].name

  values = [
    <<-EOT
      hub:
        config:
          JupyterHub:
            admin_access: true
            authenticator_class: dummy
          DummyAuthenticator:
            password: "fraud-detection-demo"
          Spawner:
            default_url: '/lab'
            cmd: ['jupyter-labhub']
        
        extraEnv:
          VIRTUAL_CLUSTER_ID:
            value: "${module.emr_containers.virtual_cluster_id}"
          EMR_EXECUTION_ROLE_ARN:
            value: "${module.emr_containers.iam_role_arn}"
          S3_BUCKET:
            value: "${module.s3_bucket.s3_bucket_id}"
          AWS_DEFAULT_REGION:
            value: "${local.region}"

      singleuser:
        profileList:
          - display_name: "EMR Spark + RAPIDS"
            description: "Feature engineering with GPU acceleration"
            default: true
            kubespawner_override:
              image: 'fraud-detection/emr-spark-rapids:latest'
              cpu_limit: 4
              mem_limit: '16G'
              cpu_guarantee: 2
              mem_guarantee: '8G'
              environment:
                VIRTUAL_CLUSTER_ID: "${module.emr_containers.virtual_cluster_id}"
                EMR_EXECUTION_ROLE_ARN: "${module.emr_containers.iam_role_arn}"
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"
                SPARK_DRIVER_MEMORY: '4g'
                SPARK_EXECUTOR_MEMORY: '8g'
              extra_resource_limits:
                nvidia.com/gpu: "0"
              
          - display_name: "Ray ML Training"
            description: "Distributed ML training and serving"
            kubespawner_override:
              image: 'fraud-detection/ray-ml:latest'
              cpu_limit: 8
              mem_limit: '32G'
              cpu_guarantee: 4
              mem_guarantee: '16G'
              environment:
                RAY_ADDRESS: 'ray://ray-cluster-head:10001'
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"
              extra_resource_limits:
                nvidia.com/gpu: "1"
              node_selector:
                provisioner: spark-gpu-rapids
              tolerations:
                - key: nvidia.com/gpu
                  operator: Exists
                  effect: NoSchedule
                  
          - display_name: "Unified Development"
            description: "Both EMR Spark and Ray capabilities"
            kubespawner_override:
              image: 'fraud-detection/unified-dev:latest'
              cpu_limit: 6
              mem_limit: '24G'
              cpu_guarantee: 3
              mem_guarantee: '12G'
              environment:
                VIRTUAL_CLUSTER_ID: "${module.emr_containers.virtual_cluster_id}"
                EMR_EXECUTION_ROLE_ARN: "${module.emr_containers.iam_role_arn}"
                RAY_ADDRESS: 'ray://ray-cluster-head:10001'
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"

        storage:
          type: 'dynamic'
          capacity: '10Gi'
          homeMountPath: '/home/jovyan'
          dynamic:
            storageClass: 'gp3'
            
        serviceAccountName: 'jupyterhub-user-sa'
        
        extraEnv:
          GRANT_SUDO: "yes"
          NOTEBOOK_ARGS: "--allow-root"

      rbac:
        create: true
        
      serviceAccount:
        create: true
    EOT
  ]

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.jupyterhub,
    aws_eks_pod_identity_association.jupyterhub,
    aws_eks_pod_identity_association.jupyterhub_user
  ]
}

#---------------------------------------------------------------
# Ray Operator Helm Release
#---------------------------------------------------------------
resource "helm_release" "kuberay_operator" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  name       = "kuberay-operator"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "kuberay-operator"
  version    = "1.2.2"
  namespace  = "kuberay-system"
  create_namespace = true

  values = [
    <<-EOT
      image:
        repository: kuberay/operator
        tag: v1.2.2
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 256Mi
    EOT
  ]

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Argo Workflows Helm Release
#---------------------------------------------------------------
resource "helm_release" "argo_workflows" {
  count = var.enable_argo_workflows ? 1 : 0
  
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = "0.45.1"
  namespace  = kubernetes_namespace.argo_workflows[0].metadata[0].name

  values = [
    <<-EOT
      controller:
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
      server:
        enabled: true
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
        serviceType: LoadBalancer
        serviceAnnotations:
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
          service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      executor:
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
    EOT
  ]

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.argo_workflows,
    aws_eks_pod_identity_association.argo_workflows
  ]
}#---------------------------------------------------------------
# JARK Stack Components (Deployed via Helm)
#---------------------------------------------------------------

#---------------------------------------------------------------
# JupyterHub Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  
  metadata {
    name = "jupyterhub"
    labels = {
      name = "jupyterhub"
    }
  }

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# JupyterHub Helm Release
#---------------------------------------------------------------
resource "helm_release" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  
  name       = "jupyterhub"
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  version    = "3.2.1"
  namespace  = kubernetes_namespace.jupyterhub[0].metadata[0].name

  values = [
    <<-EOT
      hub:
        config:
          JupyterHub:
            admin_access: true
            authenticator_class: dummy
          DummyAuthenticator:
            password: "fraud-detection-demo"
          Spawner:
            default_url: '/lab'
            cmd: ['jupyter-labhub']
        
        extraEnv:
          VIRTUAL_CLUSTER_ID:
            value: "${module.emr_containers.virtual_cluster_id}"
          EMR_EXECUTION_ROLE_ARN:
            value: "${module.emr_containers.iam_role_arn}"
          S3_BUCKET:
            value: "${module.s3_bucket.s3_bucket_id}"
          AWS_DEFAULT_REGION:
            value: "${local.region}"

      singleuser:
        profileList:
          - display_name: "EMR Spark + RAPIDS"
            description: "Feature engineering with GPU acceleration"
            default: true
            kubespawner_override:
              image: 'fraud-detection/emr-spark-rapids:latest'
              cpu_limit: 4
              mem_limit: '16G'
              cpu_guarantee: 2
              mem_guarantee: '8G'
              environment:
                VIRTUAL_CLUSTER_ID: "${module.emr_containers.virtual_cluster_id}"
                EMR_EXECUTION_ROLE_ARN: "${module.emr_containers.iam_role_arn}"
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"
                SPARK_DRIVER_MEMORY: '4g'
                SPARK_EXECUTOR_MEMORY: '8g'
              extra_resource_limits:
                nvidia.com/gpu: "0"
              
          - display_name: "Ray ML Training"
            description: "Distributed ML training and serving"
            kubespawner_override:
              image: 'fraud-detection/ray-ml:latest'
              cpu_limit: 8
              mem_limit: '32G'
              cpu_guarantee: 4
              mem_guarantee: '16G'
              environment:
                RAY_ADDRESS: 'ray://ray-cluster-head:10001'
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"
              extra_resource_limits:
                nvidia.com/gpu: "1"
              node_selector:
                provisioner: spark-gpu-rapids
              tolerations:
                - key: nvidia.com/gpu
                  operator: Exists
                  effect: NoSchedule
                  
          - display_name: "Unified Development"
            description: "Both EMR Spark and Ray capabilities"
            kubespawner_override:
              image: 'fraud-detection/unified-dev:latest'
              cpu_limit: 6
              mem_limit: '24G'
              cpu_guarantee: 3
              mem_guarantee: '12G'
              environment:
                VIRTUAL_CLUSTER_ID: "${module.emr_containers.virtual_cluster_id}"
                EMR_EXECUTION_ROLE_ARN: "${module.emr_containers.iam_role_arn}"
                RAY_ADDRESS: 'ray://ray-cluster-head:10001'
                S3_BUCKET: "${module.s3_bucket.s3_bucket_id}"

        storage:
          type: 'dynamic'
          capacity: '10Gi'
          homeMountPath: '/home/jovyan'
          dynamic:
            storageClass: 'gp3'
            
        serviceAccountName: 'jupyterhub-user-sa'
        
        extraEnv:
          GRANT_SUDO: "yes"
          NOTEBOOK_ARGS: "--allow-root"

      rbac:
        create: true
        
      serviceAccount:
        create: true
    EOT
  ]

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.jupyterhub,
    aws_eks_pod_identity_association.jupyterhub,
    aws_eks_pod_identity_association.jupyterhub_user
  ]
}

#---------------------------------------------------------------
# Ray Operator Helm Release
#---------------------------------------------------------------
resource "helm_release" "kuberay_operator" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  name       = "kuberay-operator"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "kuberay-operator"
  version    = "1.2.2"
  namespace  = "kuberay-system"
  create_namespace = true

  values = [
    <<-EOT
      image:
        repository: kuberay/operator
        tag: v1.2.2
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 256Mi
    EOT
  ]

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Argo Workflows Helm Release
#---------------------------------------------------------------
resource "helm_release" "argo_workflows" {
  count = var.enable_argo_workflows ? 1 : 0
  
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = "0.45.1"
  namespace  = kubernetes_namespace.argo_workflows[0].metadata[0].name

  values = [
    <<-EOT
      controller:
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
      server:
        enabled: true
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
        serviceType: LoadBalancer
        serviceAnnotations:
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
          service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      executor:
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
    EOT
  ]

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.argo_workflows,
    aws_eks_pod_identity_association.argo_workflows
  ]
}