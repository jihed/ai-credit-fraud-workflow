# EMR Spark + RAPIDS Notebook Image
FROM jupyter/pyspark-notebook:python-3.10

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

USER $NB_UID

# Install Python packages for fraud detection
RUN pip install --no-cache-dir \
    boto3==1.35.* \
    s3fs==2024.* \
    pandas==2.2.* \
    numpy==1.26.* \
    scikit-learn==1.5.* \
    xgboost==2.1.* \
    matplotlib==3.9.* \
    seaborn==0.13.* \
    plotly==5.24.* \
    jupyterlab==4.2.* \
    ipywidgets==8.1.*

# Install RAPIDS (CPU version for compatibility)
RUN pip install --no-cache-dir \
    cudf-cu11==24.10.* \
    cuml-cu11==24.10.* \
    cugraph-cu11==24.10.* \
    cuspatial-cu11==24.10.* \
    cupy-cuda11x==13.3.*

# Install EMR-specific packages
RUN pip install --no-cache-dir \
    pyspark==3.5.* \
    pyarrow==17.0.* \
    delta-spark==3.2.*

# Set environment variables
ENV PYSPARK_PYTHON=/opt/conda/bin/python
ENV PYSPARK_DRIVER_PYTHON=/opt/conda/bin/python
ENV SPARK_HOME=/usr/local/spark
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH

# Create directories for notebooks and data
RUN mkdir -p /home/jovyan/notebooks /home/jovyan/data /home/jovyan/models

# Copy sample notebooks (to be created)
COPY notebooks/ /home/jovyan/notebooks/
COPY src/ /home/jovyan/src/

# Set working directory
WORKDIR /home/jovyan

# Expose JupyterLab port
EXPOSE 8888

# Start JupyterLab
CMD ["start-notebook.py", "--NotebookApp.token=''", "--NotebookApp.password=''"]