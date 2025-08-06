#---------------------------------------------------------------
# Fraud Detection Inference Service
#---------------------------------------------------------------

# ConfigMap for inference service configuration
resource "kubernetes_config_map" "inference_config" {
  count = var.enable_inference_service ? 1 : 0
  
  metadata {
    name      = "fraud-inference-config"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
  }

  data = {
    "app.py" = <<-EOF
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pandas as pd
import numpy as np
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Fraud Detection API",
    description="GPU-accelerated fraud detection inference service",
    version="${var.fraud_detection_model_version}"
)

class PredictionRequest(BaseModel):
    avg_amount: float
    std_amount: float
    tx_count: int

class PredictionResponse(BaseModel):
    fraud_probability: float
    prediction: str
    confidence: float
    model_version: str

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "model_version": "${var.fraud_detection_model_version}",
        "service": "fraud-detection-inference"
    }

@app.post("/predict", response_model=PredictionResponse)
def predict_fraud(request: PredictionRequest):
    try:
        # Simplified fraud detection logic (replace with actual model)
        # In production, this would load an XGBoost model from S3
        features = np.array([request.avg_amount, request.std_amount, request.tx_count])
        
        # Normalize features (simplified)
        normalized_features = features / np.array([200.0, 100.0, 50.0])
        
        # Simple scoring logic (replace with actual model inference)
        score = np.clip(np.sum(normalized_features * [0.4, 0.3, 0.3]), 0, 1)
        
        # Add some randomness for demo purposes
        score = score * 0.7 + np.random.random() * 0.3
        
        prediction = "fraud" if score > 0.5 else "normal"
        confidence = abs(score - 0.5) * 2
        
        logger.info(f"Prediction: {prediction}, Score: {score:.4f}, Confidence: {confidence:.4f}")
        
        return PredictionResponse(
            fraud_probability=round(score, 4),
            prediction=prediction,
            confidence=round(confidence, 4),
            model_version="${var.fraud_detection_model_version}"
        )
        
    except Exception as e:
        logger.error(f"Prediction error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@app.get("/metrics")
def get_metrics():
    return {
        "requests_total": "fraud_detection_requests_total",
        "prediction_latency": "fraud_detection_prediction_duration_seconds",
        "model_version": "${var.fraud_detection_model_version}"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    "requirements.txt" = <<-EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pandas==2.1.4
numpy==1.24.3
scikit-learn==1.3.2
boto3==1.34.0
prometheus-client==0.19.0
EOF
  }

  depends_on = [kubernetes_namespace.ml_team_a]
}

# Deployment for inference service
resource "kubernetes_deployment" "fraud_inference" {
  count = var.enable_inference_service ? 1 : 0
  
  metadata {
    name      = "fraud-inference"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
    labels = {
      app     = "fraud-inference"
      version = var.fraud_detection_model_version
    }
  }

  spec {
    replicas = var.inference_service_replicas

    selector {
      match_labels = {
        app = "fraud-inference"
      }
    }

    template {
      metadata {
        labels = {
          app     = "fraud-inference"
          version = var.fraud_detection_model_version
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8000"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        container {
          name  = "fraud-inference"
          image = "python:3.11-slim"

          port {
            container_port = 8000
            name          = "http"
          }

          env {
            name  = "MODEL_S3_PATH"
            value = "s3://${module.s3_bucket.s3_bucket_id}/models/fraud-detection-model/"
          }

          env {
            name  = "AWS_DEFAULT_REGION"
            value = local.region
          }

          env {
            name  = "MODEL_VERSION"
            value = var.fraud_detection_model_version
          }

          command = ["/bin/bash", "-c"]
          args = [
            <<-EOF
            set -e
            echo "Installing dependencies..."
            pip install --no-cache-dir -r /app/requirements.txt
            echo "Starting fraud detection inference service..."
            cd /app && python app.py
            EOF
          ]

          volume_mount {
            name       = "app-config"
            mount_path = "/app"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "app-config"
          config_map {
            name = kubernetes_config_map.inference_config[0].metadata[0].name
          }
        }

        node_selector = {
          "workload-type" = "cpu"
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.inference_config]
}

# Service for inference API
resource "kubernetes_service" "fraud_inference" {
  count = var.enable_inference_service ? 1 : 0
  
  metadata {
    name      = "fraud-inference"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
    labels = {
      app = "fraud-inference"
    }
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }

  spec {
    selector = {
      app = "fraud-inference"
    }

    port {
      name        = "http"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.fraud_inference]
}

# Horizontal Pod Autoscaler
resource "kubernetes_horizontal_pod_autoscaler_v2" "fraud_inference_hpa" {
  count = var.enable_inference_service ? 1 : 0
  
  metadata {
    name      = "fraud-inference-hpa"
    namespace = kubernetes_namespace.ml_team_a.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "fraud-inference"
    }

    min_replicas = 2
    max_replicas = 10

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.fraud_inference]
}