# Quick Start Guide

## ⚡ 5-Minute Setup (from zero to hero)

### Prerequisites Check

```bash
# Verify you have these installed
kind version
kubectl version --client
helm version
docker --version
docker-compose --version
git --version

# If any are missing, install them first
```

### Step 1: Clone & Prepare

```bash
cd d:\Yotto-Assignment
chmod +x scripts/*.sh
```

### Step 2: Bootstrap Everything

```bash
# This runs all setup steps automatically (5-10 minutes)
bash scripts/bootstrap.sh

# Watch the script output:
# ✓ Creates kind cluster
# ✓ Installs ingress-nginx, cert-manager, metrics-server
# ✓ Sets up ArgoCD
# ✓ Starts Kafka
# ✓ Installs Prometheus + Grafana
```

### Step 3: Add Domains to Your System

```bash
# Linux/macOS/WSL:
sudo bash scripts/setup-hosts.sh

# Windows (run as Administrator in PowerShell):
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 user1.example.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 user2.example.com"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 user3.example.com"
```

### Step 4: Verify Everything Works

```bash
# Check all resources deployed
bash scripts/verify-deployment.sh

# Test a website
curl -k https://user1.example.com

# Should return HTML with "Welcome to user1"
```

## 📊 What You Now Have

✅ **3 tenant websites** running in isolated namespaces
✅ **TLS enabled** with auto-cert generation
✅ **Auto-scaling** configured (2-10 pods per tenant)
✅ **Kafka** for event streaming
✅ **Prometheus + Grafana** for monitoring
✅ **ArgoCD** for GitOps deployments
✅ **GitHub Actions** ready for CI/CD

## 🎯 Next: See It In Action

### Test 1: Load Testing & Auto-Scaling

```bash
# Terminal 1: Watch pods scale
kubectl get hpa -n user1 -w

# Terminal 2: Watch HPA metrics
kubectl get pods -n user1 -w

# Terminal 3: Run load test (requires 'hey' tool)
bash scripts/load-test.sh user1 10000 50

# You should see:
# 1. CPU utilization spike
# 2. New pods created (HPA scales from 2 → 10)
# 3. Traffic distributed across pods
# 4. After traffic stops, pods scale down
```

### Test 2: Check Grafana Dashboards

```bash
# Access Grafana
open http://localhost:32000
# Login: admin / admin123

# View dashboards:
# - Kubernetes Cluster Overview
# - Pod CPU/Memory Usage
# - HTTP Requests (per tenant)
```

### Test 3: Check Kafka Events

```bash
# Start event consumer
cd kafka/consumer
npm ci
node consumer.js

# You should see WebsiteCreated events:
# [Event #1]
#   Event Type: WebsiteCreated
#   Tenant: user1
#   Domain: user1.example.com
#   Timestamp: 2024-03-15T10:00:00Z

# Ctrl+C to stop
```

### Test 4: Check ArgoCD Status

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
open https://localhost:32002
# Login: admin / <password from above>

# View applications for all 3 tenants
```

## 🚀 Add a New Website

Scenario: User1 wants a second website (user1-site2)

```bash
# 1. Create values file
cat > helm/tenant-website/values-user1-site2.yaml <<EOF
tenantName: "user1-site2"
domain: "user1-site2.example.com"
EOF

# 2. Add domain to /etc/hosts
echo "127.0.0.1  user1-site2.example.com" | sudo tee -a /etc/hosts

# 3. Push to git
git add helm/tenant-website/values-user1-site2.yaml
git commit -m "feat: add user1-site2"
git push origin main

# 4. ArgoCD auto-deploys within 3 minutes
kubectl get applications -n argocd -w

# 5. Verify it's live
curl -k https://user1-site2.example.com
```

**Details**: See [docs/dynamic-domain-mapping.md](docs/dynamic-domain-mapping.md)

## 📝 Configuration & Customization

### Change image tag

```bash
# Update all tenants to use a specific image
for tenant in user1 user2 user3; do
  sed -i "s|tag: .*|tag: \"sha-abc123\"|" helm/tenant-website/values-${tenant}.yaml
done

git add helm/tenant-website/values-*.yaml
git commit -m "chore: update image tag"
git push origin main
```

### Adjust resource limits

```bash
# Edit base values file
vim helm/tenant-website/values.yaml

# Change:
# resources.requests.cpu: "200m"
# resources.limits.cpu: "1000m"

# Re-apply to all tenants
for tenant in user1 user2 user3; do
  helm upgrade ${tenant}-website ./helm/tenant-website \
    -f helm/tenant-website/values-${tenant}.yaml \
    -n ${tenant}
