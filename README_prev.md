# 🚀 Production-Grade Kubernetes Stack (FastAPI + ELK + Prometheus + Grafana)

This README provides all files and instructions to deploy a production-like Kubernetes stack on Minikube, including:
- 🧩 **FastAPI** backend with JSON logging and Prometheus metrics
- 🔍 **Elasticsearch** for log storage
- ⚙️ **Logstash** for log aggregation
- 📊 **Prometheus** for metrics collection
- 🎨 **Grafana** for visualization
- 🌐 **NGINX reverse proxy** for external access (no port-forwarding)

The stack is exposed via a unified Ingress and a host-level NGINX proxy on a GCP VM.

---

## ⚙️ Prerequisites

- **GCP VM**: >= 30 GB disk, ports `80` and `30808` open
- **Tools**:
  ```bash
  sudo apt update
  sudo apt install -y docker.io kubectl minikube nginx
  ```
- **Minikube Setup**:
  ```bash
  minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=40g --listen-address=0.0.0.0
  ```

---

## 📋 Files Index

Create these files in your project root:
- `main.py`
- `requirements.txt`
- `backend.Dockerfile`
- `backend-deployment.yaml`
- `backend-service.yaml`
- `backend-nodeport.yaml`
- `unified-ingress.yaml`
- `ingress-nodeport.yaml`
- `elasticsearch-deployment.yaml`
- `elasticsearch-service.yaml`
- `logstash-pipeline-config.yaml`
- `logstash-deployment.yaml`
- `logstash-service.yaml`
- `prometheus-config.yaml`
- `prometheus-deployment.yaml`
- `prometheus-service.yaml`
- `grafana-deployment.yaml`
- `grafana-service.yaml`
- `k8s-proxy`
- `run_full_stack.sh`
- `reset_k8s.sh`
- `README.md` (this file)

---

## 🧠 FastAPI Backend

### main.py
```python
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import logging
from pythonjsonlogger import jsonlogger
import socket

app = FastAPI()

# Configure logger for Logstash
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logstash_handler = logging.StreamHandler(socket.socket(socket.AF_INET, socket.SOCK_STREAM))
logstash_handler.socket.connect(('logstash', 5044))  # Connect to Logstash service
formatter = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(message)s')
logstash_handler.setFormatter(formatter)
logger.addHandler(logstash_handler)

# Enable Prometheus metrics
Instrumentator().instrument(app).expose(app)

@app.get("/")
async def root():
    logger.info("Received request at /")
    return {"message": "Hello from FastAPI"}
```

### requirements.txt
```
fastapi==0.115.0
uvicorn==0.30.6
python-json-logger==2.0.7
prometheus-fastapi-instrumentator==6.0.0
```

### backend.Dockerfile
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 🛠️ Kubernetes Manifests

### backend-deployment.yaml
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
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
```

### backend-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
    - port: 8000
      targetPort: 8000
```

### backend-nodeport.yaml
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

---

## 🌐 Ingress

### unified-ingress.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: unified-ingress
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  rules:
    - http:
        paths:
          - path: /grafana
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
          - path: /
            pathType: Prefix
            backend:
              service:
                name: backend-service
                port:
                  number: 8000
```

### ingress-nodeport.yaml
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
    - port: 80
      targetPort: 80
      nodePort: 30808
      name: http
```

---

## 🎨 Grafana

### grafana-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:10.4.2
          env:
            - name: GF_SECURITY_ADMIN_USER
              value: admin
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: admin
            - name: GF_SERVER_ROOT_URL
              value: /grafana
            - name: GF_SERVER_SERVE_FROM_SUB_PATH
              value: "true"
          ports:
            - containerPort: 3000
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

