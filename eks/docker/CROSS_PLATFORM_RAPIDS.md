# Cross-Platform Considerations for RAPIDS Docker Image

## Overview

The RAPIDS Docker image has been updated to support cross-platform builds while maintaining compatibility with EMR on EKS requirements.

## Platform Support

### Primary Platform: linux/amd64
- **Target**: EC2 instances with NVIDIA GPUs
- **Compatibility**: EMR on EKS clusters
- **GPU Support**: Full RAPIDS acceleration with CUDA

### Architecture Constraints

RAPIDS has specific requirements that limit cross-platform support:

1. **GPU Dependency**: RAPIDS requires NVIDIA GPUs with CUDA support
2. **CUDA Runtime**: Only available on x86_64/amd64 architecture
3. **EMR Compatibility**: EMR on EKS primarily runs on AMD64 EC2 instances

## Build Process

### Docker Buildx Support
The build script now supports Docker buildx for better cross-platform handling:

```bash
# Build with explicit platform targeting
docker buildx build --platform linux/amd64 -f Dockerfile.rapids -t rapids-image .
```

### Build Arguments
The Dockerfile now accepts build arguments for flexibility:

- `TARGETPLATFORM`: Target platform (default: linux/amd64)
- `EMR_RAPIDS_VERSION`: EMR RAPIDS base image version

## Validation

### Architecture Validation
The image includes runtime validation to ensure proper architecture:

```dockerfile
RUN echo "Building for architecture: $(uname -m)" && \
    if [ "$(uname -m)" != "x86_64" ]; then \
        echo "WARNING: RAPIDS is optimized for x86_64 architecture with NVIDIA GPUs"; \
    fi
```

### Health Check
A health check validates RAPIDS libraries are properly loaded:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import cudf, cuml; print('RAPIDS libraries loaded successfully')" || exit 1
```

## Usage

### Building the Image
```bash
# Standard build (AMD64)
./build-rapids-image.sh

# Validation only (no ECR push)
./build-rapids-image.sh validate-only
```

### Environment Variables
- `AWS_REGION`: Target AWS region (default: us-west-2)
- `IMAGE_TAG`: Docker image tag (default: latest)
- `VALIDATE_CONTAINER`: Enable validation (default: true)

## Limitations

1. **ARM64 Support**: Limited due to CUDA/GPU requirements
2. **Local Testing**: GPU functionality requires NVIDIA hardware
3. **Platform Lock-in**: Primarily designed for AMD64 EC2 instances

## Best Practices

1. **Explicit Platform**: Always specify `--platform linux/amd64` for builds
2. **Version Pinning**: Pin package versions for reproducibility
3. **Validation**: Run container validation before deployment
4. **GPU Testing**: Test GPU functionality on actual EMR clusters

## Troubleshooting

### Build Issues
- Ensure Docker buildx is available for cross-platform builds
- Verify base image availability for target platform
- Check CUDA compatibility requirements

### Runtime Issues
- Validate GPU availability on target nodes
- Check EMR cluster GPU configuration
- Verify RAPIDS library compatibility

## Future Considerations

- Monitor RAPIDS ARM64 support development
- Consider CPU-only fallback for development environments
- Evaluate multi-stage builds for better optimization