# Production-Grade Kubernetes Setup for FastAPI Backend with NGINX Ingress

This project deploys a FastAPI backend on a Minikube cluster (bare-metal Kubernetes) on a GCP instance (external IP: 35.224.185.200). It uses NGINX Ingress for routing and a host-level NGINX reverse proxy for persistent external access without `kubectl port-forward`, mimicking production-grade bare-metal setups.

## Prerequisites
- GCP instance with all ports allowed in firewall (80, 30808).
- Minikube, Docker, kubectl, and NGINX installed:
  ```bash
  sudo apt update
  sudo apt install -y nginx
  ```
- Minikube cluster running with Docker driver:
  ```bash
  minikube start --driver=docker --memory=5120 --cpus=5 --listen-address=0.0.0.0
  ```

## Files and Setup

### Backend FastAPI Application
`main.py`: FastAPI app serving a simple endpoint.
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

`requirements.txt`: Dependencies.
```text
fastapi==0.115.0
uvicorn==0.30.6
python-json-logger==2.0.7
```

`backend.Dockerfile`: Docker image for backend.
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Build and Load Backend Image
```bash
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest
```

### Backend Deployment
`backend-deployment.yaml`: Deploys 3 backend pods.
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

Apply: `kubectl apply -f backend-deployment.yaml`

### Backend Service
`backend-nodeport.yaml`: Exposes backend internally.
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

Apply: `kubectl apply -f backend-nodeport.yaml`

### NGINX Ingress
Enable NGINX Ingress controller:
```bash
minikube addons enable ingress
```

Wait for the controller pod to be ready (1/1):
```bash
kubectl get pods -n ingress-nginx -w
```

`ingress.yaml`: Routes traffic to backend.
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

Apply: `kubectl apply -f ingress.yaml`

`ingress-nodeport.yaml`: Exposes Ingress controller on NodePort 30808.
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

Apply: `kubectl apply -f ingress-nodeport.yaml`

### Host NGINX Reverse Proxy
Configure NGINX on the GCP instance to proxy `35.224.185.200:80` to Minikube’s Ingress NodePort (`192.168.49.2:30808`).

Create `/etc/nginx/sites-available/k8s-proxy`:
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

Enable and restart NGINX:
```bash
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### Verify Setup
Check pods, services, and Ingress:
```bash
kubectl get pods -l app=backend -o wide
kubectl get svc -n ingress-nginx
kubectl get ingress
```

Test external access (expect: `{"message":"Hello from FastAPI"}`):
```bash
curl http://35.224.185.200
```

## Notes
- **Why NGINX Reverse Proxy?** Minikube’s Docker driver binds NodePorts to `127.0.0.1` or internal IPs (192.168.49.2). The host NGINX reverse proxy routes traffic from `35.224.185.200:80` to `192.168.49.2:30808`, providing persistent access without `port-forward`.
- **Production Considerations**: In a true production bare-metal setup, use MetalLB for LoadBalancer services or a hardware load balancer. For GCP, consider GKE with a cloud LoadBalancer.
- **Frontend**: Can be added with a similar Dockerized setup and Ingress routing.

## Troubleshooting
- If `curl http://35.224.185.200` fails, verify NGINX:
  ```bash
  sudo nginx -t
  sudo systemctl status nginx
  ```
- Test internal Ingress: `curl http://192.168.49.2:30808`
- Check Ingress pod logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`