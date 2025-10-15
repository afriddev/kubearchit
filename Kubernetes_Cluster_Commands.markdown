# Kubernetes Cluster Commands

This document provides a collection of essential Kubernetes commands for managing a Minikube cluster.

## User and Cluster Setup
- **Add Docker User**  
  Add the current user to the Docker group to allow running Docker commands without `sudo`.  
  ```bash
  sudo usermod -aG docker $USER && newgrp docker
  ```

- **Start Minikube Cluster**  
  Start a Minikube cluster with specified memory and CPU resources.  
  ```bash
  minikube start --memory 5120 --cpus 5
  ```

## Cluster and Node Management
- **List Nodes in Cluster**  
  Display all nodes in the Kubernetes cluster.  
  ```bash
  kubectl get nodes
  ```

- **Add a Node**  
  Add a new node to the Minikube cluster with specified CPU and memory.  
  ```bash
  minikube node add 
  ```

- **Delete a Node**  
  Remove a specific node (e.g., `minikube-m02`) from the Minikube cluster.  
  ```bash
  minikube node delete minikube-m02
  ```

## Pod Management
- **List Pods in Default Namespace**  
  Display all pods in the default namespace with detailed information.  
  ```bash
  kubectl get pods -o wide
  ```

- **List Pods on a Specific Node**  
  Display pods running on a specific node (e.g., `node1`).  
  ```bash
  kubectl get pods -o wide --field-selector spec.nodeName=node1
  ```

- **Check Pod Status on a Specific Node**  
  Display pods running on a specific node (e.g., `minikube-m02`).  
  ```bash
  kubectl get pods -o wide --field-selector spec.nodeName=minikube-m02
  ```

- **Create/Update Pod from YAML**  
  Apply a pod configuration from a YAML file (e.g., `testAppProd.yaml`).  
  ```bash
  kubectl apply -f testAppProd.yaml
  ```

- **Delete a Pod**  
  Delete a specific pod (e.g., `mypod`).  
  ```bash
  kubectl delete pod mypod
  ```

## Debugging and Monitoring
- **View Pod Details/Errors**  
  Display detailed information about a specific pod (e.g., `mypod`) to troubleshoot issues.  
  ```bash
  kubectl describe pod mypod
  ```

- **View Pod Logs**  
  Retrieve logs for a specific pod (e.g., `mypod`).  
  ```bash
  kubectl logs mypod
  ```

## Image Management
- **Load Image into Minikube**  
  Load a Docker image (e.g., `testapp:latest`) into the Minikube cluster.  
  ```bash
  minikube image load testapp:latest --daemon
  ```

## Networking
- **Port Forwarding**  
  Forward a local port (e.g., `3000`) to a pod's port (e.g., `3000`) for a specific pod (e.g., `mypod`).  
  ```bash
  kubectl port-forward pod/mypod 3000:3000
  ```