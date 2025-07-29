#---------------------------------------------------------------
# KubeRay Operator for distributed ML training
#---------------------------------------------------------------

resource "helm_release" "kuberay_operator" {
  name             = "kuberay-operator"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = "1.1.1"
  namespace        = "ray-system"
  create_namespace = true

  values = [
    <<-EOT
    image:
      repository: quay.io/kuberay/operator
      tag: v1.1.1
      pullPolicy: IfNotPresent

    nameOverride: ""
    fullnameOverride: ""

    # Operator configuration
    operator:
      env: []
      resources:
        limits:
          cpu: 100m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 512Mi

    # RBAC configuration
    rbac:
      create: true
      apiVersion: v1

    serviceAccount:
      create: true
      name: kuberay-operator

    # Security context
    securityContext:
      runAsNonRoot: true
      runAsUser: 65532

    # Node selector for operator placement
    nodeSelector:
      NodeGroupType: core

    # Tolerations for operator placement
    tolerations: []

    # Affinity for operator placement
    affinity: {}

    # Webhook configuration
    webhook:
      create: true
      port: 9443
    EOT
  ]

  depends_on = [
    module.eks,
    module.eks_blueprints_addons
  ]

  tags = local.tags
}

#---------------------------------------------------------------
# Ray Cluster for XGBoost distributed training
#---------------------------------------------------------------

resource "kubernetes_namespace" "ray_ml" {
  metadata {
    name = "ray-ml"
    labels = {
      name = "ray-ml"
    }
  }

  depends_on = [module.eks]
}

# Ray Cluster Custom Resource
resource "kubectl_manifest" "ray_cluster" {
  yaml_body = <<-YAML
    apiVersion: ray.io/v1alpha1
    kind: RayCluster
    metadata:
      name: fraud-training-cluster
      namespace: ray-ml
      labels:
        app: ray-cluster
        workload: fraud-detection
    spec:
      rayVersion: '2.8.0'
      enableInTreeAutoscaling: true
      autoscalerOptions:
        upscalingMode: Default
        idleTimeoutSeconds: 60
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "500m"
            memory: "512Mi"
      headGroupSpec:
        rayStartParams:
          dashboard-host: '0.0.0.0'
          dashboard-port: '8265'
          num-cpus: '0'
        template:
          metadata:
            labels:
              app: ray-head
              workload: fraud-detection
          spec:
            containers:
            - name: ray-head
              image: rayproject/ray-ml:2.8.0-gpu
              imagePullPolicy: IfNotPresent
              ports:
              - containerPort: 6379
                name: gcs-server
              - containerPort: 8265
                name: dashboard
              - containerPort: 10001
                name: client
              resources:
                limits:
                  cpu: "2"
                  memory: "8Gi"
                requests:
                  cpu: "2"
                  memory: "8Gi"
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              - name: RAY_GRAFANA_IFRAME_HOST
                value: http://localhost:3000
              - name: RAY_GRAFANA_HOST
                value: http://kube-prometheus-stack-grafana.kube-prometheus-stack.svc.cluster.local
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
            volumes:
            - name: ray-logs
              emptyDir: {}
            nodeSelector:
              NodeGroupType: core
            tolerations: []
      workerGroupSpecs:
      - replicas: 2
        minReplicas: 1
        maxReplicas: 10
        groupName: gpu-workers
        rayStartParams:
          num-cpus: '4'
          num-gpus: '1'
        template:
          metadata:
            labels:
              app: ray-worker
              workload: fraud-detection
              worker-type: gpu
          spec:
            containers:
            - name: ray-worker
              image: rayproject/ray-ml:2.8.0-gpu
              imagePullPolicy: IfNotPresent
              resources:
                limits:
                  cpu: "4"
                  memory: "16Gi"
                  nvidia.com/gpu: "1"
                requests:
                  cpu: "4"
                  memory: "16Gi"
                  nvidia.com/gpu: "1"
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              - name: CUDA_VISIBLE_DEVICES
                value: "0"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
              - mountPath: /dev/shm
                name: dshm
            volumes:
            - name: ray-logs
              emptyDir: {}
            - name: dshm
              emptyDir:
                medium: Memory
                sizeLimit: 1Gi
            nodeSelector:
              NodeGroupType: spark-executor-gpu-ca
            tolerations:
            - key: nvidia.com/gpu
              operator: Exists
              effect: NoSchedule
      - replicas: 2
        minReplicas: 0
        maxReplicas: 20
        groupName: cpu-workers
        rayStartParams:
          num-cpus: '4'
        template:
          metadata:
            labels:
              app: ray-worker
              workload: fraud-detection
              worker-type: cpu
          spec:
            containers:
            - name: ray-worker
              image: rayproject/ray-ml:2.8.0-gpu
              imagePullPolicy: IfNotPresent
              resources:
                limits:
                  cpu: "4"
                  memory: "16Gi"
                requests:
                  cpu: "4"
                  memory: "16Gi"
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
            volumes:
            - name: ray-logs
              emptyDir: {}
            nodeSelector:
              NodeGroupType: spark-driver-cpu-ca
            tolerations: []
  YAML

  depends_on = [
    helm_release.kuberay_operator,
    kubernetes_namespace.ray_ml
  ]
}

