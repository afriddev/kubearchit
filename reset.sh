#!/bin/bash
set -e

echo "🧹 Stopping and deleting Minikube..."
minikube stop || true
minikube delete --all --purge || true

echo "🧼 Removing all Docker containers and images..."
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker rmi -f $(docker images -q) 2>/dev/null || true
docker system prune -af --volumes -f || true

echo "🗑️ Cleaning leftover Kubernetes configs..."
kubectl delete all --all -A 2>/dev/null || true
rm -rf ~/.kube ~/.minikube

echo "✅ System fully cleaned. Ready for fresh deployment."