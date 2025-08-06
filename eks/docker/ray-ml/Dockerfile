# Ray ML Training and Serving Notebook Image
FROM rayproject/ray:2.8.0-py310

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

# Create jovyan user (standard Jupyter user)
RUN useradd -m -s /bin/bash jovyan && \
    chown -R jovyan:jovyan /home/jovyan

USER jovyan

# Install JupyterLab and extensions
RUN pip install --no-cache-dir \
    jupyterlab==4.2.* \
    notebook==7.2.* \
    ipywidgets==8.1.* \
    jupyterlab-git==0.50.*

# Install ML and data science packages
RUN pip install --no-cache-dir \
    boto3==1.35.* \
    s3fs==2024.* \
    pandas==2.2.* \
    numpy==1.26.* \
    scikit-learn==1.5.* \
    xgboost==2.1.* \
    lightgbm==4.5.* \
    matplotlib==3.9.* \
    seaborn==0.13.* \
    plotly==5.24.* \
    pyarrow==17.0.*

# Install Ray ML packages
RUN pip install --no-cache-dir \
    "ray[train]"==2.8.* \
    "ray[tune]"==2.8.* \
    "ray[serve]"==2.8.* \
    "ray[data]"==2.8.* \
    ray-lightning==0.3.*

# Install additional ML frameworks
RUN pip install --no-cache-dir \
    torch==2.4.* \
    torchvision==0.19.* \
    tensorflow==2.17.* \
    transformers==4.45.*

# Set environment variables
ENV RAY_DISABLE_IMPORT_WARNING=1
ENV PYTHONPATH=/home/jovyan:$PYTHONPATH

# Create directories
RUN mkdir -p /home/jovyan/notebooks /home/jovyan/data /home/jovyan/models /home/jovyan/ray_results

# Copy sample notebooks and scripts
COPY notebooks/ /home/jovyan/notebooks/
COPY src/ /home/jovyan/src/

# Set working directory
WORKDIR /home/jovyan

# Expose JupyterLab port
EXPOSE 8888

# Start JupyterLab
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]