### grafana-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
spec:
  type: ClusterIP
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
```

---

## 🔍 Elasticsearch

### elasticsearch-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
        - name: elasticsearch
          image: docker.elastic.co/elasticsearch/elasticsearch:8.10.2
          ports:
            - containerPort: 9200
          env:
            - name: discovery.type
              value: single-node
            - name: xpack.security.enabled
              value: "false"
            - name: xpack.security.http.ssl.enabled
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms1g -Xmx1g"
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "1"
```

### elasticsearch-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
spec:
  type: ClusterIP
  selector:
    app: elasticsearch
  ports:
    - port: 9200
      targetPort: 9200
```

---

## ⚙️ Logstash

### logstash-pipeline-config.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-pipeline
data:
  logstash.conf: |
    input {
      tcp {
        port => 5044
        codec => json_lines
      }
    }
    output {
      elasticsearch {
        hosts => ["http://elasticsearch:9200"]
        index => "fastapi-logs-%{+YYYY.MM.dd}"
      }
    }
```

### logstash-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      containers:
        - name: logstash
          image: docker.elastic.co/logstash/logstash:8.10.2
          env:
            - name: LS_JAVA_OPTS
              value: "-Xms256m -Xmx256m"
          ports:
            - containerPort: 5044
          volumeMounts:
            - name: pipeline
              mountPath: /usr/share/logstash/pipeline
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: pipeline
          configMap:
            name: logstash-pipeline
```

### logstash-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: logstash
spec:
  type: ClusterIP
  selector:
    app: logstash
  ports:
    - port: 5044
      targetPort: 5044
```

---

## 📊 Prometheus

### prometheus-config.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 10s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
      - job_name: 'fastapi'
        metrics_path: /metrics
        static_configs:
          - targets: ['backend-service:8000']
```

### prometheus-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:v2.53.1
          args:
            - "--config.file=/etc/prometheus/prometheus.yml"
          ports:
            - containerPort: 9090
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: prometheus-config
```

### prometheus-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  type: ClusterIP
  selector:
    app: prometheus
  ports:
    - port: 9090
      targetPort: 9090
