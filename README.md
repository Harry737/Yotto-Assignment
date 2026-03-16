# Yotto Multi-Tenant Website Hosting Platform

A complete DevOps solution for deploying and managing multiple isolated websites on Kubernetes with dynamic domain mapping, auto-scaling, CI/CD, and event-driven architecture.

## 🏗️ Architecture Overview

### Components

- **Kubernetes Cluster**: kind (local development) with 1 control-plane + 2 workers
- **Ingress Controller**: ingress-nginx for HTTP/HTTPS routing
- **TLS Termination**: cert-manager with self-signed CA certificates
- **Container Registry**: Docker Hub
- **GitOps**: ArgoCD for declarative deployments
- **CI/CD**: GitHub Actions with self-hosted runner for build & push
- **Event Streaming**: Kafka with Docker Compose for deployment events
- **Observability**: Prometheus + Grafana for metrics and dashboards
- **Auto-Scaling**: Horizontal Pod Autoscaler (HPA) based on CPU/memory

### Multi-Tenancy Model

- **5 Tenants**: user1, user2, user3, user4, user5 (user4-5 created dynamically)
- **Isolation**: Each tenant has its own Kubernetes namespace with:
  - Network Policies (ingress-nginx → pod traffic only)
  - Resource Quotas (2 CPU, 2Gi memory per tenant)
  - Service accounts per namespace
- **Dynamic Tenant Creation**: Add new tenants via script without cluster redeploy
  - Example: `bash scripts/create-tenant.sh user6`
  - Takes ~2 minutes to deploy
  - Uses ApplicationSet list generator for GitOps

## 🚀 Quick Start

### Prerequisites

- Linux/macOS/WSL2 (Windows Subsystem for Linux 2)
- Docker & Docker Compose
- kubectl v1.29+
- Helm v3.14+
- kind v0.22+
- Git
- (Optional) GitHub account for CI/CD integration

### Bootstrap Cluster (5-10 minutes)

```bash
# 1. Clone the repository
git clone <repo-url> && cd Yotto-Assignment

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Bootstrap the entire platform (automated)
bash scripts/bootstrap.sh

# 4. Setup local DNS (requires sudo)
sudo bash scripts/setup-hosts.sh
```

The bootstrap script will:
- Create a kind cluster with 3 nodes (1 control-plane, 2 workers)
- Install ingress-nginx, cert-manager, metrics-server
- Create 5 tenant namespaces (user1-5) with resource quotas
- Install ArgoCD with ApplicationSet for GitOps
- Deploy all 5 tenants via Helm chart
- Start Kafka (Docker Compose) with topic initialization
- Install Prometheus + Grafana for monitoring

### Verify Deployment

```bash
# Check all resources across tenants
bash scripts/verify-deployment.sh

# Or manually - check all 5 tenants:
kubectl get all -n user1
kubectl get all -n user2
kubectl get all -n user3
kubectl get all -n user4
kubectl get all -n user5

# Check ApplicationSet status
kubectl get applicationset -n argocd
```

### Access Services (from WSL)

```bash
# Port-forward to access from Windows browser
# In WSL terminal, find your WSL IP:
wsl hostname -I

# Then forward services:
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443 --address 172.24.160.103 &
kubectl port-forward -n monitoring svc/grafana 3000:80 --address 172.24.160.103 &
kubectl port-forward -n argocd svc/argocd-server 6443:443 --address 172.24.160.103 &

# Test websites (add to hosts file: 127.0.0.1 user1.example.com, etc.)
curl -k https://user1.example.com

# Grafana Dashboard
# Visit: http://172.24.160.103:3000
# Login: admin / admin

# ArgoCD UI
# Visit: https://172.24.160.103:6443
# Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Watch HPA scaling
kubectl get hpa -n user1 -w
```

## 📊 Load Testing & Auto-Scaling

### Simulate High Traffic

```bash
# Run load test (requires 'hey' tool)
bash scripts/load-test.sh user1 5000 50
# Arguments: tenant, requests, concurrency
```

This will:
1. Send 5000 requests with 50 concurrent connections
2. Watch HPA metrics in real-time
3. Pod count should increase as CPU utilization exceeds 60%

### Monitor Scaling

