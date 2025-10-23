# 🚀 Production-Grade Kubernetes Stack (FastAPI + Elasticsearch + Logstash + Prometheus + Grafana)

This guide sets up a **full production-like Kubernetes environment** with:
- 🧩 **FastAPI** backend
- 🔍 **Elasticsearch** for logs storage
- ⚙️ **Logstash** for log aggregation
- 📊 **Prometheus** for metrics collection
- 🎨 **Grafana** for visualization (UI exposed via Ingress)
- 🌐 **NGINX reverse proxy** for external routing (no `port-forward`)

---

## ⚙️ Prerequisites

- GCP VM (>= 30 GB disk recommended)
- Ports open: **80**, **30808**
- Installed:
  ```bash
  sudo apt update
  sudo apt install -y docker.io kubectl minikube nginx
  ```

Start Minikube:
```bash
minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=30g
```

---

## 🧠 FastAPI Backend

### main.py
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

### requirements.txt
```
fastapi==0.115.0
uvicorn==0.30.6
python-json-logger==2.0.7
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
          ports:
            - containerPort: 5044
          volumeMounts:
            - name: logstash-pipeline
              mountPath: /usr/share/logstash/pipeline
      volumes:
        - name: logstash-pipeline
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
      - job_name: 'fastapi'
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
            - name: prometheus-config
              mountPath: /etc/prometheus/
      volumes:
        - name: prometheus-config
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
          ports:
            - containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              value: admin
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: admin
            - name: GF_SERVER_ROOT_URL
              value: http://35.224.185.200/grafana
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

### grafana-ingress.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
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
```

---

## 🌐 NGINX Reverse Proxy (Host Level)

### /etc/nginx/sites-available/k8s-proxy
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

    location /grafana {
        proxy_pass http://192.168.49.2:30808/grafana;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable & reload:
```bash
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## ✅ Access Points

| Service | Type | URL |
|----------|------|-----|
| FastAPI Backend | Ingress | http://35.224.185.200/ |
| Grafana UI | Ingress | http://35.224.185.200/grafana |
| Elasticsearch | Internal | http://elasticsearch:9200 |
| Logstash | Internal | logstash:5044 |
| Prometheus | Internal | http://prometheus:9090 |

---

## 🧩 Final Notes
- Default Grafana login: **admin / admin**
- Add Prometheus: `http://prometheus:9090`
- Add Elasticsearch: `http://elasticsearch:9200`
- Works on bare-metal (Minikube + GCP) with no port-forwarding.
