# Kubernetes Cluster

- Add docker user

`sudo usermod -aG docker $USER && newgrp docker`

- minikube start cluster

`minikube start --memory 5120 --cpus 5`

- nodes in cluster

`kubectl get nodes`

- get pods in default node

`kubectl get pods -o wide`

- See pods in node

`kubectl get pods -o wide --field-selector spec.nodeName=node1`

- Delete node
  `minikube node delete minikube-m02`

- Add Node
  `minikube node add --cpus 2 --memory 2048`

- errors in prod

`kubectl describe pod mypod`

- Load image in nimikube
  `minikube image load testapp:latest --daemon`

- Laod yaml File (Create Prod)
  `kubectl apply -f testAppProd.yaml`

- Delete pod 
`kubectl delete pod mypod`

- See pod status in new node
`kubectl get pods -o wide --field-selector spec.nodeName=minikube-m02`

- kubectl port forwarding 
`kubectl port-forward pod/mypod 3000:3000`

-logs for specific pod
`kubectl logs mypod`