```bash
# Watch HPA status (opens watch mode)
kubectl get hpa -n user1 -w

# In another terminal, watch pods scaling
kubectl get pods -n user1 -w

# Check current metrics
kubectl top pods -n user1
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

Triggered on `git push` to `main` branch:

1. **build-and-push**: Docker build + push to Docker Hub (tagged with git SHA)
2. **update-helm-values**: Dynamically update ALL values-*.yaml files with new tag (works for unlimited tenants)
3. **verify-deployment**: Wait for rollout, check pod readiness across all tenants
4. **rollback-on-failure**: Auto-rollback if verification fails, publish DeploymentRolledBack event
5. **Event publishing**: Publish DeploymentSucceeded event to Kafka with version info

### Setup GitHub Actions

```bash
# 1. Configure git repository
git remote add origin https://github.com/YOUR_ORG/YOUR_REPO.git

# 2. Add GitHub secrets
gh secret set DOCKERHUB_USERNAME -b "your-docker-username"
gh secret set DOCKERHUB_TOKEN -b "your-docker-token"

# 3. (Optional) Install self-hosted runner for local cluster integration
# See: https://docs.github.com/en/actions/hosting-your-own-runners
```

### Rollback Strategy

If deployment fails, the pipeline automatically:
1. Detects failure in deployment verification
2. Executes `helm rollback` to previous release
3. Publishes `DeploymentRolledBack` event to Kafka

**Manual rollback**:
```bash
helm rollback user1-website -n user1
```

## 🎯 Dynamic Tenant Creation & Domain Mapping

### Add a New Tenant (user4, user5, etc.)

**Simplest way** (recommended):

```bash
# Create new tenant in 2 minutes, zero downtime
bash scripts/create-tenant.sh user4

# What it does:
# 1. Creates values-user4.yaml
# 2. Adds user4 to ApplicationSet
# 3. Creates user4 namespace
# 4. Creates ResourceQuota
# 5. Pushes to git
# 6. Waits for ArgoCD sync
# 7. Verifies pods running
```

**Manual approach** (if you understand the flow):

```bash
# 1. Create new values file for new tenant
cp helm/tenant-website/values-user1.yaml helm/tenant-website/values-user4.yaml
# Edit: change tenantName, domain, image tag to match new tenant

# 2. Add tenant to ApplicationSet list
kubectl edit applicationset tenant-websites -n argocd
# Add: - tenant: user4 to the list

# 3. Create namespace and quota
kubectl create namespace user4
kubectl apply -f k8s/resource-quotas/user4-quota.yaml

# 4. Push to git (triggers ArgoCD sync)
git add helm/tenant-website/values-user4.yaml argocd/applicationset.yaml
git commit -m "feat: add user4 tenant"
git push origin main
```

### How Dynamic Domain Mapping Works

**Traditional approach** (❌ requires cluster redeploy):
- Hardcoded domains in Ingress
- Every new domain requires code change + redeploy
- Downtime and complexity

**Our approach** (✅ zero downtime):
1. ApplicationSet uses template: `{{.tenant}}.example.com`
2. No hardcoding - works for any tenant
3. Helm renders domain dynamically from values
4. Ingress created automatically
5. cert-manager provisions TLS cert
6. Service live in ~30 seconds after git push

See [docs/dynamic-domain-mapping.md](docs/dynamic-domain-mapping.md) for technical deep-dive.

## 📈 Observability & Monitoring

### Prometheus Metrics

The platform automatically collects:
- Pod CPU and memory usage
- HPA replica counts and scaling events
- Kubernetes node metrics
- HTTP request metrics from /metrics endpoint
- Prometheus self-monitoring

### Grafana Dashboards (4 Panels)

Pre-installed custom dashboard shows:
1. **HPA Current Replicas** - Shows scaling from 2 to 10 during load
2. **Memory Usage per Tenant** - Tracks baseline (~100-200MB) vs peak usage
3. **Pods per Tenant** - Visualizes replica scaling
4. **CPU Usage per Tenant** - Shows 0% baseline to 400%+ under load

**Access**: Grafana on http://172.24.160.103:3000
**Default login**: admin / admin

### Service Monitors

The platform uses Prometheus `ServiceMonitor` CRD for auto-discovery. Metrics are collected automatically without manual scrape config.

## 🔐 Security Features

### Network Isolation

Each tenant's pods can only:
- Accept traffic from ingress-nginx controller
- Communicate with other pods in same namespace
- Resolve DNS queries
- Connect to Kafka broker (port 9092)

**Enforced via**: NetworkPolicy resources

### Pod Security

- **Non-root user**: Runs as uid 1000 (node user)
- **Read-only filesystem**: Except /tmp
- **Dropped capabilities**: ALL (minimalist approach)
- **No privileged escalation**: allowPrivilegeEscalation=false

### Resource Limits

**Per Pod**:
- **CPU**: 500m (limit) / 100m (request)
- **Memory**: 512Mi (limit) / 128Mi (request)

**Per Namespace Quota**:
- **Total CPU**: 2 cores max
- **Total Memory**: 2Gi max
- **Pod limit**: 10 pods per namespace

**Enforced via**: ResourceQuota + LimitRange per namespace

### TLS Certificates

- Self-signed CA chain (cert-manager)
- Automatic cert issuance & renewal
- No external CA needed for demo

## 📝 Kafka Event Streaming

### Event Topics & Types

**Topic**: `website-events`

**Event Types Published**:
- **WebsiteCreated**: When pod starts, publishes from app
- **DeploymentTriggered**: CI/CD pipeline starts
- **DeploymentSucceeded**: After verify-deployment job (all pods ready)
- **DeploymentRolledBack**: When rollback-on-failure job executes

**Event Schema**:
```json
{
  "event": "DeploymentSucceeded",
  "tenant": "user1",
  "timestamp": "2026-03-16T10:30:00Z",
  "version": "sha-abc123def456"
}
```

### Verify Events

```bash
# Start consumer (in new terminal)
cd kafka/consumer
npm ci
node consumer.js

