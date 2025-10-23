# Docker Setup Guide

This guide explains how to build and use the Gen3 KRO platform Docker development environment.

## Overview

The Gen3 KRO platform uses a Docker-based development environment that includes all necessary tools for infrastructure deployment and management. The container provides a consistent, reproducible environment across different systems.

## Prerequisites

- **Docker**: Version 20.10 or higher
  - Install: https://docs.docker.com/get-docker/
- **Docker Compose**: Version 2.0 or higher (included with Docker Desktop)
- **Git**: For cloning the repository
- **Sufficient disk space**: ~10GB for container and tools

## Container Components

The development container includes:

- **Terraform**: v1.5+ - Infrastructure as Code
- **Terragrunt**: v0.48+ - DRY Terraform wrapper
- **kubectl**: v1.28+ - Kubernetes CLI
- **AWS CLI**: v2.0+ - AWS command-line tool
- **Docker CLI**: For managing containers on host
- **Git**: Built from source with latest features
- **Helm**: Kubernetes package manager
- **argocd CLI**: ArgoCD command-line tool
- **yq/jq**: YAML/JSON processors

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/indiana-university/gen3-kro.git
cd gen3-kro
```

### 2. Build the Container

Using the provided script:

```bash
./scripts/docker-build-push.sh
```

Or manually:

```bash
docker build -t gen3-kro:latest .
```

### 3. Run the Container

With VS Code Dev Containers extension:

```bash
# Open in VS Code
code .

# Click "Reopen in Container" when prompted
```

Or manually:

```bash
docker run -it \
  -v $(pwd):/workspaces/gen3-kro \
  -v ~/.aws:/root/.aws:ro \
  -v ~/.kube:/root/.kube \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gen3-kro:latest \
  bash
```

## Dockerfile Structure

The Dockerfile uses Ubuntu 24.04 LTS as the base and is organized into logical sections:

### Base Image Selection

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
```

Uses Microsoft's Dev Container base image with useful development tools pre-installed.

### Package Installation

```dockerfile
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        build-essential curl wget unzip git ca-certificates \
        python3 python3-pip jq yq
```

Installs system packages and build tools.

### Tool Installation

1. **Terraform**:
   ```dockerfile
   RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
       && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin \
       && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
   ```

2. **Terragrunt**:
   ```dockerfile
   RUN wget https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64 \
       && chmod +x terragrunt_linux_amd64 \
       && mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
   ```

3. **kubectl**:
   ```dockerfile
   RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
       && chmod +x kubectl \
       && mv kubectl /usr/local/bin/
   ```

4. **AWS CLI**:
   ```dockerfile
   RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
       && unzip awscliv2.zip \
       && ./aws/install \
       && rm -rf awscliv2.zip aws/
   ```

## Volume Mounts

### Workspace Mount

```bash
-v $(pwd):/workspaces/gen3-kro
```

Mounts the repository into the container at `/workspaces/gen3-kro`. Changes are reflected on both host and container.

### AWS Credentials

```bash
-v ~/.aws:/root/.aws:ro
```

Mounts AWS credentials read-only. Keep credentials on host, accessible in container.

**Alternative**: Use AWS SSO or environment variables:

```bash
docker run -it \
  -e AWS_PROFILE=myprofile \
  -e AWS_REGION=us-east-1 \
  -v ~/.aws:/root/.aws:ro \
  gen3-kro:latest bash
```

### Kubernetes Config

```bash
-v ~/.kube:/root/.kube
```

Mounts kubeconfig for kubectl access to clusters.

### Docker Socket

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

Enables running Docker commands from within the container (Docker-in-Docker pattern).

**Note**: This grants the container significant host access. Only use in trusted environments.

## VS Code Dev Container

### Configuration

The repository includes `.devcontainer/devcontainer.json`:

```json
{
  "name": "Gen3 KRO Dev Container",
  "build": {
    "dockerfile": "../Dockerfile",
    "context": ".."
  },
  "mounts": [
    "source=${localEnv:HOME}/.aws,target=/root/.aws,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.kube,target=/root/.kube,type=bind,consistency=cached",
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "hashicorp.terraform",
        "ms-kubernetes-tools.vscode-kubernetes-tools",
        "redhat.vscode-yaml"
      ]
    }
  },
  "postCreateCommand": "terraform version && terragrunt --version && kubectl version --client"
}
```

### Using Dev Container

1. **Install VS Code Extensions**:
   - Remote - Containers
   - Docker

2. **Open Repository**:
   ```bash
   code /path/to/gen3-kro
   ```

3. **Reopen in Container**:
   - Press `F1`
   - Select "Remote-Containers: Reopen in Container"
   - Wait for build/start

4. **Verify**:
   ```bash
   terraform version
   terragrunt --version
   kubectl version --client
   ```

## Building for Different Architectures

### ARM64 (Apple Silicon)

```bash
docker build --platform linux/arm64 -t gen3-kro:arm64 .
```

### Multi-Platform Build

```bash
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t gen3-kro:latest \
  --push \
  .
```

## Custom Build with Build Args

### Specify Tool Versions

```bash
docker build \
  --build-arg TERRAFORM_VERSION=1.6.0 \
  --build-arg TERRAGRUNT_VERSION=0.50.0 \
  -t gen3-kro:custom \
  .
```

### Add Additional Tools

Create a custom Dockerfile:

