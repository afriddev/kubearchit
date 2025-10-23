#!/bin/bash
set -e

echo "🚀 Starting Minikube..."
minikube start --driver=docker --memory=10192 --cpus=6 --listen-address=0.0.0.0

echo "🐳 Building and loading backend image..."
docker build -t backend:latest -f backend.Dockerfile .
minikube image load backend:latest

echo "📦 Deploying backend..."
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-nodeport.yaml

echo "⚙️ Enabling Ingress..."
minikube addons enable ingress

echo "⏳ Waiting for Ingress controller to be ready..."
while [[ $(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.containerStatuses[0].ready}') != "true" ]]; do
  echo "   ➤ Waiting for ingress-nginx-controller..."
  sleep 5
done

echo "📄 Applying ingress configs..."
kubectl apply -f ingress.yaml
kubectl apply -f ingress-nodeport.yaml

echo "🌐 Installing and configuring NGINX..."
sudo apt update -y
sudo apt install -y nginx

echo "🧩 Linking your k8s-proxy config..."
sudo cp ./k8s-proxy /etc/nginx/sites-available/k8s-proxy
sudo ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

echo "✅ Deployment complete!"
echo "🌍 Test your API externally:"
echo "curl http://35.224.185.200"
