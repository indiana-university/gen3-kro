# gen3-kro Development Container
# Based on Ubuntu 24.04 with tools for Terraform, Kubernetes, AWS, and GitOps

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set versions for consistency
ARG TERRAFORM_VERSION=1.13.3
ARG TERRAGRUNT_VERSION=0.89.3
ARG KUBECTL_VERSION=1.34.1
ARG HELM_VERSION=3.16.1
ARG AWS_CLI_VERSION=2.15.17
ARG YQ_VERSION=4.44.3
ARG NODE_VERSION=25.0.0

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
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN curl -L "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install Terraform
RUN set -eux; \
    TF_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TF_ZIP}"; \
    echo "Downloading Terraform ${TERRAFORM_VERSION}..."; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/${TF_ZIP} "${TF_URL}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/terraform_SHA256SUMS "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    echo "Verifying download..."; \
    cd /tmp && grep " ${TF_ZIP}$" terraform_SHA256SUMS | sha256sum -c -; \
    echo "Installing Terraform..."; \
    unzip /tmp/${TF_ZIP} -d /usr/local/bin && \
    rm -f /tmp/${TF_ZIP} /tmp/terraform_SHA256SUMS && \
    chmod +x /usr/local/bin/terraform && \
    terraform version

# Install Terragrunt
RUN set -eux; \
    TG_BIN="terragrunt_linux_amd64"; \
    TG_URL_BASE="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}"; \
    echo "Downloading Terragrunt ${TERRAGRUNT_VERSION}..."; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/${TG_BIN} "${TG_URL_BASE}/${TG_BIN}"; \
    echo "Installing Terragrunt..."; \
    mv /tmp/${TG_BIN} /usr/local/bin/terragrunt && \
    chmod +x /usr/local/bin/terragrunt && \
    terragrunt --version

# Install kubectl
RUN echo "Downloading kubectl ${KUBECTL_VERSION}..."; \
    curl -fsSL --retry 3 --retry-delay 2 "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && kubectl version --client

# Install Helm
RUN echo "Downloading Helm ${HELM_VERSION}..."; \
    curl -fsSL --retry 3 --retry-delay 2 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/helm.tar.gz \
    && tar -xzf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
    && chmod +x /usr/local/bin/helm \
    && helm version

# Install AWS CLI v2
RUN echo "Downloading AWS CLI ${AWS_CLI_VERSION}..."; \
    curl -fsSL --retry 3 --retry-delay 2 "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" \
    -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && aws --version

# Install k9s (Kubernetes CLI UI)
RUN echo "Downloading k9s..."; \
    curl -fsSL --retry 3 --retry-delay 2 https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz \
    | tar xz -C /tmp \
    && mv /tmp/k9s /usr/local/bin/k9s \
    && chmod +x /usr/local/bin/k9s \
    && k9s version

# Install ArgoCD CLI
RUN echo "Downloading ArgoCD CLI..."; \
    curl -fsSL --retry 3 --retry-delay 2 -o /usr/local/bin/argocd \
    https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 \
    && chmod +x /usr/local/bin/argocd \
    && argocd version --client

# Install kustomize (release binary)
RUN echo "Downloading kustomize..."; \
    KUSTOMIZE_VERSION="5.7.1" && \
    curl -fsSL --retry 3 --retry-delay 2 "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C /tmp && mv /tmp/kustomize /usr/local/bin/kustomize && chmod +x /usr/local/bin/kustomize \
    && kustomize version


# Set up bash completion for kubectl and helm
RUN kubectl completion bash > /etc/bash_completion.d/kubectl \
    && helm completion bash > /etc/bash_completion.d/helm

# Install Node.js
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    -o /tmp/node.tar.xz \
    && mkdir -p /usr/local/lib/nodejs \
    && tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs \
    && rm /tmp/node.tar.xz

# Add Node.js to PATH
ENV PATH=/usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-x64/bin:$PATH

# Create workspace directory
RUN mkdir -p /workspaces

# Set permissions for vscode user
RUN chown -R vscode:vscode /workspaces

# Switch to vscode user
USER vscode

# Set working directory
WORKDIR /workspaces

# Add helpful aliases to .bashrc
RUN echo 'alias k=kubectl' >> /home/vscode/.bashrc \
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias tg=terragrunt' >> /home/vscode/.bashrc \
    && echo 'complete -F __start_kubectl k' >> /home/vscode/.bashrc \
    && echo 'export PS1="\[\033[01;32m\]\u@devcontainer\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/vscode/.bashrc

RUN echo '' >> /home/vscode/.bashrc \
    && echo '# Display installed tools on terminal start' >> /home/vscode/.bashrc \
    && echo 'echo "=== Installed Tools ==="' >> /home/vscode/.bashrc \
    && echo 'echo "Terraform: $(terraform version | head -n1)"' >> /home/vscode/.bashrc \
    && echo 'echo "Terragrunt: $(terragrunt --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1)"' >> /home/vscode/.bashrc \
    && echo 'echo "Helm: $(helm version --short)"' >> /home/vscode/.bashrc \
    && echo 'echo "AWS CLI: $(aws --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "yq: $(yq --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "Node.js: $(node --version) | npm: $(npm --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "======================="' >> /home/vscode/.bashrc \
    && echo 'echo ""' >> /home/vscode/.bashrc


# Reset to root for any final setup
USER root

# Set the default command
CMD ["/bin/bash"]
