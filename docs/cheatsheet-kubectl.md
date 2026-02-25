# kubectl Cheat Sheet

A consolidated reference of common `kubectl` commands organized by category.

---

## Cluster Management

| Command                      | Description                      |
|------------------------------|----------------------------------|
| `kubectl cluster-info`       | Get cluster information.         |
| `kubectl get nodes`          | View all nodes in the cluster.   |
| `kubectl config use-context` | Switch to a specific context.    |

---

## Node Management

| Command                                                        | Description                                   |
|----------------------------------------------------------------|-----------------------------------------------|
| `kubectl get nodes`                                            | List all nodes in the cluster.                |
| `kubectl describe node <node-name>`                            | Describe a specific node.                     |
| `kubectl drain <node-name>`                                    | Drain a node for maintenance.                 |
| `kubectl uncordon <node-name>`                                 | Uncordon a node after maintenance.            |
| `kubectl label node <node-name> <key>=<value>`                 | Attach a label to a node.                     |
| `kubectl label node <node-name> <label-key>-`                  | Remove a label from a node.                   |

---

## Namespace Management

| Command                                                              | Description                                          |
|----------------------------------------------------------------------|------------------------------------------------------|
| `kubectl describe namespace <namespace-name>`                        | Describe a namespace.                                |
| `kubectl create namespace <namespace-name>`                          | Create a namespace.                                  |
| `kubectl get namespaces`                                             | List all namespaces.                                 |
| `kubectl config set-context --current --namespace=<namespace-name>`  | Switch to a different namespace.                     |
| `kubectl delete namespace <namespace-name>`                          | Delete a namespace.                                  |
| `kubectl edit namespace <namespace-name>`                            | Edit and update the namespace definition.            |

---

## Creating Resources

| Command                                                                     | Definition                                           |
|-----------------------------------------------------------------------------|------------------------------------------------------|
| `kubectl apply -f <resource-definition.yaml>`                               | Create or update a resource from a YAML file.        |
| `kubectl create <resource>`                                                 | Imperatively create an object.                       |
| `kubectl apply -f https://url-to-resource-definition.yaml`                  | Create a resource by URL.                            |

---

## Viewing & Finding Resources

| Command                                                                    | Description                                                      |
|----------------------------------------------------------------------------|------------------------------------------------------------------|
| `kubectl get <resource-type>`                                              | List all resources of a specific type.                           |
| `kubectl get <resource-type> -o wide`                                      | List all resources with additional details.                      |
| `kubectl describe <resource-type> <resource-name>`                         | Describe a specific resource.                                    |
| `kubectl get <resource-type> -l <label-key>=<label-value>`                 | List resources with a specific label.                            |
| `kubectl get <resource-type> --all-namespaces`                             | List all resources in all namespaces.                            |
| `kubectl get <resource-type> --sort-by=<field>`                            | List resources sorted by a specific field.                       |
| `kubectl get <resource-type> --field-selector=<field-selector>`            | List resources filtered by a field.                              |
| `kubectl get <resource-type> -n <namespace>`                               | List all resources in a specific namespace.                      |

---

## Deleting Resources

| Command                                                                          | Description                                                            |
|----------------------------------------------------------------------------------|------------------------------------------------------------------------|
| `kubectl delete <resource-type> <resource-name>`                                 | Delete a resource.                                                     |
| `kubectl delete <type1> <name1> <type2> <name2>`                                 | Delete multiple resources.                                             |
| `kubectl delete <resource-type> --all`                                           | Delete all resources of a specific type.                               |
| `kubectl delete -f <resource-definition.yaml>`                                   | Delete a resource by YAML file.                                        |
| `kubectl delete -f https://url-to-resource-definition.yaml`                      | Delete a resource by URL.                                              |
| `kubectl delete <resource-type> --all -n <namespace>`                            | Delete all resources of a type in a namespace.                         |

---

## Copying Files & Directories

