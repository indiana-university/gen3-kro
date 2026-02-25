# Helm Cheatsheet

## Project-Specific Commands

```bash
# Validate project charts (run from repo root)
helm template argocd/charts/application-sets/
helm template argocd/charts/instances/
helm template argocd/charts/resource-groups/
helm template argocd/charts/workloads/

# Template with custom values
helm template argocd/charts/instances/ -f argocd/cluster-fleet/spoke1/infrastructure.yaml

# List Helm releases in ArgoCD namespace
helm list -n argocd

# Inspect ArgoCD Helm release values
helm get values argocd -n argocd
```

## Chart Management

```bash
helm create <name>                      # Creates a chart directory with common files
helm package <chart-path>               # Packages a chart into a versioned archive
helm lint <chart>                       # Run tests to examine a chart for issues
helm show all <chart>                   # Inspect a chart and list its contents
helm show values <chart>                # Display the contents of values.yaml
helm pull <chart>                       # Download/pull chart
helm pull <chart> --untar=true          # Untar the chart after downloading
helm pull <chart> --verify              # Verify the package before using it
helm pull <chart> --version <number>    # Specify a version constraint
helm dependency list <chart>            # Display a list of a chart's dependencies
```

## Install and Uninstall Apps

```bash
helm install <name> <chart>                           # Install with a name
helm install <name> <chart> --set key1=val1,key2=val2 # Set values on the command line
helm install <name> <chart> --values <yaml-file/url>  # Install with specified values
helm install <name> <chart> --dry-run --debug         # Test installation
helm install <name> <chart> --verify                  # Verify the package first
helm install <name> <chart> --dependency-update       # Update dependencies before installing
helm uninstall <name>                                 # Uninstall a release
```

## Upgrade and Rollback

```bash
helm upgrade <release> <chart>                            # Upgrade a release
helm upgrade <release> <chart> --atomic                   # Roll back on failed upgrade
helm upgrade <release> <chart> --dependency-update        # Update dependencies first
helm upgrade <release> <chart> --version <version_number> # Specify chart version
helm upgrade <release> <chart> --values <yaml-file>       # Specify values file
helm upgrade <release> <chart> --set key1=val1,key2=val2  # Set values inline
helm upgrade <release> <chart> --force                    # Force resource updates
helm rollback <release> <revision>                        # Roll back to a revision
helm rollback <release> <revision> --cleanup-on-fail      # Delete new resources on rollback failure
```

## Repositories

```bash
helm repo add <repo-name> <url>   # Add a repository
helm repo list                    # List added chart repositories
helm repo update                  # Update chart info locally
helm repo remove <repo_name>      # Remove chart repositories
helm repo index <DIR>             # Generate index from charts in directory
helm repo index <DIR> --merge     # Merge with an existing index file
helm search repo <keyword>        # Search repositories for a keyword
helm search hub <keyword>         # Search Artifact Hub
```

## Release Monitoring

```bash
helm list                       # List releases for current namespace
helm list --all                 # Show all releases (no filter)
helm list --all-namespaces      # List releases across all namespaces
helm list -l key1=value1        # Filter by label selector
helm list --date                # Sort by release date
helm list --deployed            # Show deployed releases
helm list --pending             # Show pending releases
helm list --failed              # Show failed releases
helm list --uninstalled         # Show uninstalled releases
helm list -o yaml               # Output as YAML (table, json, yaml)
helm status <release>           # Show status of a named release
helm status <release> --revision <number>  # Status at specific revision
helm history <release>          # Historical revisions
helm env                        # Print Helm environment info
```

## Release Information

```bash
helm get all <release>      # All release info (notes, hooks, values, manifest)
helm get hooks <release>    # Download hooks
helm get manifest <release> # Download generated manifest
helm get notes <release>    # Show chart notes
helm get values <release>   # Download values file (-o for format)
```

## Plugin Management

```bash
helm plugin install <path/url>      # Install plugins
helm plugin list                    # View installed plugins
helm plugin update <plugin>         # Update plugins
helm plugin uninstall <plugin>      # Uninstall a plugin
```