#---------------------------------------------------------------
# Ray Service for external access to dashboard
#---------------------------------------------------------------

resource "kubernetes_service" "ray_dashboard" {
  metadata {
    name      = "ray-dashboard"
    namespace = "ray-ml"
    labels = {
      app = "ray-dashboard"
    }
  }

  spec {
    selector = {
      app = "ray-head"
    }

    port {
      name        = "dashboard"
      port        = 8265
      target_port = 8265
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubectl_manifest.ray_cluster]
}

#---------------------------------------------------------------
# Ray Job for XGBoost training template
#---------------------------------------------------------------

resource "kubectl_manifest" "ray_job_template" {
  yaml_body = <<-YAML
    apiVersion: ray.io/v1alpha1
    kind: RayJob
    metadata:
      name: xgboost-training-template
      namespace: ray-ml
      labels:
        app: ray-job
        workload: fraud-detection
        job-type: training
    spec:
      entrypoint: python /app/train.py
      runtimeEnv: |
        pip:
          - xgboost==2.0.3
          - pandas==2.0.3
          - numpy==1.24.3
          - scikit-learn==1.3.0
          - boto3==1.34.0
          - s3fs==2023.12.0
        env_vars:
          RAY_DISABLE_IMPORT_WARNING: "1"
          PYTHONPATH: "/app"
      rayClusterSpec:
        rayVersion: '2.8.0'
        enableInTreeAutoscaling: true
        headGroupSpec:
          rayStartParams:
            dashboard-host: '0.0.0.0'
            dashboard-port: '8265'
            num-cpus: '0'
          template:
            metadata:
              labels:
                app: ray-head
                workload: fraud-detection
            spec:
              containers:
              - name: ray-head
                image: rayproject/ray-ml:2.8.0-gpu
                imagePullPolicy: IfNotPresent
                resources:
                  limits:
                    cpu: "2"
                    memory: "8Gi"
                  requests:
                    cpu: "2"
                    memory: "8Gi"
                env:
                - name: RAY_DISABLE_IMPORT_WARNING
                  value: "1"
                volumeMounts:
                - mountPath: /tmp/ray
                  name: ray-logs
              volumes:
              - name: ray-logs
                emptyDir: {}
              nodeSelector:
                NodeGroupType: core
        workerGroupSpecs:
        - replicas: 4
          minReplicas: 1
          maxReplicas: 10
          groupName: gpu-workers
          rayStartParams:
            num-cpus: '4'
            num-gpus: '1'
          template:
            metadata:
              labels:
                app: ray-worker
                workload: fraud-detection
                worker-type: gpu
            spec:
              containers:
              - name: ray-worker
                image: rayproject/ray-ml:2.8.0-gpu
                imagePullPolicy: IfNotPresent
                resources:
                  limits:
                    cpu: "4"
                    memory: "16Gi"
                    nvidia.com/gpu: "1"
                  requests:
                    cpu: "4"
                    memory: "16Gi"
                    nvidia.com/gpu: "1"
                env:
                - name: RAY_DISABLE_IMPORT_WARNING
                  value: "1"
                - name: CUDA_VISIBLE_DEVICES
                  value: "0"
                volumeMounts:
                - mountPath: /tmp/ray
                  name: ray-logs
                - mountPath: /dev/shm
                  name: dshm
              volumes:
              - name: ray-logs
                emptyDir: {}
              - name: dshm
                emptyDir:
                  medium: Memory
                  sizeLimit: 1Gi
              nodeSelector:
                NodeGroupType: spark-executor-gpu-ca
              tolerations:
              - key: nvidia.com/gpu
                operator: Exists
                effect: NoSchedule
      submitterPodTemplate:
        spec:
          restartPolicy: Never
          containers:
          - name: ray-job-submitter
            image: rayproject/ray-ml:2.8.0-gpu
            imagePullPolicy: IfNotPresent
            resources:
              limits:
                cpu: "1"
                memory: "2Gi"
              requests:
                cpu: "1"
                memory: "2Gi"
            env:
            - name: RAY_DISABLE_IMPORT_WARNING
              value: "1"
          nodeSelector:
            NodeGroupType: core
      shutdownAfterJobFinishes: true
      ttlSecondsAfterFinished: 3600
  YAML

  depends_on = [
    helm_release.kuberay_operator,
    kubernetes_namespace.ray_ml
  ]
}