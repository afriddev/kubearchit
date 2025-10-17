# 🧩 Kubernetes Architecture

## 1. Overview
This architecture represents a **Kubernetes cluster** created using **Minikube** with **Docker** as the container runtime.  
It demonstrates the deployment of two core applications — **Elasticsearch (DB)** and **Grafana (UI)** — with all services exposed using **ClusterIP** inside the cluster.

---

## 2. Tech Stack

| Component | Purpose |
|------------|----------|
| **Minikube** | To manage the Kubernetes cluster locally. |
| **kubectl** | CLI tool used to communicate with the Kubernetes API. |
| **Docker** | Container engine to run application pods. |
| **Elasticsearch** | Acts as a database to store log and metric data. |
| **Grafana** | Used for visualizing data from Elasticsearch. |

---

## 3. Cluster Structure

| Node Type | Description |
|------------|--------------|
| **Master Node** | Controls and manages the cluster through the API and control plane. |
| **Worker Node 1** | Runs the deployed applications (Grafana and Elasticsearch). |

---

## 4. Services in the Cluster
All components are deployed inside the cluster using **ClusterIP Services**, which enable internal communication between applications.

| Service Type | Description |
|---------------|--------------|
| **ClusterIP Service** | Internal network service for pod-to-pod communication. |
| **ConfigMap Service** | Stores non-sensitive configuration data for applications. |
| **Secrets Service** | Stores sensitive credentials like passwords and tokens. |

---

## 5. Application Deployments

### APP-1 → Elasticsearch (Database Service)
- **Deployment Type:** Stateless Deployment  
- **Service Type:** ClusterIP  
- **Purpose:** Acts as a log and metrics database.  
- **Configuration:**
  - Connected to ConfigMap for environment data (e.g., paths, ports).
  - Connected to Secrets for authentication.
  - Deployed as multiple replicas (pods) for load balancing.
- **Flow:**
  - Deployment creates identical pod copies (Code A).
  - Each pod communicates internally via the ClusterIP service.
  - Data stored in container filesystem (no persistent volume used).

### APP-2 → Grafana (Visualization Service)
- **Deployment Type:** Standard Deployment  
- **Service Type:** ClusterIP  
- **Purpose:** Visualizes data from Elasticsearch.  
- **Configuration:**
  - Uses ConfigMap for environment variables (Elasticsearch endpoint, dashboard config).
  - Uses Secrets for credentials (admin username, password).
- **Flow:**
  - Deployment service manages replicas of Grafana pods.
  - Grafana connects internally to Elasticsearch using the ClusterIP endpoint.
  - Exposed internally to other pods; external access via port forwarding if needed.

---

## 6. Internal Service Flow

1. User interacts through `kubectl` or port-forward to access Grafana UI.  
2. Kubernetes API schedules the deployments on Worker Node 1.  
3. Deployment Service manages replica pods for both applications.  
4. Pods fetch required environment values from ConfigMap and credentials from Secrets.  
5. Grafana Pods communicate internally with Elasticsearch Pods via ClusterIP Service.  
6. All inter-pod traffic remains internal within the cluster network.  

---

## 7. Architecture Representation (as per diagram)

### Master Node
- Control Plane  
- API  
- ETCD  

### Worker Node 1
- **Applications:**
  - APP-1 (Elasticsearch) — Stateless DB Deployment  
  - APP-2 (Grafana) — UI Visualization Deployment  
- **Core Components:**
  - Deployment Service (manages Pods)  
  - ConfigMap Service (non-sensitive configs)  
  - Secrets Service (credentials & tokens)  
  - Stateless Service (for DB behavior)  
  - ClusterIP Service (for internal traffic routing)

---

## 🧾 Summary
- The Kubernetes cluster can be scaled horizontally by **adding more nodes and pods** based on system load and available resources.  
- If **one node fails**, Kubernetes automatically **shifts the workload** to another active node to maintain application availability.  
- If **one pod fails**, the **Deployment controller** automatically **recreates or restarts** a new pod instance to ensure service continuity.  
- The number of **pod replicas** can be increased or decreased dynamically according to **traffic, performance, and resource usage**.  
- This ensures the cluster remains **fault-tolerant, self-healing, and load-balanced** at all times.
