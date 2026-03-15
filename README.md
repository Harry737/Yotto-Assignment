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

- **3 Tenants**: user1, user2, user3
- **Isolation**: Each tenant has its own Kubernetes namespace with:
  - Network Policies (ingress-nginx → pod traffic only)
  - Resource Quotas (CPU/memory limits per tenant)
  - RBAC (future: per-tenant service accounts)
- **Scalability**: Each tenant can deploy multiple independent websites
  - Example: user1-site1, user1-site2, user1-site3
  - New sites deployed via git push (values-user1-siteN.yaml)
  - ArgoCD automatically detects and deploys new sites

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
- Create a kind cluster with 3 nodes
- Install ingress-nginx, cert-manager, metrics-server
- Create 3 tenant namespaces with resource quotas
- Install ArgoCD for GitOps deployments
- Start Kafka + initialize topics
- Install kube-prometheus-stack for monitoring

### Verify Deployment

```bash
# Check all resources across tenants
bash scripts/verify-deployment.sh

# Or manually:
kubectl get all -n user1
kubectl get all -n user2
kubectl get all -n user3
```

### Access Services

```bash
# Test a website
curl -k https://user1.example.com

# ArgoCD UI (get admin password first)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
# Then visit: https://localhost:32002

# Grafana Dashboard
# Visit: http://localhost:32000
# Login: admin / admin123

# Prometheus
# Visit: http://localhost:32001

# Watch pods scaling
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

1. **Build Phase**: Docker build + push to Docker Hub (tagged with git SHA)
2. **Update Phase**: Update Helm values files with new image tag
3. **Sync Phase**: ArgoCD auto-syncs and deploys to all 3 tenants
4. **Verify Phase**: (Self-hosted runner) Confirm pod rollout status
5. **Event Phase**: Publish deployment events to Kafka

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

## 🎯 Dynamic Domain Mapping & Multi-Website Deployment

### Add a New Website for a Tenant

**Scenario**: User1 wants to deploy a second website (user1-site2)

```bash
# 1. Create a new values file
cat > helm/tenant-website/values-user1-site2.yaml <<EOF
tenantName: "user1-site2"
domain: "user1-site2.example.com"
# All other settings inherit from values.yaml
EOF

# 2. Add domain to /etc/hosts (or CoreDNS)
echo "127.0.0.1  user1-site2.example.com" | sudo tee -a /etc/hosts

# 3. Update domain registry ConfigMap (optional, for documentation)
kubectl edit cm domain-registry -n ingress-nginx

# 4. Push to git
git add helm/tenant-website/values-user1-site2.yaml
git commit -m "feat: add user1-site2 website"
git push origin main
```

ArgoCD will automatically:
- Detect the new values file
- Create a new Helm Application (via ApplicationSet file generator)
- Deploy a new Deployment, Service, Ingress, HPA, PDB in the `user1` namespace
- issue TLS cert via cert-manager
- Expose at `https://user1-site2.example.com` (~30 seconds)

### How It Works

**Traditional approach**: Redeploy entire cluster for new domain ❌

**Our approach**:
1. ingress-nginx watches Ingress objects cluster-wide
2. When a new Ingress is created, ingress-nginx reloads its config (~30s)
3. No pod restarts, no cluster redeploy, zero downtime ✅

See [docs/dynamic-domain-mapping.md](docs/dynamic-domain-mapping.md) for detailed explanation.

## 📈 Observability & Monitoring

### Prometheus Metrics

The platform automatically collects:
- Pod CPU, memory, network I/O
- HTTP request duration (from /metrics endpoint)
- HPA scaling events
- Kubernetes control-plane metrics

### Grafana Dashboards

Pre-installed dashboards:
- Kubernetes Cluster Overview
- Pod CPU/Memory Usage
- HTTP Request Metrics (per tenant)

**Custom dashboard**: Deployed automatically via values.yaml

### Service Monitors

The Helm chart includes a `ServiceMonitor` for Prometheus auto-discovery. No manual scrape config needed.

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

- **CPU**: 500m (limit) / 100m (request)
- **Memory**: 256Mi (limit) / 128Mi (request)
- **Enforced via**: ResourceQuota per namespace

### TLS Certificates

- Self-signed CA chain (cert-manager)
- Automatic cert issuance & renewal
- No external CA needed for demo

## 📝 Kafka Event Streaming

### Event Topics

**Topic**: `website-events`

**Event Schema**:
```json
{
  "event": "WebsiteCreated|DeploymentTriggered|DeploymentSucceeded|DeploymentRolledBack",
  "tenant": "user1",
  "domain": "user1.example.com",
  "timestamp": "2024-03-15T10:30:00Z",
  "version": "sha-abc123def456"
}
```

### Subscribe to Events

```bash
# Start consumer
cd kafka/consumer
npm ci
node consumer.js

# Output: prints all events real-time
```

### Publish Events (Manual)

```bash
node kafka/consumer/notify.js \
  --event CustomEvent \
  --tenant user1 \
  --version v1.0.0
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

**Last Updated**: March 2024
**Version**: 1.0.0
