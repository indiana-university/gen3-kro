# Dev Container Configuration

This project provides OS-specific devcontainer configurations to handle different credential paths on different operating systems.

## Available Configurations

### Option 1: Automatic (Current - `devcontainer.json`)
- Uses environment variable fallback: `${localEnv:HOME}${localEnv:USERPROFILE}`
- Should work on most systems but may have edge cases

### Option 2: OS-Specific Configurations
Choose the appropriate configuration for your operating system:

#### Windows (`devcontainer-windows.json`)
```bash
# In VS Code Command Palette (Ctrl+Shift+P)
> Dev Containers: Reopen in Container
# Then select: devcontainer-windows.json
```

#### Linux/macOS (`devcontainer-unix.json`)
```bash
# In VS Code Command Palette (Ctrl+Shift+P)
> Dev Containers: Reopen in Container  
# Then select: devcontainer-unix.json
```

## Credential Mounts

All configurations mount these directories from your host:

- **`.kube`** → `/home/vscode/.kube` (Kubernetes configs)
- **`.aws`** → `/home/vscode/.aws` (AWS credentials)
- **`.config/gh`** → `/home/vscode/.config/gh` (GitHub CLI credentials)

## Path Differences

| OS | Home Directory | Mount Source |
|---|---|---|
| Windows | `%USERPROFILE%` | `${localEnv:USERPROFILE}/.kube` |
| Linux/macOS | `$HOME` | `${localEnv:HOME}/.kube` |

## Switching Configurations

1. Close the current devcontainer
2. Rename your desired config file to `devcontainer.json`
3. Reopen in container

Or use VS Code's configuration selector when reopening.

## Troubleshooting

If you get "bind source path does not exist" errors:
1. Ensure the credential directories exist on your host
2. Use the OS-specific configuration file
3. Check that environment variables are set correctly