| Command                                                                                                         | Description                                             |
|-----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| `kubectl cp <local-path> <namespace>/<pod-name>:<container-path>`                                               | Copy files/directories to a container.                  |
| `kubectl cp <namespace>/<pod-name>:<container-path> <local-path>`                                               | Copy files/directories from a container.                |
| `kubectl cp <ns>/<pod>:<src-path> <ns>/<pod>:<dest-path>`                                                       | Copy files between containers in the same pod.          |
| `kubectl cp <src-ns>/<src-pod>:<src-path> <dest-ns>/<dest-pod>:<dest-path>`                                     | Copy files between containers in different pods.        |

---

## Patching Resources

| Command                                                                                          | Description                                |
|--------------------------------------------------------------------------------------------------|--------------------------------------------|
| `kubectl patch <type> <name> -p '<patch-document>'`                                              | Patch a resource with inline JSON/YAML.    |
| `kubectl patch <type> <name> --patch-file=<patch-file>`                                          | Patch a resource from a JSON/YAML file.    |

---

## Scaling Resources

| Command                                                                      | Description                  |
|------------------------------------------------------------------------------|------------------------------|
| `kubectl scale deployment <name> --replicas=<count>`                         | Scale a Deployment.          |
| `kubectl scale statefulset <name> --replicas=<count>`                        | Scale a StatefulSet.         |
| `kubectl scale replicaset <name> --replicas=<count>`                         | Scale a ReplicaSet.          |

---

## Pod Management

| Command                                                                                | Description                                  |
|----------------------------------------------------------------------------------------|----------------------------------------------|
| `kubectl create -f <pod-definition.yaml>`                                              | Create a Pod from a YAML file.               |
| `kubectl get pods`                                                                     | List all Pods in the cluster.                |
| `kubectl describe pod <pod-name>`                                                      | Describe a specific Pod.                     |
| `kubectl logs <pod-name>`                                                              | Get logs from a Pod.                         |
| `kubectl logs -f <pod-name>`                                                           | Stream logs from a Pod.                      |
| `kubectl logs -l <label-key>=<label-value>`                                            | Get logs from Pods with a label.             |
| `kubectl exec -it <pod-name> -- <command>`                                             | Exec into a Pod.                             |
| `kubectl delete pod <pod-name>`                                                        | Delete a Pod.                                |
| `kubectl get pod -n <namespace>`                                                       | List all Pods in a namespace.                |

---

## Deployment Management

| Command                                                                                              | Description                                         |
|------------------------------------------------------------------------------------------------------|-----------------------------------------------------|
| `kubectl create deployment <name> --image=<image>`                                                   | Create a Deployment.                                |
| `kubectl get deployments`                                                                            | List all Deployments.                               |
| `kubectl describe deployment <name>`                                                                 | Describe a specific Deployment.                     |
| `kubectl set image deployment/<name> <container>=<new-image>`                                        | Update a Deployment's image.                        |
| `kubectl rollout status deployment/<name>`                                                           | Show rollout status.                                |
| `kubectl rollout pause deployment/<name>`                                                            | Pause a rollout.                                    |
| `kubectl rollout resume deployment/<name>`                                                           | Resume a rollout.                                   |
| `kubectl rollout undo deployment/<name>`                                                             | Roll back to previous revision.                     |
| `kubectl rollout undo deployment/<name> --to-revision=<revision-number>`                             | Roll back to a specific revision.                   |
| `kubectl delete deployment <name>`                                                                   | Delete a Deployment.                                |

---

## ReplicaSet Management

| Command                                                                 | Description                  |
|-------------------------------------------------------------------------|------------------------------|
| `kubectl create -f <replicaset-definition.yaml>`                       | Create a ReplicaSet.         |
| `kubectl get replicasets`                                               | List all ReplicaSets.        |
| `kubectl describe replicaset <name>`                                    | Describe a specific RS.      |
| `kubectl scale replicaset <name> --replicas=<count>`                    | Scale a ReplicaSet.          |

