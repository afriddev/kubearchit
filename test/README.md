## Production-Grade Kubernetes Setup for FastAPI Backend with NGINX Ingress

This setup deploys a **FastAPI backend** on a **Minikube (bare-metal)** cluster running on a **GCP instance** (`35.224.185.200`).  
It uses **Kubernetes Ingress** and a **host-level NGINX reverse proxy** for persistent external access 

---

## ⚙️ Prerequisites

- GCP VM with firewall open for **ports 80 and 30808**  
- Installed:
  ```bash
  sudo apt update
  sudo apt install -y docker.io kubectl minikube nginx
  ```
- Start cluster:
  ```bash
  minikube start --driver=docker --memory=8192 --cpus=6
  ```

---

## 🧠 FastAPI Backend

### `main.py`
```python
from fastapi import FastAPI
import logging

app = FastAPI()
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@app.get("/")
async def root():
    logger.info("Received request at /")
    return {"message": "Hello from FastAPI"}
```

### `requirements.txt`
```
fastapi==0.115.0
uvicorn==0.30.6
python-json-logger==2.0.7
```

### `backend.Dockerfile`
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Build and load:
```bash
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest
```

---

## ☸️ Kubernetes Manifests

### `backend-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: backend:latest
          imagePullPolicy: Never
          ports:
            - containerPort: 8000
```

### `backend-nodeport.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-nodeport
spec:
  type: NodePort
  selector:
    app: backend
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30000
```

### `ingress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: backend-nodeport
                port:
                  number: 8000
```

### `ingress-nodeport.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller-nodeport
  namespace: ingress-nginx
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
  ports:
    - port: 8080
      targetPort: 80
      nodePort: 30808
      name: http
```

### `k8s-proxy` (NGINX Reverse Proxy)
```nginx
server {
    listen 80;
    server_name 35.224.185.200;

    location / {
        proxy_pass http://192.168.49.2:30808;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```


Run yaml files


```sh
#!/bin/bash
set -e

minikube start --driver=docker --memory=10192 --cpus=6 

docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest

kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-nodeport.yaml

minikube addons enable ingress

while [[ $(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.containerStatuses[0].ready}') != "true" ]]; do
  echo "   ➤ Waiting for ingress-nginx-controller..."
  sleep 5
done
```

Run ngnix and ingress config

```bash
kubectl apply -f ingress.yaml
kubectl apply -f ingress-nodeport.yaml
sudo apt update -y
sudo apt install -y nginx
sudo cp ./k8s-proxy /etc/nginx/sites-available/k8s-proxy
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

echo "✅ Deployment complete!"
echo "🌍 Test your API externally:"
echo "curl http://35.224.185.200"
```



---

## ✅ Verify Setup
```bash
kubectl get pods -l app=backend -o wide
kubectl get svc -n ingress-nginx
kubectl get ingress
curl http://35.224.185.200
```

Expected Output:
```json
{"message": "Hello from FastAPI"}
```

---


