# gen3-kro Multi-Account EKS Platform Image
# This image contains all tools for managing the gen3-kro infrastructure

FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set versions for consistency
ARG TERRAFORM_VERSION=1.5.7
ARG TERRAGRUNT_VERSION=0.55.1
ARG KUBECTL_VERSION=1.31.0
ARG HELM_VERSION=3.14.0
ARG YQ_VERSION=4.44.3
ARG NODE_VERSION=22.21.0

LABEL org.opencontainers.image.source="https://github.com/indiana-university/gen3-kro"
LABEL org.opencontainers.image.description="Multi-account EKS platform with Terragrunt, ArgoCD, KRO, and AWS ACK"
LABEL org.opencontainers.image.licenses="MIT"

# Persist Node.js version in the runtime environment
ENV NODE_VERSION=${NODE_VERSION}
ENV PATH=/usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-x64/bin:$PATH

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    jq \
    unzip \
    git \
    git-lfs \
    bash-completion \
    vim \
    less \
    groff \
    python3 \
    python3-pip \
    python3-yaml \
    tree \
    htop \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN curl -L "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install Terraform
RUN curl -L "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && chmod +x /usr/local/bin/terraform

# Install Terragrunt
RUN curl -L "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64" \
    -o /usr/local/bin/terragrunt \
    && chmod +x /usr/local/bin/terragrunt

# Install kubectl
RUN curl -L "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN curl -L "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && chmod +x /usr/local/bin/helm

# Install AWS CLI v2 (latest)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install k9s (Kubernetes CLI UI)
RUN curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz \
    | tar xz -C /tmp \
    && mv /tmp/k9s /usr/local/bin/k9s \
    && chmod +x /usr/local/bin/k9s

# Install ArgoCD CLI
RUN curl -sSL -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 \
    && chmod +x /usr/local/bin/argocd

# Install kustomize
RUN curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
    | bash \
    && mv kustomize /usr/local/bin/kustomize \
    && chmod +x /usr/local/bin/kustomize

# Install Python packages for YAML processing (using apt for Ubuntu 24.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

    # Install Node.js (LTS 22.21.0)
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    -o /tmp/node.tar.xz \
    && mkdir -p /usr/local/lib/nodejs \
    && tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs \
    && rm /tmp/node.tar.xz
# Create working directory
WORKDIR /workspace

# Copy project files
COPY . /workspace/

# Set up bash completion and aliases
RUN echo 'alias k=kubectl' >> /root/.bashrc \
    && echo 'alias tf=terraform' >> /root/.bashrc \
    && echo 'alias tg=terragrunt' >> /root/.bashrc \
    && echo 'export PS1="\[\033[01;32m\]\u@gen3-kro\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc

# Display versions
RUN echo "=== Installed Tools ===" && \
    echo "Terraform: $(terraform version | head -n1)" && \
    echo "Terragrunt: $(terragrunt --version)" && \
    echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)" && \
    echo "Helm: $(helm version --short)" && \
    echo "AWS CLI: $(aws --version)" && \
    echo "yq: $(yq --version)" && \
    echo "Node.js: $(node --version)" && \
    echo "npm: $(npm --version)" && \
    echo "======================="

# Default command
CMD ["/bin/bash"]