# Output: Listens for all events in real-time
# When deployment happens: "Event received: DeploymentSucceeded"
```

### Publish Events Manually

```bash
node kafka/consumer/notify.js \
  --event DeploymentSucceeded \
  --tenant user1 \
  --version sha-abc123def456
```

### Kafka Access

```bash
# Check Kafka is running
docker-compose -f kafka/docker-compose.yml ps

# Connect to Kafka broker: 172.17.0.1:9092 (from pods)
# From host: localhost:9092
```

## 🛠️ Troubleshooting

### Cluster not starting

```bash
# Check kind is installed
kind version

# Check cluster status
kind get clusters
kind describe cluster yotto-cluster

# Restart cluster
kind delete cluster --name yotto-cluster
bash scripts/bootstrap.sh
```

### Ingress not receiving traffic

```bash
# Check ingress-nginx pods
kubectl get pods -n ingress-nginx

# Check service NodePort mapping
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Verify port 80/443 mappings in kind nodes
docker ps | grep kind-control-plane
```

### HPA not scaling

```bash
# Check metrics-server is running
kubectl get deployment -n kube-system metrics-server

# Verify metrics are available
kubectl top pods -n user1

# Check HPA status
kubectl describe hpa user1-website -n user1
```

### Kafka not reachable from pods

```bash
# Check Kafka is running
docker-compose -f kafka/docker-compose.yml ps

# Get gateway IP for pods to reach Kafka
docker network inspect kind | grep Gateway

# Update Helm values if IP changed
# Edit: helm/tenant-website/values.yaml
# kafka.broker: "172.17.0.1:9092"

# Redeploy
helm upgrade user1-website ./helm/tenant-website -f values-user1.yaml -n user1
```

### ArgoCD not syncing

```bash
# Check ApplicationSet is created
kubectl get applicationsets -n argocd

# Check generated Applications
kubectl get applications -n argocd

# Manual sync
kubectl -n argocd patch app user1-website -p \
  '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' \
  --type merge

# Check sync status
kubectl describe app user1-website -n argocd
```

## 📚 Directory Structure

```
.
├── .github/workflows/ci.yml          # GitHub Actions pipeline
├── apps/website/                      # Node.js Express application
├── helm/tenant-website/               # Helm chart (used for all tenants)
├── k8s/                               # Kubernetes manifests
│   ├── cluster/kind-config.yaml
│   ├── namespaces/
│   ├── resource-quotas/
│   ├── cert-manager/
│   └── ingress/domain-configmap.yaml
├── argocd/applicationset.yaml         # Declarative app deployments
├── kafka/                             # Kafka setup & consumers
├── monitoring/prometheus/             # Prometheus/Grafana config
├── scripts/                           # Helper scripts
└── docs/                              # Documentation
```

## 📖 Additional Documentation

- [docs/dynamic-domain-mapping.md](docs/dynamic-domain-mapping.md) — Technical deep-dive on domain mapping
- [docs/architecture.md](docs/architecture.md) — Detailed system architecture
- [docs/kafka-integration.md](docs/kafka-integration.md) — Event-driven design

## 🎓 Learning Resources

- [Kubernetes Docs](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [cert-manager Docs](https://cert-manager.io/docs/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [ingress-nginx Docs](https://kubernetes.github.io/ingress-nginx/)
- [Prometheus Docs](https://prometheus.io/docs/)

## 📄 License

MIT

## 👥 Authors

DevOps Team - Yotto Assignment

---

**Last Updated**: March 16, 2026
**Version**: 1.0.0
**Status**: Production Ready
