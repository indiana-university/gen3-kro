# Devcontainer Usage (gen3-kro)

This project uses a single VS Code devcontainer configured in `.devcontainer/`.

Quick steps to open the repository in the VS Code devcontainer:

1. Install the "Dev Containers" extension in VS Code.
2. Open this repository in VS Code.
3. Command Palette -> Dev Containers: Reopen in Container.

Mounts
- The devcontainer only mounts your host `~/.kube` and `~/.aws` into the container. No other host paths are mounted.

Quick local build (to validate Dockerfile):

```bash
# From the repository root
docker build -f .devcontainer/Dockerfile -t gen3-kro-dev .
```

Quick run (start an interactive shell with your host AWS/Kube mounts):

```bash
docker run --rm -it \
  -v "$HOME/.kube:/home/vscode/.kube:ro" \
  -v "$HOME/.aws:/home/vscode/.aws:ro" \
  -v "$(pwd):/workspaces/gen3-kro" \
  gen3-kro-dev /bin/bash
```

Notes
- The CI workflow builds the same `.devcontainer/Dockerfile` so dev and CI use the same image definition.
- Binaries (Terraform, Terragrunt) are verified by checksums during build.