---

## Service Management

| Command                                                                              | Description                             |
|--------------------------------------------------------------------------------------|-----------------------------------------|
| `kubectl create service <type> <name> --tcp=<port>`                                  | Create a Service.                       |
| `kubectl get services`                                                               | List all Services.                      |
| `kubectl expose deployment <deployment-name> --port=<port>`                          | Expose a Deployment as a Service.       |
| `kubectl describe service <service-name>`                                            | Describe a Service.                     |
| `kubectl delete service <service-name>`                                              | Delete a Service.                       |
| `kubectl get endpoints <service-name>`                                               | Show Service endpoints.                 |

---

## ConfigMaps & Secrets

| Command                                                                                       | Description                                           |
|-----------------------------------------------------------------------------------------------|-------------------------------------------------------|
| `kubectl create configmap <name> --from-file=<path>`                                          | Create a ConfigMap from a file.                       |
| `kubectl get configmaps`                                                                      | List all ConfigMaps.                                  |
| `kubectl describe configmap <name>`                                                           | Describe a ConfigMap.                                 |
| `kubectl delete configmap <name>`                                                             | Delete a ConfigMap.                                   |
| `kubectl create secret <type> <name> --from-literal=<key>=<value>`                            | Create a Secret.                                      |
| `kubectl get secrets`                                                                         | List all Secrets.                                     |
| `kubectl describe secret <name>`                                                              | Describe a Secret.                                    |
| `kubectl delete secret <name>`                                                                | Delete a Secret.                                      |

---

## Networking

| Command                                                                                                         | Description                                             |
|-----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| `kubectl port-forward <pod-name> <local-port>:<pod-port>`                                                       | Port-forward to a Pod.                                  |
| `kubectl expose deployment <deployment-name> --type=NodePort --port=<port>`                                     | Expose as a NodePort Service.                           |
| `kubectl create ingress <name> --rule=<host>/<path>=<service>:<port>`                                           | Create an Ingress resource.                             |
| `kubectl describe ingress <name>`                                                                               | Describe an Ingress.                                    |
| `kubectl get ingress <name> -o jsonpath='{.spec.rules[0].host}'`                                               | Retrieve the host from the first Ingress rule.          |

---

## Storage

| Command                                                                                     | Description                                      |
|---------------------------------------------------------------------------------------------|--------------------------------------------------|
| `kubectl create -f <pv-definition.yaml>`                                                    | Create a PersistentVolume.                       |
| `kubectl get pv`                                                                            | List all PersistentVolumes.                      |
| `kubectl describe pv <pv-name>`                                                             | Describe a PersistentVolume.                     |
| `kubectl create -f <pvc-definition.yaml>`                                                   | Create a PersistentVolumeClaim.                  |
| `kubectl get pvc`                                                                           | List all PVCs.                                   |
| `kubectl describe pvc <pvc-name>`                                                           | Describe a PersistentVolumeClaim.                |

---

## StatefulSet Management

| Command                                                                                     | Description                                     |
|---------------------------------------------------------------------------------------------|-------------------------------------------------|
| `kubectl create -f <statefulset-definition.yaml>`                                           | Create a StatefulSet.                           |
| `kubectl get statefulsets`                                                                  | List all StatefulSets.                          |
| `kubectl describe statefulset <name>`                                                       | Describe a StatefulSet.                         |
| `kubectl scale statefulset <name> --replicas=<count>`                                       | Scale a StatefulSet.                            |

---

## Monitoring & Troubleshooting

| Command                                                                 | Description                             |
|-------------------------------------------------------------------------|-----------------------------------------|
| `kubectl get events`                                                    | Check cluster events.                   |
| `kubectl get componentstatuses`                                         | Get component health statuses.          |
| `kubectl top nodes`                                                     | Show node resource utilization.         |
| `kubectl top pods`                                                      | Show pod resource utilization.          |
| `kubectl debug <pod-name> -it --image=<debug-image>`                    | Debug a Pod with a debug container.     |