```dockerfile
FROM gen3-kro:latest

# Install additional tools
RUN apt-get update && apt-get install -y \
    vim \
    tmux \
    htop

# Install Python packages
RUN pip3 install \
    boto3 \
    kubernetes \
    pyyaml
```

Build:

```bash
docker build -f Dockerfile.custom -t gen3-kro:custom .
```

## Docker Build Script

The `scripts/docker-build-push.sh` script automates the build process:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
IMAGE_NAME="${IMAGE_NAME:-gen3-kro}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"
BUILD_ARGS="${BUILD_ARGS:-}"

# Build image
echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build ${BUILD_ARGS} -t "${IMAGE_NAME}:${IMAGE_TAG}" .

# Optionally push to registry
if [ -n "$REGISTRY" ]; then
  FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
  echo "Tagging as ${FULL_IMAGE}..."
  docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${FULL_IMAGE}"

  echo "Pushing to registry..."
  docker push "${FULL_IMAGE}"
fi

echo "Build complete!"
```

### Usage Examples

**Basic build**:
```bash
./scripts/docker-build-push.sh
```

**Build with custom tag**:
```bash
IMAGE_TAG=v1.2.3 ./scripts/docker-build-push.sh
```

**Build and push to registry**:
```bash
REGISTRY=myregistry.azurecr.io \
IMAGE_TAG=v1.2.3 \
./scripts/docker-build-push.sh
```

**Build with custom Terraform version**:
```bash
BUILD_ARGS="--build-arg TERRAFORM_VERSION=1.6.0" \
./scripts/docker-build-push.sh
```

## Development Workflow

### 1. Start Container

```bash
# Using VS Code
code .
# Reopen in Container

# Or manually
docker run -it \
  -v $(pwd):/workspaces/gen3-kro \
  -v ~/.aws:/root/.aws:ro \
  -v ~/.kube:/root/.kube \
  gen3-kro:latest bash
```

### 2. Configure AWS

Inside container:

```bash
# Verify AWS access
aws sts get-caller-identity

# Configure if needed
aws configure --profile myprofile
```

### 3. Work with Infrastructure

```bash
cd /workspaces/gen3-kro/live/aws/us-east-1/gen3-kro-hub

# Initialize
terragrunt init

# Plan changes
terragrunt plan

# Apply changes
terragrunt apply
```

### 4. Access Kubernetes

```bash
# Update kubeconfig
aws eks update-kubeconfig --name gen3-kro-hub --region us-east-1

# Verify access
kubectl get nodes

# Check ArgoCD applications
kubectl get applications -n argocd
```

## Troubleshooting

### Container Won't Build

**Symptom**: Build fails with package installation errors

**Solution**:
```bash
# Clear Docker cache
docker builder prune -a

# Rebuild without cache
docker build --no-cache -t gen3-kro:latest .
```

### AWS Credentials Not Working

**Symptom**: `aws` commands fail with authentication errors

**Check**:
```bash
# Verify mount
docker inspect <container-id> | grep Mounts -A 20

# Check credentials inside container
ls -la ~/.aws/
cat ~/.aws/credentials
```

**Solution**: Ensure `.aws` directory is mounted and contains valid credentials

### kubectl Can't Connect to Cluster

**Symptom**: `kubectl` commands fail

**Check**:
```bash
# Verify kubeconfig
cat ~/.kube/config

# Test connection
kubectl cluster-info
```

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### Docker Socket Permission Denied

**Symptom**: Cannot run `docker` commands inside container

**Solution**:
```bash
# On host, check Docker socket permissions
ls -l /var/run/docker.sock

# Add user to docker group (if needed)
sudo usermod -aG docker $USER

# Restart Docker
sudo systemctl restart docker
```

## Best Practices

### 1. Use .dockerignore

Create `.dockerignore` to exclude unnecessary files:

```
.git
.terraform
.terragrunt-cache
node_modules
*.log
```

### 2. Layer Caching

Order Dockerfile commands from least to most frequently changed:

```dockerfile
# Rarely changes - layer cached
RUN apt-get update && apt-get install -y ...

# Occasionally changes - layer cached
RUN wget <tool> && install ...

# Frequently changes - not cached
COPY . /workspaces/gen3-kro
```

### 3. Security

- **Don't store credentials in image**
- **Use read-only mounts for sensitive data**
- **Scan images for vulnerabilities**:
  ```bash
  docker scan gen3-kro:latest
  ```

### 4. Cleanup

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune
```

## Advanced Topics

### Multi-Stage Builds

Reduce image size with multi-stage builds:

```dockerfile
# Build stage
FROM ubuntu:24.04 AS builder
RUN apt-get update && apt-get install -y build-essential
# ... build tools ...

# Runtime stage
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/
# ... only copy binaries, not build tools ...
```

### Docker Compose

For more complex setups, use `docker-compose.yml`:

```yaml
version: '3.8'
services:
  gen3-kro:
    build: .
    volumes:
      - .:/workspaces/gen3-kro
      - ~/.aws:/root/.aws:ro
      - ~/.kube:/root/.kube
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - AWS_PROFILE=default
      - AWS_REGION=us-east-1
    command: bash
```

Run:
```bash
docker-compose run gen3-kro
```

## See Also

- [Terragrunt Setup Guide](./setup-terragrunt.md)
- [Dockerfile](../Dockerfile)
- [.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json)
- [Docker Documentation](https://docs.docker.com/)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/remote/containers)
