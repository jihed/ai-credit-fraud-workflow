# Unified Development Environment (EMR Spark + Ray)
FROM rayproject/ray:2.8.0-py310

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    openjdk-11-jdk \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

# Install Spark
ENV SPARK_VERSION=3.5.0
ENV HADOOP_VERSION=3
RUN wget -q "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" \
    && tar xzf "spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" -C /opt/ \
    && rm "spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" \
    && ln -s "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}" /opt/spark

# Create jovyan user
RUN useradd -m -s /bin/bash jovyan && \
    chown -R jovyan:jovyan /home/jovyan

USER jovyan

# Install JupyterLab and extensions
RUN pip install --no-cache-dir \
    jupyterlab==4.2.* \
    notebook==7.2.* \
    ipywidgets==8.1.* \
    jupyterlab-git==0.50.*

# Install core data science packages
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

# Install Spark packages
RUN pip install --no-cache-dir \
    pyspark==3.5.* \
    delta-spark==3.2.*

# Install Ray ML packages
RUN pip install --no-cache-dir \
    "ray[train]"==2.8.* \
    "ray[tune]"==2.8.* \
    "ray[serve]"==2.8.* \
    "ray[data]"==2.8.* \
    ray-lightning==0.3.*

# Install RAPIDS (CPU version for compatibility)
RUN pip install --no-cache-dir \
    cudf-cu11==24.10.* \
    cuml-cu11==24.10.* \
    cugraph-cu11==24.10.* \
    cuspatial-cu11==24.10.* \
    cupy-cuda11x==13.3.*

# Install additional ML frameworks
RUN pip install --no-cache-dir \
    torch==2.4.* \
    torchvision==0.19.* \
    tensorflow==2.17.* \
    transformers==4.45.*

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV SPARK_HOME=/opt/spark
ENV PYSPARK_PYTHON=/opt/conda/bin/python
ENV PYSPARK_DRIVER_PYTHON=/opt/conda/bin/python
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH
ENV RAY_DISABLE_IMPORT_WARNING=1

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