---

## Miscellaneous

| Command                                  | Description                               |
|------------------------------------------|-------------------------------------------|
| `kubectl proxy`                          | Run a local proxy to the API server.      |
| `kubectl completion <shell>`             | Install shell completion.                 |
| `kubectl config view`                    | Display merged kubeconfig settings.       |

---

## kubectl Output Verbosity & Debugging

Control client-side verbosity with `--v=<level>`:

| Command                                                           | Effect                                                    |
|-------------------------------------------------------------------|-----------------------------------------------------------|
| `kubectl get <resource> --v=0`                                    | Minimal output.                                           |
| `kubectl get <resource> --v=3`                                    | Extended information about changes.                       |
| `kubectl get <resource> --v=7`                                    | Show HTTP request headers.                                |
| `kubectl get <resource> --v=8`                                    | Show full HTTP request contents.                          |

---

## Project-Specific: KRO & ACK Inspection

Commands specific to this platform for inspecting KRO ResourceGraphDefinitions and ACK controller status.

### KRO Resources

| Command                                                                              | Description                                            |
|--------------------------------------------------------------------------------------|--------------------------------------------------------|
| `kubectl get resourcegraphdefinitions`                                               | List all KRO ResourceGraphDefinitions.                 |
| `kubectl get resourcegraphdefinitions -o wide`                                       | List RGDs with additional status columns.              |
| `kubectl describe resourcegraphdefinition <name>`                                    | Show detailed RGD status and conditions.               |
| `kubectl get instances -A`                                                           | List all KRO instances across namespaces.              |
| `kubectl describe instance <name> -n <namespace>`                                    | Show instance status and managed resources.            |
| `kubectl get pods -n kro-system`                                                     | Check KRO controller pods.                             |
| `kubectl logs -n kro-system -l app.kubernetes.io/name=kro --tail=100`                | View KRO controller logs.                              |

### ACK Controllers

| Command                                                                                  | Description                                            |
|------------------------------------------------------------------------------------------|--------------------------------------------------------|
| `kubectl get pods -A \| grep ack-`                                                       | Find all ACK controller pods across namespaces.        |
| `kubectl get pods -n ack-system`                                                         | List ACK controller pods (if using shared namespace).  |
| `kubectl logs -n <ack-ns> -l app.kubernetes.io/name=<ack-controller> --tail=100`         | View ACK controller logs.                              |
| `kubectl get crd \| grep amazonaws.com`                                                   | List all ACK-installed CRDs.                           |
| `kubectl get adoptedresources -A`                                                        | List adopted AWS resources.                            |
| `kubectl get fieldexports -A`                                                            | List ACK field export resources.                       |

### ArgoCD Status

| Command                                                                              | Description                                            |
|--------------------------------------------------------------------------------------|--------------------------------------------------------|
| `kubectl get applications -n argocd`                                                 | List all ArgoCD Applications.                          |
| `kubectl get applicationsets -n argocd`                                              | List all ArgoCD ApplicationSets.                       |
| `kubectl get applications -n argocd -o wide`                                         | Show sync/health status for all apps.                  |
| `kubectl describe application <name> -n argocd`                                     | Detailed app status with sync conditions.              |
| `kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster`            | List ArgoCD cluster secrets (registered clusters).     |

### Cross-Account Verification

| Command                                                                              | Description                                            |
|--------------------------------------------------------------------------------------|--------------------------------------------------------|
| `kubectl get pods -A -l app.kubernetes.io/instance=ack-* -o wide`                    | Verify ACK pod identity associations.                  |
| `kubectl describe sa -n <ack-ns> <service-account>`                                  | Check SA annotations for IAM role ARN.                 |

---

*Happy kubectl-ing!*
