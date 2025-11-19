kubectl describe awsvpc vpc -n spoke1-infrastructure

kubectl delete awsvpc awsvpc -n spoke1-infrastructure
kubectl patch awsvpc awsvpc -n spoke1-infrastructure -p '{"metadata":{"finalizers":null}}' --type=merge
correct the observed issues with your template and commit the changes and sync via argocd, or manually apply the corrected yaml via:

kubectl apply -f <corrected-yaml-file> -n <namespace>
argocd app sync <app-name>




