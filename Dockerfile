# gen3-kro Development Container
# Ubuntu 24.04 with tools for Terraform, Kubernetes, AWS, GitOps, and MCP runtimes

# UV_VERSION must be defined before the first FROM when used in COPY --from below.
ARG UV_VERSION=0.10.2

# Pull uv/uvx binaries in a separate stage to avoid ARG expansion in --from.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uvbin

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Set versions for consistency
ARG TERRAFORM_VERSION=1.13.5
ARG TERRAGRUNT_VERSION=0.99.1
ARG KUBECTL_VERSION=1.35.1
ARG HELM_VERSION=3.16.1
ARG AWS_CLI_VERSION=2.32.0
ARG YQ_VERSION=4.44.3

# Base dependencies (includes Node/NPM for npx + Python for uvx-based tools).
# Includes sandbox binaries used by AI terminal runners in local/container mode.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    jq \
    unzip \
    git \
    git-lfs \
    bubblewrap \
    uidmap \
    socat \
    tini \
    bash-completion \
    vim \
    less \
    groff \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Sanity check: Context7 requires Node >= 18 (Ubuntu 24.04 apt usually provides 18.x).
RUN node --version && npm --version && npx --version && bwrap --version && socat -V | head -n1

# Install yq (YAML processor)
RUN curl -fsSL --retry 3 --retry-delay 2 \
    -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# Install uv + uvx (reliable container method)
# Uses the distroless image that contains only /uv and /uvx. :contentReference[oaicite:1]{index=1}
COPY --from=uvbin /uv /uvx /usr/local/bin/
RUN chmod +x /usr/local/bin/uv /usr/local/bin/uvx \
    && uv --version \
    && uvx --version

# Install Terraform (with checksum verification)
RUN set -eux; \
    TF_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TF_ZIP}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/${TF_ZIP} "${TF_URL}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/terraform_SHA256SUMS \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    cd /tmp && grep " ${TF_ZIP}$" terraform_SHA256SUMS | sha256sum -c -; \
    unzip /tmp/${TF_ZIP} -d /usr/local/bin; \
    rm -f /tmp/${TF_ZIP} /tmp/terraform_SHA256SUMS; \
    chmod +x /usr/local/bin/terraform; \
    terraform version

# Install Terragrunt
RUN set -eux; \
    TG_BIN="terragrunt_linux_amd64"; \
    TG_URL="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/${TG_BIN}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o /usr/local/bin/terragrunt "${TG_URL}"; \
    chmod +x /usr/local/bin/terragrunt; \
    terragrunt --version

# Install kubectl
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 2 \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl; \
    chmod +x /usr/local/bin/kubectl; \
    kubectl version --client

# Install Helm
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 2 \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
      -o /tmp/helm.tar.gz; \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64; \
    chmod +x /usr/local/bin/helm; \
    helm version

# Install AWS CLI v2 (pinned)
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 2 \
      "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" \
      -o /tmp/awscliv2.zip; \
    unzip /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update; \
    rm -rf /tmp/awscliv2.zip /tmp/aws; \
    aws --version

# Install k9s (Kubernetes CLI UI) - only once (removed duplicate)
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 2 \
      "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz" \
      | tar xz -C /tmp; \
    mv /tmp/k9s /usr/local/bin/k9s; \
    chmod +x /usr/local/bin/k9s; \
    k9s version

# Install ArgoCD CLI
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 2 \
      -o /usr/local/bin/argocd \
      "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"; \
    chmod +x /usr/local/bin/argocd; \
    argocd version --client

# Install kustomize (release binary)
RUN set -eux; \
    KUSTOMIZE_VERSION="5.7.1"; \
    curl -fsSL --retry 3 --retry-delay 2 \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
      | tar xz -C /tmp; \
    mv /tmp/kustomize /usr/local/bin/kustomize; \
    chmod +x /usr/local/bin/kustomize; \
    kustomize version

# Bash completion for kubectl and helm
RUN kubectl completion bash > /etc/bash_completion.d/kubectl \
    && helm completion bash > /etc/bash_completion.d/helm

# Workspace directory
RUN mkdir -p /workspaces && chown -R vscode:vscode /workspaces

# Use tini as PID 1 so foreground processes receive signals correctly.
ENTRYPOINT ["/usr/bin/tini", "--"]

# Use vscode user by default (important for devcontainers)
USER vscode
WORKDIR /workspaces

# Aliases and startup banner
RUN echo 'alias k=kubectl' >> /home/vscode/.bashrc \
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias tg=terragrunt' >> /home/vscode/.bashrc \
    && echo 'complete -F __start_kubectl k' >> /home/vscode/.bashrc \
    && echo 'export PS1="\[\033[01;32m\]\u@devcontainer\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/vscode/.bashrc \
    && echo '' >> /home/vscode/.bashrc \
    && echo '# Display installed tools on terminal start' >> /home/vscode/.bashrc \
    && echo 'echo "=== Installed Tools ==="' >> /home/vscode/.bashrc \
    && echo 'echo "Terraform: $(terraform version | head -n1)"' >> /home/vscode/.bashrc \
    && echo 'echo "Terragrunt: $(terragrunt --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1)"' >> /home/vscode/.bashrc \
    && echo 'echo "Helm: $(helm version --short)"' >> /home/vscode/.bashrc \
    && echo 'echo "AWS CLI: $(aws --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "yq: $(yq --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "uv: $(uv --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "uvx: $(uvx --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "Node: $(node --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "npm: $(npm --version)"' >> /home/vscode/.bashrc \
    && echo 'echo "======================="' >> /home/vscode/.bashrc \
    && echo 'echo ""' >> /home/vscode/.bashrc

CMD ["/bin/bash"]
