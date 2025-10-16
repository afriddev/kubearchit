# 🚀 Kubernetes + Minikube + React App Setup Guide

This guide combines Kubernetes core commands and a full React app deployment workflow using Minikube.

---

## 🧩 Prerequisites

Ensure Docker, Node.js, and Minikube are installed.  
Then, add your current user to the Docker group:

```bash
sudo usermod -aG docker $USER && newgrp docker
```

---

## ⚙️ Start & Manage Kubernetes Cluster

```bash
minikube start --driver=docker --memory 5120 --cpus 5
kubectl get nodes
```

### 🧱 Node Management

- **Add Node**
  ```bash
  minikube node add --cpus 2 --memory 2048
  ```

- **Delete Node**
  ```bash
  minikube node delete minikube-m02
  ```

- **View Pods per Node**
  ```bash
  kubectl get pods -o wide --field-selector spec.nodeName=minikube-m02
  ```

---

## 🧠 React App Creation

```bash
npm create vite@latest testapp -- --template react
cd testapp
npm install
npm run build
```

---

## 🐳 Dockerfile

```Dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
RUN npm install -g serve
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
```

### 🏗️ Build & Load Docker Image

```bash
docker build -t testapp:latest .
minikube image load testapp:latest --daemon
minikube image ls | grep testapp
```

---

## 🚢 Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: testapp-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: testapp
  template:
    metadata:
      labels:
        app: testapp
    spec:
      containers:
        - name: testapp
          image: testapp:latest
          imagePullPolicy: Never
          ports:
            - containerPort: 3000
```

```bash
kubectl apply -f deployment.yaml
kubectl get pods -o wide
kubectl describe pod testapp-deployment
```

---

## 🌐 Service Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: testapp-service
spec:
  type: NodePort
  selector:
    app: testapp
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30080
```

```bash
kubectl apply -f service.yaml
kubectl get svc
```

---

## ☸️ LoadBalancer / Tunnel Access

```bash
kubectl patch svc testapp-service -p '{"spec": {"type": "LoadBalancer"}}'
kubectl get svc testapp-service

sudo nohup minikube tunnel > /dev/null 2>&1 &
nohup kubectl port-forward service/testapp-service 3000:3000 --address=0.0.0.0 > /dev/null 2>&1 &
```

---

## 🧰 Useful Kubernetes Commands

| Action | Command |
|--------|----------|
| Get all pods | `kubectl get pods -o wide` |
| Get pods in specific node | `kubectl get pods -o wide --field-selector spec.nodeName=node1` |
| Delete a pod | `kubectl delete pod <pod-name>` |
| Check pod logs | `kubectl logs <pod-name>` |
| Describe pod errors | `kubectl describe pod <pod-name>` |
| Forward ports to localhost | `kubectl port-forward pod/<pod-name> 3000:3000` |
| Get services | `kubectl get svc` |
| Apply a YAML file | `kubectl apply -f <file>.yaml` |
| Delete a resource | `kubectl delete -f <file>.yaml` |

---

## ✅ Verification

Once everything is deployed, check your app:

```bash
minikube service testapp-service
```

or access via NodePort:

```
http://<minikube-ip>:30080
```

---

### 📄 Summary

This setup covers:
- Docker + Minikube + React workflow
- Cluster node operations
- Pod & Service management
- LoadBalancer access for production-like environments

Perfect for local Kubernetes testing or small-scale production demos. 🚀
