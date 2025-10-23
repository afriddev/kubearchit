#!/bin/bash
set -e

echo "🚀 Starting Minikube..."
minikube start --driver=docker --memory=5120 --cpus=5 --listen-address=0.0.0.0

echo "🐳 Building and loading backend image..."
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest

echo "📦 Deploying backend..."
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-nodeport.yaml

echo "⚙️ Enabling Ingress..."
minikube addons enable ingress
kubectl wait --for=condition=ready pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --timeout=120s

kubectl apply -f ingress.yaml
kubectl apply -f ingress-nodeport.yaml

echo "🌐 Configuring NGINX host reverse proxy..."
sudo apt update -y
sudo apt install -y nginx
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

echo "✅ All components deployed successfully!"
echo "🌍 Test your API:"
echo "curl http://35.224.185.200"
