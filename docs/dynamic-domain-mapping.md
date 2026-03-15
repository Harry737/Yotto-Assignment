# Dynamic Domain Mapping & Multi-Tenant Website Deployment

## Problem Statement

Traditional Kubernetes deployments require cluster redeploy or pod restarts when adding new domains. This breaks the zero-downtime requirement for SaaS platforms where users frequently add custom domains.

**Goal**: Support adding new domains without redeploying the cluster or restarting any workloads.

## Solution Architecture

### Key Components

1. **ingress-nginx**: Watches Ingress objects cluster-wide
2. **Helm Chart**: Templated Ingress with `domain:` field
3. **ArgoCD**: Detects new values files and auto-deploys
4. **Domain Registry ConfigMap**: Human-readable domain-to-tenant mapping

### How It Works

```
┌─────────────────────────────────────────┐
│  Developer: git push values-user1-site2 │
└─────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────┐
        │  ArgoCD ApplicationSet   │
        │  File Generator Pattern  │
        │  helm/tenant-website/    │
        │  values-*.yaml           │
        └───────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────┐
        │ ArgoCD generates Application:     │
        │ user1-site2-website               │
        └───────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────────────┐
        │ Helm renders templates with new values:   │
        │ - Deployment (user1-site2-...)            │
        │ - Service (user1-site2-...)               │
        │ - Ingress (host: user1-site2.example.com) │
        │ - HPA, PDB, NetworkPolicy                 │
        └───────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────┐
        │  kubectl apply all resources      │
        │  Pod starts                       │
        │  TLS cert issued (cert-manager)   │
        └───────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────────────┐
        │  ingress-nginx watches Ingress change     │
        │  Reloads nginx config (~30s)              │
        │  No pod restart! No cluster impact!       │
        └───────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────┐
        │  user1-site2.example.com → LIVE   │
        │  ✓ TLS enabled                    │
        │  ✓ Auto-scaled                    │
        │  ✓ Isolated from user1-site1      │
        └───────────────────────────────────┘
```

## Step-by-Step: Add New Website

### Example: Deploy user1-site2

#### Step 1: Create values file

```bash
cat > helm/tenant-website/values-user1-site2.yaml <<EOF
tenantName: "user1-site2"
domain: "user1-site2.example.com"

# Inherits all other settings from values.yaml:
# image.repository, replicaCount, resources, hpa, pdb, tls, etc.
EOF
```

#### Step 2: Add to DNS

```bash
# For testing: /etc/hosts
echo "127.0.0.1  user1-site2.example.com" | sudo tee -a /etc/hosts

# For production: CoreDNS or external DNS (managed by ExternalDNS controller)
```

#### Step 3: Update domain registry (optional)

```bash
kubectl edit cm domain-registry -n ingress-nginx

# Add entry:
# user1-site2.example.com = user1/user1-site2-tenant-website
```

#### Step 4: Push to git

```bash
git add helm/tenant-website/values-user1-site2.yaml
git commit -m "feat: add user1-site2 website for new customer"
git push origin main
```

#### Step 5: ArgoCD auto-deploys

```bash
# Monitor ArgoCD
kubectl get applications -n argocd -w

# Or UI: https://localhost:32002
# Look for: user1-site2-website → Synced
```

#### Step 6: Verify

```bash
# Check deployment created
kubectl get deployments -n user1

# Check Ingress created
kubectl get ingress -n user1

# Check TLS certificate issued
kubectl get certificate -n user1

# Test access
curl -k https://user1-site2.example.com/
```

**Total time**: ~30-60 seconds (including ArgoCD sync + ingress-nginx config reload)

## Why No Cluster Redeploy?

### Traditional Approach (❌ Downtime)

```
Step 1: Edit cluster ingress config
Step 2: kubectl apply cluster.yaml
Step 3: Cluster admission controller restarts
Step 4: ALL pods evicted and rescheduled
Step 5: Few minutes of downtime
```

### Our Approach (✅ Zero Downtime)

```
Step 1: New Ingress resource created (isolated, in user1 namespace)
Step 2: ingress-nginx controller watches and detects change
Step 3: nginx config reloaded in-place (no pod restart)
Step 4: User1-site2 live in ~30 seconds
Step 5: Other tenants unaffected
```

**Key insight**: ingress-nginx continuously watches Ingress objects. When a new one is created, it incremental updates its internal nginx config—no cluster-level operation needed.

## Technical Details

### Ingress Annotation Magic

```yaml
# helm/tenant-website/templates/ingress.yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "selfsigned-issuer"  # ← Auto TLS
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - {{ .Values.domain }}  # ← Templated per tenant
    secretName: {{ .Release.Name }}-tls
  rules:
  - host: {{ .Values.domain }}
    http:
      paths:
      - path: /
        backend:
          service: {{ .Release.Name }}
```

When Helm renders this with `tenantName: user1-site2` and `domain: user1-site2.example.com`, it creates:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: user1-site2-tenant-website
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned-issuer"
spec:
  tls:
  - hosts:
    - user1-site2.example.com
    secretName: user1-site2-tenant-website-tls
  rules:
  - host: user1-site2.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: user1-site2-tenant-website
            port: 80
