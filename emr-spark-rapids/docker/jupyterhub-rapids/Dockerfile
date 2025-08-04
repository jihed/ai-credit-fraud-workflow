# Custom JupyterHub image with RAPIDS, EMR, and Ray support
FROM jupyter/datascience-notebook:latest

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA CUDA toolkit (for GPU support)
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb && \
    dpkg -i cuda-keyring_1.0-1_all.deb && \
    apt-get update && \
    apt-get -y install cuda-toolkit-11-8 && \
    rm cuda-keyring_1.0-1_all.deb && \
    rm -rf /var/lib/apt/lists/*

# Set CUDA environment variables
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

USER $NB_UID

# Install Python packages for RAPIDS, EMR, and Ray
RUN pip install --no-cache-dir \
    # RAPIDS packages
    cudf-cu11 \
    cuml-cu11 \
    cugraph-cu11 \
    cuspatial-cu11 \
    # Ray and distributed computing
    ray[default,train,tune,serve] \
    xgboost-ray \
    # AWS and EMR integration
    boto3 \
    awscli \
    # Data processing and ML
    pandas \
    numpy \
    scikit-learn \
    xgboost \
    lightgbm \
    # Visualization
    matplotlib \
    seaborn \
    plotly \
    # Jupyter extensions
    jupyterlab-git \
    jupyterlab-s3-browser \
    # Additional utilities
    requests \
    joblib \
    tqdm

# Install JupyterLab extensions
RUN jupyter labextension install \
    @jupyter-widgets/jupyterlab-manager \
    @jupyterlab/git \
    jupyterlab-plotly

# Create directories for templates and shared data
RUN mkdir -p /opt/templates /home/jovyan/templates /shared

# Copy notebook templates
COPY notebook-templates/ /opt/templates/

# Set up environment variables for EMR and Ray connectivity
ENV PYTHONPATH=/home/jovyan/work:$PYTHONPATH
ENV RAY_DISABLE_IMPORT_WARNING=1

# Create startup script
RUN echo '#!/bin/bash\n\
# Initialize notebook environment\n\
echo "🚀 Initializing Fraud Detection Notebook Environment..."\n\
\n\
# Copy templates if they don'\''t exist\n\
if [ ! -f "/home/jovyan/templates/fraud-detection-pipeline.ipynb" ]; then\n\
    echo "📋 Copying notebook templates..."\n\
    cp -r /opt/templates/* /home/jovyan/templates/ 2>/dev/null || true\n\
fi\n\
\n\
# Create example configuration file\n\
cat > /home/jovyan/config.py << EOF\n\
# Fraud Detection Pipeline Configuration\n\
import os\n\
\n\
# EMR Configuration\n\
EMR_VIRTUAL_CLUSTER_ID = os.environ.get("EMR_VIRTUAL_CLUSTER_ID", "")\n\
EMR_EXECUTION_ROLE_ARN = os.environ.get("EMR_EXECUTION_ROLE_ARN", "")\n\
\n\
# Ray Configuration\n\
RAY_ADDRESS = os.environ.get("RAY_ADDRESS", "ray://ray-cluster-head-svc.ray-system.svc.cluster.local:10001")\n\
\n\
# AWS Configuration\n\
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-west-2")\n\
S3_BUCKET = os.environ.get("S3_BUCKET", "")\n\
\n\
print(f"Configuration loaded:")\n\
print(f"- EMR Virtual Cluster: {EMR_VIRTUAL_CLUSTER_ID}")\n\
print(f"- Ray Address: {RAY_ADDRESS}")\n\
print(f"- S3 Bucket: {S3_BUCKET}")\n\
print(f"- AWS Region: {AWS_REGION}")\n\
EOF\n\
\n\
echo "✅ Environment initialized successfully!"\n\
echo "📚 Available notebook templates:"\n\
ls -la /home/jovyan/templates/\n\
echo ""\n\
echo "🔗 Quick Links:"\n\
echo "- EMR Spark RAPIDS Example: templates/emr-spark-rapids-example.ipynb"\n\
echo "- Ray XGBoost Training: templates/ray-xgboost-training.ipynb"\n\
echo "- End-to-End Pipeline: templates/fraud-detection-pipeline.ipynb"\n\
' > /home/jovyan/startup.sh && chmod +x /home/jovyan/startup.sh

# Create a welcome notebook
RUN echo '{\n\
 "cells": [\n\
  {\n\
   "cell_type": "markdown",\n\
   "metadata": {},\n\
   "source": [\n\
    "# Welcome to Fraud Detection on EKS\\n",\n\
    "\\n",\n\
    "This JupyterHub environment is configured for GPU-accelerated fraud detection using:\\n",\n\
    "- **EMR on EKS** with RAPIDS for data processing\\n",\n\
    "- **Ray** for distributed ML training\\n",\n\
    "- **XGBoost** for fraud detection models\\n",\n\
    "\\n",\n\
    "## Available Templates\\n",\n\
    "\\n",\n\
    "1. **EMR Spark RAPIDS Example** (`templates/emr-spark-rapids-example.ipynb`)\\n",\n\
    "   - Submit GPU-accelerated Spark jobs to EMR on EKS\\n",\n\
    "   - Monitor job progress and view results\\n",\n\
    "\\n",\n\
    "2. **Ray XGBoost Training** (`templates/ray-xgboost-training.ipynb`)\\n",\n\
    "   - Distributed XGBoost training with GPU acceleration\\n",\n\
    "   - Model versioning and S3 storage\\n",\n\
    "\\n",\n\
    "3. **End-to-End Pipeline** (`templates/fraud-detection-pipeline.ipynb`)\\n",\n\
    "   - Complete fraud detection workflow\\n",\n\
    "   - Data processing → Training → Inference\\n",\n\
    "\\n",\n\
    "## Getting Started\\n",\n\
    "\\n",\n\
    "Run the cell below to load your configuration and check connectivity:\\n"\n\
   ]\n\
  },\n\
  {\n\
   "cell_type": "code",\n\
   "execution_count": null,\n\
   "metadata": {},\n\
   "outputs": [],\n\
   "source": [\n\
    "# Load configuration\\n",\n\
    "exec(open('\''config.py'\'').read())\\n",\n\
    "\\n",\n\
    "# Test imports\\n",\n\
    "try:\\n",\n\
    "    import cudf\\n",\n\
    "    print(\\"✅ RAPIDS cuDF available\\")\\n",\n\
    "except ImportError:\\n",\n\
    "    print(\\"❌ RAPIDS cuDF not available\\")\\n",\n\
    "\\n",\n\
    "try:\\n",\n\
    "    import ray\\n",\n\
    "    print(\\"✅ Ray available\\")\\n",\n\
    "except ImportError:\\n",\n\
    "    print(\\"❌ Ray not available\\")\\n",\n\
    "\\n",\n\
    "try:\\n",\n\
    "    import boto3\\n",\n\
    "    print(\\"✅ AWS SDK available\\")\\n",\n\
    "except ImportError:\\n",\n\
    "    print(\\"❌ AWS SDK not available\\")\\n",\n\
    "\\n",\n\
    "try:\\n",\n\
    "    import xgboost\\n",\n\
    "    print(\\"✅ XGBoost available\\")\\n",\n\
    "except ImportError:\\n",\n\
    "    print(\\"❌ XGBoost not available\\")\\n",\n\
    "\\n",\n\
    "print(\\"\\\\n🚀 Ready to start fraud detection on EKS!\\")"\n\
   ]\n\
  }\n\
 ],\n\
 "metadata": {\n\
  "kernelspec": {\n\
   "display_name": "Python 3",\n\
   "language": "python",\n\
   "name": "python3"\n\
  },\n\
  "language_info": {\n\
   "codemirror_mode": {\n\
    "name": "ipython",\n\
    "version": 3\n\
   },\n\
   "file_extension": ".py",\n\
   "mimetype": "text/x-python",\n\
   "name": "python",\n\
   "nbconvert_exporter": "python",\n\
   "pygments_lexer": "ipython3",\n\
   "version": "3.8.10"\n\
  }\n\
 },\n\
 "nbformat": 4,\n\
 "nbformat_minor": 4\n\
}' > /home/jovyan/Welcome.ipynb

# Set proper permissions
USER root
RUN chown -R $NB_UID:$NB_GID /home/jovyan/templates /home/jovyan/startup.sh /home/jovyan/Welcome.ipynb /home/jovyan/config.py
USER $NB_UID

# Set the default working directory
WORKDIR /home/jovyan

# Run startup script on container start
CMD ["sh", "-c", "/home/jovyan/startup.sh && start-notebook.sh"]