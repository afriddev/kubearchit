#!/bin/bash
set -e

# Define project directory
PROJECT_DIR=~/kubearchit

# Create project directory if it doesn't exist
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Function to create a file with content
create_file() {
  local file="$1"
  local content="$2"
  echo "Creating $file..."
  echo "$content" > "$file"
  chmod 644 "$file"  # Set read/write permissions for owner, read for others
}

# Function to create an executable script
create_executable() {
  local file="$1"
  local content="$2"
  echo "Creating $file..."
  echo "$content" > "$file"
  chmod 755 "$file"  # Set executable permissions
}

# File: main.py
create_file "main.py" 'from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import logging
from pythonjsonlogger import jsonlogger
import logging.handlers
import time

app = FastAPI()

# Configure logger for Logstash
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Attempt to connect to Logstash with retries
def setup_logstash_handler():
    for _ in range(5):  # Retry 5 times
        try:
            logstash_handler = logging.handlers.SocketHandler("logstash", 5044)
            formatter = jsonlogger.JsonFormatter("%(asctime)s %(levelname)s %(message)s")
            logstash_handler.setFormatter(formatter)
            logger.addHandler(logstash_handler)
            logger.info("Connected to Logstash")
            return
        except Exception as e:
            logger.warning(f"Failed to connect to Logstash: {e}")
            time.sleep(2)  # Wait before retrying
    logger.error("Could not connect to Logstash after retries")

setup_logstash_handler()

# Enable Prometheus metrics
Instrumentator().instrument(app).expose(app)

@app.get("/")
async def root():
    logger.info("Received request at /")
    return {"message": "Hello from FastAPI"}'

# File: requirements.txt
create_file "requirements.txt" 'fastapi==0.115.0
uvicorn==0.30.6
python-json-logger==2.0.7
prometheus-fastapi-instrumentator==6.0.0'

# File: backend.Dockerfile
create_file "backend.Dockerfile" 'FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]'

# File: backend-deployment.yaml
create_file "backend-deployment.yaml" 'apiVersion: apps/v1
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
              cpu: "500m"'

# File: backend-service.yaml
create_file "backend-service.yaml" 'apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
    - port: 8000
      targetPort: 8000'

# File: backend-nodeport.yaml
create_file "backend-nodeport.yaml" 'apiVersion: v1
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
      nodePort: 30000'

# File: unified-ingress.yaml
create_file "unified-ingress.yaml" 'apiVersion: networking.k8s.io/v1
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
                  number: 8000'

# File: ingress-nodeport.yaml
create_file "ingress-nodeport.yaml" 'apiVersion: v1
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
      name: http'

# File: elasticsearch-deployment.yaml
create_file "elasticsearch-deployment.yaml" 'apiVersion: apps/v1
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
              cpu: "1"'

# File: elasticsearch-service.yaml
create_file "elasticsearch-service.yaml" 'apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
spec:
  type: ClusterIP
  selector:
    app: elasticsearch
  ports:
    - port: 9200
      targetPort: 9200'

# File: logstash-pipeline-config.yaml
create_file "logstash-pipeline-config.yaml" 'apiVersion: v1
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
    }'

# File: logstash-deployment.yaml
create_file "logstash-deployment.yaml" 'apiVersion: apps/v1
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
            name: logstash-pipeline'

# File: logstash-service.yaml
create_file "logstash-service.yaml" 'apiVersion: v1
kind: Service
metadata:
  name: logstash
spec:
  type: ClusterIP
  selector:
    app: logstash
  ports:
    - port: 5044
      targetPort: 5044'

# File: prometheus-config.yaml
create_file "prometheus-config.yaml" 'apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 10s
    scrape_configs:
      - job_name: '"'"'kubernetes-pods'"'"'
        kubernetes_sd_configs:
          - role: pod
        authorization:
          credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      - job_name: '"'"'fastapi'"'"'
        metrics_path: /metrics
        static_configs:
          - targets: ['"'"'backend-service:8000'"'"']'

# File: prometheus-deployment.yaml
create_file "prometheus-deployment.yaml" 'apiVersion: apps/v1
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
      serviceAccountName: prometheus
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
            name: prometheus-config'

# File: prometheus-service.yaml
create_file "prometheus-service.yaml" 'apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  type: ClusterIP
  selector:
    app: prometheus
  ports:
    - port: 9090
      targetPort: 9090'

# File: prometheus-rbac.yaml
create_file "prometheus-rbac.yaml" 'apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: default
roleRef:
  kind: ClusterRole
  name: prometheus
  apiGroup: rbac.authorization.k8s.io'

# File: grafana-deployment.yaml
create_file "grafana-deployment.yaml" 'apiVersion: apps/v1
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
              cpu: "500m"'

# File: grafana-service.yaml
create_file "grafana-service.yaml" 'apiVersion: v1
kind: Service
metadata:
  name: grafana
spec:
  type: ClusterIP
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000'

# File: k8s-proxy
create_file "k8s-proxy" 'server {
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
}'

# File: run_full_stack.sh
create_executable "run_full_stack.sh" '#!/bin/bash
set -e

# Clean up
minikube delete --all --purge || true
docker system prune -a -f || true

# Start Minikube
minikube start --driver=docker --memory=8192 --cpus=6 --disk-size=40g --listen-address=0.0.0.0

# Build and load FastAPI image
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest

# Apply manifests (excluding ingress-nodeport.yaml for now)
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
kubectl apply -f unified-ingress.yaml

# Enable Ingress and wait for ingress-nginx namespace
minikube addons enable ingress
echo "Waiting for ingress-nginx namespace to be created..."
until kubectl get namespace ingress-nginx >/dev/null 2>&1; do
    sleep 2
done
echo "ingress-nginx namespace created."

# Apply ingress-nodeport.yaml
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
echo "Elasticsearch (internal): http://elasticsearch:9200"'

# File: reset_k8s.sh
create_executable "reset_k8s.sh" '#!/bin/bash
set -e

minikube delete --all --purge || true
docker system prune -a -f || true
sudo rm -rf ~/.minikube ~/.kube || true
sudo systemctl stop nginx || true
sudo rm -f /etc/nginx/sites-enabled/k8s-proxy /etc/nginx/sites-available/k8s-proxy || true
echo "Reset complete"'

echo "All files created in $PROJECT_DIR"
ls -l