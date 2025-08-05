#---------------------------------------------------------------
# Fraud Detection Monitoring Dashboards
#---------------------------------------------------------------

# ConfigMap for Grafana dashboard
resource "kubernetes_config_map" "fraud_detection_dashboard" {
  count = var.enable_monitoring_dashboards ? 1 : 0
  
  metadata {
    name      = "fraud-detection-dashboard"
    namespace = "prometheus"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "fraud-detection-dashboard.json" = jsonencode({
      dashboard = {
        id          = null
        title       = "Fraud Detection Pipeline"
        description = "GPU-accelerated fraud detection monitoring"
        tags        = ["fraud-detection", "ml", "gpu"]
        timezone    = "browser"
        panels = [
          {
            id    = 1
            title = "Inference Requests per Second"
            type  = "graph"
            targets = [
              {
                expr         = "rate(fraud_detection_requests_total[5m])"
                legendFormat = "Requests/sec"
              }
            ]
            yAxes = [
              {
                label = "Requests/sec"
                min   = 0
              }
            ]
            gridPos = {
              h = 8
              w = 12
              x = 0
              y = 0
            }
          },
          {
            id    = 2
            title = "Inference Latency (95th percentile)"
            type  = "graph"
            targets = [
              {
                expr         = "histogram_quantile(0.95, rate(fraud_detection_prediction_duration_seconds_bucket[5m]))"
                legendFormat = "95th percentile"
              }
            ]
            yAxes = [
              {
                label = "Seconds"
                min   = 0
              }
            ]
            gridPos = {
              h = 8
              w = 12
              x = 12
              y = 0
            }
          },
          {
            id    = 3
            title = "GPU Utilization"
            type  = "graph"
            targets = [
              {
                expr         = "nvidia_gpu_utilization"
                legendFormat = "GPU {{gpu}} on {{instance}}"
              }
            ]
            yAxes = [
              {
                label = "Percentage"
                min   = 0
                max   = 100
              }
            ]
            gridPos = {
              h = 8
              w = 12
              x = 0
              y = 8
            }
          },
          {
            id    = 4
            title = "GPU Memory Usage"
            type  = "graph"
            targets = [
              {
                expr         = "nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes * 100"
                legendFormat = "GPU {{gpu}} Memory %"
              }
            ]
            yAxes = [
              {
                label = "Percentage"
                min   = 0
                max   = 100
              }
            ]
            gridPos = {
              h = 8
              w = 12
              x = 12
              y = 8
            }
          },
          {
            id    = 5
            title = "Ray Cluster Status"
            type  = "stat"
            targets = [
              {
                expr         = "ray_cluster_active_nodes"
                legendFormat = "Active Nodes"
              }
            ]
            gridPos = {
              h = 4
              w = 6
              x = 0
              y = 16
            }
          },
          {
            id    = 6
            title = "Model Predictions"
            type  = "stat"
            targets = [
              {
                expr         = "increase(fraud_detection_requests_total[1h])"
                legendFormat = "Predictions/hour"
              }
            ]
            gridPos = {
              h = 4
              w = 6
              x = 6
              y = 16
            }
          },
          {
            id    = 7
            title = "Fraud Detection Rate"
            type  = "stat"
            targets = [
              {
                expr         = "rate(fraud_detection_fraud_predictions_total[5m]) / rate(fraud_detection_requests_total[5m]) * 100"
                legendFormat = "Fraud Rate %"
              }
            ]
            gridPos = {
              h = 4
              w = 6
              x = 12
              y = 16
            }
          },
          {
            id    = 8
            title = "Pod Resource Usage"
            type  = "graph"
            targets = [
              {
                expr         = "rate(container_cpu_usage_seconds_total{pod=~\"fraud-inference-.*\"}[5m])"
                legendFormat = "CPU Usage - {{pod}}"
              },
              {
                expr         = "container_memory_usage_bytes{pod=~\"fraud-inference-.*\"} / 1024 / 1024"
                legendFormat = "Memory Usage MB - {{pod}}"
              }
            ]
            gridPos = {
              h = 8
              w = 24
              x = 0
              y = 20
            }
          }
        ]
        time = {
          from = "now-1h"
          to   = "now"
        }
        refresh = "30s"
      }
    })
  }

  depends_on = [module.eks_blueprints_addons]
}

