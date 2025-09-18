# eks-cluster-mgmt
This repository contains the necessary files and configurations to set up a GitOps-based EKS cluster management solution using Argo CD and KRO (Kubernetes Resource Operator). The structure is designed to support multiple environments (dev, staging, prod) and accounts, ensuring modularity and reusability. 
# Overview
The bootstrap process is initiated by the `boot.sh` script, which sets up the necessary environment variables and configurations for the EKS clusters. 
Below is an overview of the directory structure and a brief description of desired repository structure.
# Desired Repository Structure

bootstrap/
├─ .gitattributes                # text files, line endings, etc.
├─ .gitignore                    # Terraform state, .DS_Store, etc.
├─ CODEOWNERS                   # path-based approvers
├─ README.md                    # high-level overview, dev guide
│
├─ scripts/
│  ├─ axle.sh               # script to loop through steps please rename
│  ├─ config/
│  │  ├─ aws.env                # AWS CLI environment defaults
│  │  ├─ directory.env          # directory path defaults 
│  │  ├─ file-list.env          # list of files to include in the bootstrap process
│  │  ├─ hub.env                # hub-specific defaults
│  │  ├─ output.env             # output folder mapping
│  │  ├─ repository.env         # repository-specific defaults
│  │  └─ spoke.env              # spoke-specific defaults
│  │
│  ├─ steps/
│  ├─ 0-load-env.sh           # load config files
│  ├─ 1-setup-repo.sh         # initialize git repo, commit initial files
│  ├─ 2-mod-repo.sh           # modify repo with hub/spoke names, etc.
│  ├─ 3-validate-variables.sh # validate the bootstrap process
│  ├─ 4-terraform.sh          # Terraform initialization, plan, and apply/destroy
│  ├─ 5-bootstrap-backup.sh   # backup the bootstrap process
│  ├─ 6-setup-argocd.sh       # setup Argo CD
│  └─ 7-cluster-info.sh       # gather cluster information
│
├─ utils/
│  ├─ error-codes.sh        # error code definitions
│  ├─ functions.sh          # utility functions
│  ├─ logger.sh             # logging functions

├─ templates/
│  ├─ argo/                      # ⬅️ GitOps layer
│  │  ├─ appsets/                # HOW platform is deployed
│  │  │  └─ <hub-name>/
│  │  │     ├─ apps-addons.yaml
│  │  │     ├─ apps-kro-hub.yaml
│  │  │     └─ apps-kro-spokes.yaml
│  │  │
│  │  ├─ apps/                   # WHAT is deployed
│  │  │  ├─ addons/
│  │  │  │  ├─ loki/
│  │  │  │  │  ├─ Chart.yaml
│  │  │  │  │  └─ values.yaml
│  │  │  │  ├─ prometheus/
│  │  │  │  │  ├─ Chart.yaml
│  │  │  │  │  └─ values.yaml
│  │  │  │  └─ tempo/
│  │  │  │     ├─ Chart.yaml
│  │  │  │     └─ values.yaml
│  │  │  │
│  │  │  └─ kro/
│  │  │     ├─ hub/
│  │  │     │  ├─ controllers/
│  │  │     │  │  ├─ Chart.yaml
│  │  │     │  │  └─ values.yaml
│  │  │     │  └─ rgds/
│  │  │     │     └─ <ack-graph>.yaml
│  │  │     └─ spoke/
│  │  │        ├─ controllers/
│  │  │        │  ├─ Chart.yaml
│  │  │        │  └─ values.yaml
│  │  │        └─ rgds/
│  │  │           └─ <workload-graph>.yaml
│  │  │
│  │  ├─ clusters/               # WHERE things run
│  │  │  └─ hubs/
│  │  │     └─ <hub-name>/
│  │  │        └─ hub-root.yaml
│  │  │
│  │  ├─ projects/               # RBAC / guardrails
│  │  │  ├─ project-hub.yaml
│  │  │  └─ project-spokes.yaml
│  │  │
│  │  └─ values/                 # flat, composable overrides
│  │     ├─ accounts/
│  │     │  └─ <account>.yaml
│  │     ├─ common.yaml
│  │     ├─ envs/
│  │     │  └─ <environment>.yaml
│  │     └─ matrices/
│  │        └─ <account>--<instance_category>--<environment>.yaml
│  │
│  └─ terraform/                 # ⬅️ I-a-C layer
│     ├─ hubs/                   # one dir per hub cluster
│     │  └─ <hub-name>/
│     │     ├─ backend.tf
│     │     ├─ main.tf
│     │     ├─ outputs.tf
│     │     ├─ terraform.tfvars
│     │     └─ variables.tf
│     │
│     └─ modules/                # reusable building blocks
│        ├─ eks-hub/
│        │  ├─ main.tf
│        │  ├─ outputs.tf
│        │  └─ variables.tf
│        └─ eks-spoke/
│           ├─ main.tf
│           ├─ outputs.tf
│           └─ variables.tf
   ├─ bootstrap/                    # day-0 utilities
   │  ├─ install-argocd.yaml        # namespace + upstream manifests
   │  └─ register-spoke.sh          # argocd cluster add + label patch
   │
   └─ .github/                      # CI/CD guards (GitHub Actions example)
       └─ workflows/
           ├─ terraform.yml         # fmt / validate / plan / apply
           ├─ helm-lint.yml         # helm lint, chart-testing
           └─ argocd-validate.yml   # kubeconform, argocd app lint



# 

- Git hosting (GitHub/GitLab/Bitbucket).

1. Setup