done
```

### Change HPA min/max replicas

```bash
# Edit values.yaml or per-tenant values file
vim helm/tenant-website/values-user1.yaml

# Change:
# hpa.minReplicas: 3
# hpa.maxReplicas: 20

# Redeploy
helm upgrade user1-website ./helm/tenant-website \
  -f helm/tenant-website/values-user1.yaml \
  -n user1
```

## 🔍 Troubleshooting

### Cluster stuck or slow?

```bash
# Check cluster status
kind get clusters
kind describe cluster yotto-cluster

# Check nodes
kubectl get nodes

# If stuck, restart:
kind delete cluster --name yotto-cluster
bash scripts/bootstrap.sh  # Re-run bootstrap
```

### Pods not deploying?

```bash
# Check ArgoCD is running
kubectl get pods -n argocd

# Check application status
kubectl get applications -n argocd

# Check pod logs
kubectl logs -n user1 -l app.kubernetes.io/instance=user1-website --tail=50
```

### ingress not working?

```bash
# Check ingress-nginx
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Check ingress resource
kubectl get ingress -n user1
kubectl describe ingress user1-tenant-website -n user1

# Test from inside cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -k https://user1.example.com
```

### HPA not scaling?

```bash
# Check metrics-server
kubectl get deployment -n kube-system metrics-server

# Check metrics are available
kubectl top pods -n user1

# Check HPA status
kubectl describe hpa user1-website -n user1

# If no metrics, patch metrics-server:
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## 📚 Documentation

- **[README.md](README.md)** — Comprehensive guide to all features
- **[docs/dynamic-domain-mapping.md](docs/dynamic-domain-mapping.md)** — How domain mapping works
- **[docs/architecture.md](docs/architecture.md)** — System design & decisions
- **[.github/workflows/ci.yml](.github/workflows/ci.yml)** — CI/CD pipeline (GitHub Actions)

## 🎓 Key Concepts

| Concept | Explanation |
|---------|-------------|
| **kind** | Local Kubernetes cluster in Docker containers |
| **Helm** | Kubernetes package manager; templating system |
| **Ingress** | Kubernetes resource defining HTTP/HTTPS routes |
| **cert-manager** | Auto-generates and renews TLS certificates |
| **ArgoCD** | GitOps operator; keeps cluster in sync with git |
| **HPA** | Horizontal Pod Autoscaler; scales pods based on metrics |
| **Namespace** | Kubernetes tenant isolation mechanism |
| **NetworkPolicy** | Kubernetes firewall rules between pods |
| **ResourceQuota** | Kubernetes resource limit enforcement |
| **ServiceMonitor** | Prometheus service discovery for metrics |

## 🔐 Security Notes

✅ Pods run as non-root user
✅ Read-only filesystem (except /tmp)
✅ Network policies enforce tenant isolation
✅ TLS on all traffic
✅ Resource quotas prevent DoS
✅ RBAC (future enhancement)

## 📈 Expected Performance

| Operation | Time |
|-----------|------|
| Cluster creation | 2-3 min |
| App deployment | 30-60 sec |
| Pod scaling (HPA) | 30-60 sec |
| TLS cert issuance | 10-20 sec |
| Domain live after push | 3-5 min |

## 💡 Pro Tips

```bash
# Watch pod scaling in real-time
watch -n 1 'kubectl get pods -n user1'

# Follow pod logs (new pods too)
kubectl logs -n user1 -f -l app.kubernetes.io/instance=user1-website --all-containers=true

# SSH into a pod for debugging
kubectl exec -it <pod-name> -n user1 -- /bin/sh

# Port-forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-community-grafana 3000:80

# ArgoCD sync status
kubectl get applications -n argocd -o wide
```

## 🚨 Common Issues

| Issue | Solution |
|-------|----------|
| `curl: (7) Failed to connect to user1.example.com` | Add domain to /etc/hosts, check ingress-nginx is running |
| `HPA shows <unknown>/60%` | Install/patch metrics-server, wait 30s for metrics |
| `Certificate not ready` | Check cert-manager logs, wait for cert-manager webhook |
| `Pod CrashLoopBackOff` | Check pod logs, verify image exists, check resource requests |
| `ArgoCD not syncing` | Check git credentials, verify ApplicationSet, check ArgoCD logs |

## 📞 Support

For detailed troubleshooting, see:
- [README.md#troubleshooting](README.md#-troubleshooting)
- `kubectl describe` and `kubectl logs` (your best friends)
- Kubernetes docs: https://kubernetes.io/docs/

---

**You're all set!** 🎉

Time to deploy some websites:
```bash
curl -k https://user1.example.com
curl -k https://user2.example.com
curl -k https://user3.example.com
```