# PrometheusRule for fraud detection alerts
resource "kubernetes_manifest" "fraud_detection_alerts" {
  count = var.enable_monitoring_dashboards ? 1 : 0
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "fraud-detection-alerts"
      namespace = "prometheus"
      labels = {
        app = "fraud-detection"
      }
    }
    spec = {
      groups = [
        {
          name = "fraud-detection.rules"
          rules = [
            {
              alert = "HighInferenceLatency"
              expr  = "histogram_quantile(0.95, rate(fraud_detection_prediction_duration_seconds_bucket[5m])) > 0.5"
              for   = "2m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High inference latency detected"
                description = "95th percentile latency is {{ $value }}s"
              }
            },
            {
              alert = "GPUUtilizationLow"
              expr  = "avg(nvidia_gpu_utilization) < 20"
              for   = "10m"
              labels = {
                severity = "info"
              }
              annotations = {
                summary     = "GPU utilization is low"
                description = "Average GPU utilization is {{ $value }}%"
              }
            },
            {
              alert = "InferenceServiceDown"
              expr  = "up{job=\"fraud-inference\"} == 0"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Fraud inference service is down"
                description = "The fraud detection inference service is not responding"
              }
            },
            {
              alert = "HighFraudRate"
              expr  = "rate(fraud_detection_fraud_predictions_total[5m]) / rate(fraud_detection_requests_total[5m]) > 0.1"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High fraud detection rate"
                description = "Fraud detection rate is {{ $value | humanizePercentage }}"
              }
            },
            {
              alert = "RayClusterDown"
              expr  = "ray_cluster_active_nodes == 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Ray cluster is down"
                description = "No active Ray cluster nodes detected"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [module.eks_blueprints_addons]
}

# ServiceMonitor for fraud inference service
resource "kubernetes_manifest" "fraud_inference_service_monitor" {
  count = var.enable_monitoring_dashboards && var.enable_inference_service ? 1 : 0
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "fraud-inference-metrics"
      namespace = kubernetes_namespace.ml_team_a[0].metadata[0].name
      labels = {
        app = "fraud-inference"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "fraud-inference"
        }
      }
      endpoints = [
        {
          port     = "http"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [
    kubernetes_service.fraud_inference,
    module.eks_blueprints_addons
  ]
}

# ConfigMap for Ray cluster monitoring
resource "kubernetes_config_map" "ray_monitoring_config" {
  count = var.enable_monitoring_dashboards && var.enable_ray_cluster ? 1 : 0
  
  metadata {
    name      = "ray-monitoring-config"
    namespace = kubernetes_namespace.ml_team_a[0].metadata[0].name
  }

  data = {
    "ray_metrics.py" = <<-EOF
#!/usr/bin/env python3
"""
Ray cluster metrics collection script
"""
import ray
import time
import json
from prometheus_client import start_http_server, Gauge, Counter

# Prometheus metrics
ray_nodes_gauge = Gauge('ray_cluster_active_nodes', 'Number of active Ray nodes')
ray_cpu_gauge = Gauge('ray_cluster_cpu_usage', 'Ray cluster CPU usage')
ray_memory_gauge = Gauge('ray_cluster_memory_usage', 'Ray cluster memory usage')
ray_gpu_gauge = Gauge('ray_cluster_gpu_usage', 'Ray cluster GPU usage')

def collect_ray_metrics():
    """Collect Ray cluster metrics"""
    try:
        # Connect to Ray cluster
        ray.init(address="ray://fraud-detection-cluster-head-svc:10001", ignore_reinit_error=True)
        
        # Get cluster resources
        resources = ray.cluster_resources()
        
        # Update metrics
        ray_nodes_gauge.set(len(ray.nodes()))
        ray_cpu_gauge.set(resources.get('CPU', 0))
        ray_memory_gauge.set(resources.get('memory', 0))
        ray_gpu_gauge.set(resources.get('GPU', 0))
        
        print(f"Updated Ray metrics: nodes={len(ray.nodes())}, cpu={resources.get('CPU', 0)}")
        
    except Exception as e:
        print(f"Error collecting Ray metrics: {e}")

if __name__ == "__main__":
    # Start Prometheus metrics server
    start_http_server(8080)
    print("Ray metrics collector started on port 8080")
    
    # Collect metrics every 30 seconds
    while True:
        collect_ray_metrics()
        time.sleep(30)
EOF
  }

  depends_on = [kubernetes_namespace.ml_team_a]
}