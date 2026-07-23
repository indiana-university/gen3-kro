# AGENTS.md

## Scope

The devcontainer is a reproducible toolchain for CSOC operations. It is not the
deployment orchestrator.

## Rules

- Keep Terraform, Terragrunt, AWS CLI, kubectl, Helm, yq, uv, and Node tooling
  versioned in the Dockerfile.
- Mount only the scoped `~/.aws/jayadeyemi` credential directory into
  `/home/vscode/.aws`. The current container profile is `badeyemi_tf`.
- Every host AWS credential-directory mount must be read-only inside its
  container. Refresh credentials from the host, never from inside a container.
- Do not mount host `~/.kube`.
- Do not set lifecycle commands that auto-apply infrastructure by default.
- Prefer `setup` or `setup connect` for container lifecycle commands.

## File Contracts

- The root `Dockerfile` owns OS packages and pinned CLI installation. Keep
  checksum verification for downloaded release archives where the publisher
  provides checksums, remove temporary install files, and verify installed
  binaries during the build.
- `devcontainer.json` is JSON with comments. It owns the build context, scoped
  credential mount, lifecycle hooks, forwarded Argo CD port, extensions, and
  container environment. Keep `remoteUser` as the non-root `vscode` user and do
  not add privileged mode, host networking, or a Docker socket mount without a
  documented requirement and security review.
- `devcontainer-lock.json` is tracked resolved feature metadata. Regenerate it
  with Dev Containers tooling when feature declarations change; do not invent
  digests or let it drift from `devcontainer.json`.
- `README.md` must distinguish host prerequisites from tools installed inside
  the container and must use the supported `scripts/terragrunt-stack.sh`
  entrypoint rather than generated or retired per-stack scripts.

## Lifecycle and Local State

- `postCreateCommand` may prepare the environment and validate credentials.
  `postStartCommand` may reconnect to an existing cluster. Neither may create,
  apply, or destroy infrastructure.
- The host writes credentials under `~/.aws/jayadeyemi`; the container sees
  that directory as `/home/vscode/.aws`. Keep `~/.kube` container-local and
  regenerate kubeconfig through the explicit connect stage.
- Runtime MCP config, kubeconfig, Argo CD passwords, logs, reports, and shell
  environment files are local/generated material. Document where they are
  created, but do not add them to the image or tracked source.
- Keep `/home/vscode/.codex` on the `gen3-kro-codex` named volume so Codex
  configuration, authentication, logs, and chat sessions survive ordinary
  devcontainer rebuilds. Treat the volume as sensitive local state and document
  that deleting Docker volumes or changing Docker hosts removes it.
- Keep Terraform CLI pins synchronized between the Dockerfile and root
  `.terraform-version`. Clearly label tools downloaded from `latest` as
  unpinned in documentation.

## Bug and Troubleshooting Reports

- Include reproduction steps, expected and actual behavior, product, model and
  version, platform or environment, timestamp and timezone, request ID when
  relevant, and sanitized logs, screenshots, or code.

## Validation

- For Dockerfile-only changes, inspect the changed download URL, architecture,
  checksum path, cleanup, and version command. Run a targeted image build when
  practical.
- For `devcontainer.json`, verify referenced paths and lifecycle scripts exist;
  use Dev Containers configuration/build validation when available.
- Run `bash -n scripts/container-init.sh` when lifecycle commands or their
  contract change, and run `git diff --check` for instruction/doc changes.

## Safety

Do not add secrets, real account IDs, ARNs with account IDs, tfstate,
`.terragrunt-stack` content, generated outputs, or local credential artifacts
to tracked files.

## Architecture Diagram Semantics

- Nesting means ownership or containment; it never means dependency.
- A solid connector between resource boxes means the destination consumes data,
  configuration, or a reference from the source. Draw fan-out and fan-in with
  explicit tee branches, keep arrowheads touching consumers, and leave resources
  unconnected when no such flow exists.
- Do not turn `depends_on`, Terragrunt ordering, Argo CD sync waves, an opaque
  ordering token, or observed apply sequence into a resource-data connector.
  Show ordering-only information with one detached guide such as `Deployment
  order only (not resource data): earlier -> later`, and arrange the diagram in
  that general direction.
- State connector meanings in a legend or adjacent text. Unit, module, or stack
  orchestration connectors may represent ordering when labeled; a connector
  must not silently switch between containment, data flow, and ordering.