```

### cert-manager Integration

When the Ingress is created with the cert-manager annotation, cert-manager's webhook intercepts it and automatically:

1. Creates a `Certificate` resource for `user1-site2.example.com`
2. Signs the cert using the `selfsigned-issuer`
3. Stores it in a Secret: `user1-site2-tenant-website-tls`
4. ingress-nginx reads this secret and serves it

**Zero manual intervention for TLS!**

### ApplicationSet File Generator

```yaml
# argocd/applicationset.yaml
generators:
- git:
    repoURL: https://github.com/your-org/repo
    revision: HEAD
    files:
    - path: "helm/tenant-website/values-*.yaml"
```

ArgoCD scans the repo every ~3 minutes:
- Detects all `values-*.yaml` files
- For each file, creates an Application resource
- Application → Helm chart + values file → kubectl apply

When you push `values-user1-site2.yaml`, ArgoCD detects it, creates `user1-site2-website` Application, and deploys.

## Scaling Beyond 3 Tenants

### Add Tenant 4 (New Company Signs Up)

```bash
# 1. Create namespace
kubectl create namespace user4

# 2. Create resource quota
cat > k8s/resource-quotas/user4-quota.yaml <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: user4-quota
  namespace: user4
spec:
  hard:
    requests.cpu: "1"
    requests.memory: "1Gi"
    limits.cpu: "2"
    limits.memory: "2Gi"
EOF

# 3. Create tenant values
cat > helm/tenant-website/values-user4.yaml <<EOF
tenantName: "user4"
domain: "user4.example.com"
EOF

# 4. Push to git
git add k8s/resource-quotas/user4-quota.yaml helm/tenant-website/values-user4.yaml
git commit -m "feat: onboard user4"
git push origin main

# 5. Manually create namespace (or let Helm + ArgoCD do it)
kubectl apply -f k8s/resource-quotas/user4-quota.yaml

# 6. ArgoCD auto-deploys
# Application user4-website created automatically
# Deployment live in ~30s
```

## Domain Resolution Strategies

### Development (Current)

```bash
/etc/hosts
127.0.0.1  user1.example.com
127.0.0.1  user1-site2.example.com
127.0.0.1  user2.example.com
127.0.0.1  user3.example.com
```

**Limitation**: Manual management, not scalable

### Production (Recommended)

Use **ExternalDNS** + cloud provider DNS (Route 53, CloudDNS, etc.):

```yaml
# Install ExternalDNS via Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install external-dns bitnami/external-dns \
  --namespace kube-system \
  --set provider=aws  # or gcp, azure, etc.
```

ExternalDNS watches Ingress objects and auto-creates DNS records in your cloud provider. Add a domain = automatic DNS entry.

### Production (Alternative): CoreDNS

Customize CoreDNS in the cluster:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    example.com {
      hosts /etc/coredns/example.hosts {
        fallthrough
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-hosts
  namespace: kube-system
data:
  example.hosts: |
    127.0.0.1 user1.example.com
    127.0.0.1 user1-site2.example.com
    127.0.0.1 user2.example.com
    127.0.0.1 user3.example.com
```

Maintain `example-hosts` ConfigMap as you add domains.

## Monitoring Domain Lifecycle

### Track Ingress Events

```bash
# Watch Ingress creation
kubectl get ingress -A -w

# Describe specific Ingress
kubectl describe ingress user1-site2-tenant-website -n user1

# Check TLS cert status
kubectl describe certificate user1-site2-tenant-website -n user1

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

### Prometheus Metrics for Ingress

Prometheus collects:
- `nginx_ingress_controller_requests` (per domain)
- `nginx_ingress_controller_bytes_sent`
- `nginx_ingress_controller_request_duration_seconds`

Create Grafana dashboards to monitor per-domain traffic.

## Troubleshooting

### Domain Not Accessible

```bash
# 1. Check DNS resolves
nslookup user1-site2.example.com

# 2. Check Ingress exists
kubectl get ingress -n user1

# 3. Check Ingress has IP/host
kubectl describe ingress user1-site2-tenant-website -n user1

# 4. Check TLS cert issued
kubectl get certificate -n user1
kubectl describe certificate user1-site2-tenant-website-tls -n user1

# 5. Check pod is running
kubectl get pods -n user1 -l app.kubernetes.io/instance=user1-site2-website

# 6. Test from inside cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -k https://user1-site2.example.com
```

### ArgoCD Not Detecting New Values File

```bash
# Check ApplicationSet is created
kubectl get applicationsets -n argocd

# Force refresh
kubectl patch applicationset tenant-websites -n argocd \
  -p '{"spec":{"refreshInterval":"1m"}}'

# Check generated Applications
kubectl get applications -n argocd

# If missing, check ApplicationSet logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
```

## Performance Notes

- **Ingress reload time**: ~30 seconds (from resource creation to traffic serving)
- **TLS cert issuance**: ~10-20 seconds (self-signed)
- **ArgoCD sync**: ~3 minutes default (configurable to 1 minute)
- **DNS propagation**: Depends on DNS provider (immediate for /etc/hosts)

**Critical path for new domain**: git push → ArgoCD detects (~3 min) → deploys (~1 min) → ingress-nginx syncs (~0.5 min) = **~5 minutes end-to-end**

For faster response, reduce ArgoCD refresh interval to 1 minute or use webhooks (GitHub → ArgoCD).

---

**See also**: [docs/architecture.md](architecture.md) for system design details.