```

---

## 🌐 Host NGINX Reverse Proxy

### k8s-proxy
Copy this to `/etc/nginx/sites-available/k8s-proxy` on the host VM.

```nginx
server {
    listen 80;
    server_name 35.224.185.200;

    location /grafana {
        proxy_pass http://192.168.49.2:30808/grafana;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://192.168.49.2:30808;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Notes**:
- Replace `192.168.49.2` with the Minikube IP (`minikube ip`) if different.
- Port `30808` matches `ingress-nodeport.yaml`.

---

## 🤖 Automation Scripts

### run_full_stack.sh
```bash
#!/bin/bash
set -e

# Clean up
minikube delete --all --purge || true
docker system prune -a -f || true

# Start Minikube
minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=40g --listen-address=0.0.0.0

# Build and load FastAPI image
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest
# Enable Ingress
minikube addons enable ingress
kubectl create namespace ingress-nginx

# Apply manifests
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f backend-nodeport.yaml
kubectl apply -f elasticsearch-deployment.yaml
kubectl apply -f elasticsearch-service.yaml
kubectl apply -f logstash-pipeline-config.yaml
kubectl apply -f logstash-deployment.yaml
kubectl apply -f logstash-service.yaml
kubectl apply -f prometheus-config.yaml
kubectl apply -f prometheus-deployment.yaml
kubectl apply -f prometheus-service.yaml
kubectl apply -f grafana-deployment.yaml
kubectl apply -f grafana-service.yaml
kubectl apply -f unified-ingress.yaml
kubectl apply -f ingress-nodeport.yaml

# Wait for deployments to be ready
kubectl wait --for=condition=available --timeout=300s deployment/backend-deployment
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch
kubectl wait --for=condition=available --timeout=300s deployment/logstash
kubectl wait --for=condition=available --timeout=300s deployment/prometheus
kubectl wait --for=condition=available --timeout=300s deployment/grafana



# Configure host NGINX
sudo apt update -y
sudo apt install -y nginx
sudo cp ./k8s-proxy /etc/nginx/sites-available/k8s-proxy
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Print Minikube IP and access points
MINIKUBE_IP=$(minikube ip)
echo "Deployment complete. Access points:"
echo "Backend: http://$MINIKUBE_IP:30808/ or http://35.224.185.200/"
echo "Grafana: http://$MINIKUBE_IP:30808/grafana or http://35.224.185.200/grafana"
echo "Grafana login: admin/admin"
echo "Prometheus (internal): http://prometheus:9090"
echo "Elasticsearch (internal): http://elasticsearch:9200"
```

### reset_k8s.sh
```bash
#!/bin/bash
set -e

minikube delete --all --purge || true
docker system prune -a -f || true
sudo rm -rf ~/.minikube ~/.kube || true
sudo systemctl stop nginx || true
sudo rm -f /etc/nginx/sites-enabled/k8s-proxy /etc/nginx/sites-available/k8s-proxy || true
echo "Reset complete"
```

---

## ✅ How to Apply

1. Save each code block into the respective files in your project root.
2. Make scripts executable:
   ```bash
   chmod +x run_full_stack.sh reset_k8s.sh
   ```
3. Run the deployment:
   ```bash
   ./run_full_stack.sh
   ```

---

## 📊 Access Points

| Service         | Type      | URL                          |
|-----------------|-----------|------------------------------|
| FastAPI Backend | Ingress   | http://35.224.185.200/       |
| Grafana UI      | Ingress   | http://35.224.185.200/grafana |
| Elasticsearch   | Internal  | http://elasticsearch:9200    |
| Logstash        | Internal  | logstash:5044                |
| Prometheus      | Internal  | http://prometheus:9090       |

**Grafana Login**: `admin/admin`

---

## 🛠️ Post-Deployment Setup

1. **Grafana Configuration**:
   - Access Grafana at `http://35.224.185.200/grafana`.
   - Add Prometheus as a data source: `http://prometheus:9090`.
   - Add Elasticsearch as a data source: `http://elasticsearch:9200`, index `fastapi-logs-*`.
   - Create dashboards for FastAPI metrics (e.g., request count) and logs.

2. **Verify Metrics**:
   - Check Prometheus at `http://prometheus:9090` (internal) to confirm FastAPI metrics (`/metrics` endpoint).

3. **Verify Logs**:
   - Query Elasticsearch at `http://elasticsearch:9200/fastapi-logs-*/_search` to verify logs from FastAPI.

---

## 🩺 Troubleshooting

- **Minikube Disk Full**:
  ```bash
  docker system prune -a -f
  minikube delete
  ```
  Increase GCP VM disk size if needed.

- **Grafana Redirect Issues**:
  Ensure `GF_SERVER_ROOT_URL=/grafana` and `GF_SERVER_SERVE_FROM_SUB_PATH=true` in `grafana-deployment.yaml`. Remove any `rewrite-target` annotations in `unified-ingress.yaml`.

- **Ingress Not Working**:
  Verify Minikube IP:
  ```bash
  minikube ip
  ```
  Update `k8s-proxy` with the correct IP if `192.168.49.2` is incorrect.

- **Pod Issues**:
  Check logs:
  ```bash
  kubectl logs -l app=backend
  kubectl logs -l app=grafana
  kubectl logs -l app=prometheus
  kubectl logs -l app=elasticsearch
  kubectl logs -l app=logstash
  ```

- **NGINX Errors**:
  Test configuration:
  ```bash
  sudo nginx -t
  ```

---

## 🧩 Notes

- The stack uses `unified-ingress.yaml` for simplified routing.
- FastAPI logs are sent to Logstash in JSON format and stored in Elasticsearch.
- Prometheus scrapes FastAPI metrics at `/metrics`.
- All deployments include resource requests and limits for production readiness.
- The setup assumes a GCP VM with public IP `35.224.185.200`. Adjust `k8s-proxy` if using a different IP.