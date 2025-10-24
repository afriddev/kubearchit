##  Production-Grade Kubernetes Stack (FastAPI + ELK + Prometheus + Grafana + Cluster Monitoring)

This project deploys a complete Kubernetes observability stack using:
- FastAPI backend with Prometheus metrics and JSON logs
- Elasticsearch + Logstash for centralized logging (ELK)
- Prometheus + Grafana for metrics visualization
- Node Exporter, Kube-State-Metrics, and cAdvisor for full node and cluster insights
- NGINX ingress and reverse proxy for public access


##  Prerequisites

- GCP VM: ≥ 30 GB disk, ports 80 and 30808 open
- Tools:
  ```bash
  sudo apt update
  sudo apt install -y docker.io kubectl minikube nginx
  ```
- Start Minikube:
  ```bash
  minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=40g --listen-address=0.0.0.0
  ```


##  FastAPI Backend

### main.py
```python
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import logging
from pythonjsonlogger import jsonlogger
import socket

app = FastAPI()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logstash_handler = logging.StreamHandler(socket.socket(socket.AF_INET, socket.SOCK_STREAM))
logstash_handler.socket.connect(('logstash', 5044))
formatter = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(message)s')
logstash_handler.setFormatter(formatter)
logger.addHandler(logstash_handler)
Instrumentator().instrument(app).expose(app)

@app.get("/")
async def root():
    logger.info("Request received at /")
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


##  Kubernetes Manifests

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


## Elasticsearch

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


## Logstash

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


##  Prometheus

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
      - job_name: 'node-exporter'
        static_configs:
          - targets: ['node-exporter.monitoring.svc.cluster.local:9100']
      - job_name: 'kube-state-metrics'
        static_configs:
          - targets: ['kube-state-metrics.kube-system.svc.cluster.local:8080']
      - job_name: 'cadvisor'
        static_configs:
          - targets: ['cadvisor.kube-system.svc.cluster.local:8080']
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


##  Grafana

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


## Node Exporter

### node-exporter.yaml
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      containers:
      - name: node-exporter
        image: quay.io/prometheus/node-exporter:latest
        ports:
        - containerPort: 9100
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    app: node-exporter
  ports:
  - port: 9100
    targetPort: 9100
```


##  Kube-State-Metrics

### kube-state-metrics.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube-state-metrics
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      serviceAccountName: default
      containers:
      - name: kube-state-metrics
        image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.17.0
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  selector:
    app: kube-state-metrics
  ports:
  - port: 8080
    targetPort: 8080
```


##  cAdvisor

### cadvisor.yaml
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: cadvisor
  template:
    metadata:
      labels:
        name: cadvisor
    spec:
      hostNetwork: true
      containers:
      - name: cadvisor
        image: gcr.io/cadvisor/cadvisor:v0.39.3
        ports:
        - containerPort: 8080
```


## Ingress

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
```


## NGINX Reverse Proxy

### k8s-proxy
```nginx
server {
    listen 80;
    server_name 35.224.185.200;

    location /grafana {
        proxy_pass http://192.168.49.2:30808/grafana;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        proxy_pass http://192.168.49.2:30808;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```


## Automation Scripts

### run_full_stack.sh
```bash
#!/bin/bash
set -e

echo " Cleaning old setup..."
minikube delete --all --purge || true
docker system prune -a -f || true

echo " Starting Minikube..."
minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=40g --listen-address=0.0.0.0

echo " Building FastAPI image..."
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest

echo " Enabling Ingress..."
minikube addons enable ingress
kubectl create namespace ingress-nginx || true
kubectl create namespace monitoring || true

echo " Deploying services..."
kubectl apply -f prometheus-rbac.yaml
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
kubectl apply -f node-exporter.yaml
kubectl apply -f kube-state-metrics.yaml
kubectl apply -f cadvisor.yaml

echo "Waiting for Ingress controller and admission webhook..."
kubectl wait --for=condition=available --timeout=180s deployment/ingress-nginx-controller -n ingress-nginx || true
kubectl wait --for=condition=available --timeout=180s deployment/ingress-nginx-admission -n ingress-nginx || true
sleep 10

echo " Applying Ingress configs..."
kubectl apply -f unified-ingress.yaml
kubectl apply -f ingress-nodeport.yaml

echo " Waiting for main deployments..."
kubectl wait --for=condition=available --timeout=300s deployment/backend-deployment || true
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch || true
kubectl wait --for=condition=available --timeout=300s deployment/logstash || true
kubectl wait --for=condition=available --timeout=300s deployment/prometheus || true
kubectl wait --for=condition=available --timeout=300s deployment/grafana || true

echo " Configuring NGINX reverse proxy..."
sudo apt update -y
sudo apt install -y nginx
sudo cp ./k8s-proxy /etc/nginx/sites-available/k8s-proxy
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

MINIKUBE_IP=$(minikube ip || echo "192.168.49.2")

echo  Deployment complete!"
echo "Backend: http://$MINIKUBE_IP:30808/ or http://35.224.185.200/"
echo "Grafana: http://$MINIKUBE_IP:30808/grafana or http://35.224.185.200/grafana"
echo "Grafana login: admin / admin"
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
```

---
## Grafana Data Source Configuration

After deploying the full stack, configure Grafana to connect to Prometheus (metrics) and Elasticsearch (logs).

###  Prometheus Data Source

**Steps:**
1. Go to:  **→ Data Sources → Add data source → Prometheus**  
2. Set **URL:** `http://prometheus:9090`  
3. Click **Save & Test**


###  Elasticsearch (Logstash) Data Source
**Steps:**
1. Add new data source → **Elasticsearch**  
2. Set **URL:** `http://elasticsearch:9200`  
3. Set **Index name:** `fastapi-logs-*`  
4. Set **Time field name:** `@timestamp`  
5. Click **Save & Test**

 This connects **Prometheus** (metrics) and **Elasticsearch via Logstash** (logs) to Grafana.



## Grafana Dashboards

| Dashboard | ID | Description |
|------------|----|-------------|
| 1860 | Node Exporter Full |
| 6417 | Kubernetes Cluster Monitoring |
| 315 | Cluster Overview |

---

## Access Points

| Service | URL |
|----------|-----|
| FastAPI | http://35.224.185.200/ |
| Grafana | http://35.224.185.200/grafana |
| Prometheus | Internal |
| Elasticsearch | http://elasticsearch:9200 |
| Logstash | logstash:5044 |

