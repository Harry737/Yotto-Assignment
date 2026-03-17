# Yotto Assignment - Interview Preparation Guide

**Interview Date**: 2026-03-18
**Project Status**: ✅ Complete & Production Ready

---

## 📋 Table of Contents

1. [Architecture & Design](#1-architecture--design)
2. [Kubernetes & Container Orchestration](#2-kubernetes--container-orchestration)
3. [Multi-Tenancy](#3-multi-tenancy)
4. [CI/CD & Deployment](#4-cicd--deployment)
5. [Scaling & Performance](#5-scaling--performance)
6. [Monitoring & Observability](#6-monitoring--observability)
7. [Kafka & Event Streaming](#7-kafka--event-streaming)
8. [Security](#8-security)
9. [Troubleshooting & Operations](#9-troubleshooting--operations)
10. [Design Decisions & Trade-offs](#10-design-decisions--trade-offs)
11. [Future Enhancements](#11-future-enhancements)

---

## 1. Architecture & Design

### 1.1 High-Level Architecture
**Q: Walk me through the overall architecture of the Yotto platform. What are the main components?**

**Model Answer**:
```
User Request → Internet → Host Port 80/443 → Kind Cluster →
ingress-nginx → tenant namespace → pods → Kafka/Prometheus
```

Main components:
- **Kind Cluster**: Local Kubernetes (1 control-plane + 2 workers)
- **ingress-nginx**: HTTP/HTTPS traffic routing & TLS termination
- **cert-manager**: Automatic TLS certificate management
- **ArgoCD**: GitOps operator for declarative deployments
- **Kubernetes**: Pod orchestration with HPA, PDB, NetworkPolicy
- **Kafka**: Event streaming (Docker Compose)
- **Prometheus/Grafana**: Metrics & monitoring

**Why this design?**
- Kind: Local K8s simulation without cloud costs
- ingress-nginx: Dynamic routing by hostname
- cert-manager: Automated self-signed TLS (no external CA needed)
- ArgoCD: Declarative GitOps (git is source of truth)
- Kafka: Async event notifications
- Prometheus: Auto-discovery via ServiceMonitor

---

### 1.2 Key Architectural Decisions
**Q: What were the key architectural decisions you made, and why?**

**Model Answer**:

1. **Single Helm Chart vs Per-Tenant Charts**
   - ✅ **Chose**: Single reusable Helm chart
   - **Why**: DRY principle, easier maintenance, consistent deployment
   - **Alternative**: Per-tenant charts = code duplication, harder to update

2. **ArgoCD ApplicationSet vs Manual Helm**
   - ✅ **Chose**: ApplicationSet with file generator
   - **Why**: Declarative, GitOps, auto-scales to N tenants
   - **Alternative**: Manual `helm install` = manual work, not declarative

3. **Docker Compose Kafka vs In-K8s Kafka**
   - ✅ **Chose**: Docker Compose (single-node)
   - **Why**: Sufficient for demo, easy to start/stop
   - **Alternative**: In-K8s Kafka = over-engineered, StatefulSet complexity

4. **Self-Signed Certs via cert-manager**
   - ✅ **Chose**: Self-signed CA chain
   - **Why**: No external CA needed, fully automated renewal
   - **Alternative**: Manual certs = error-prone, renewal nightmare

5. **kind Cluster vs Real Cloud K8s**
   - ✅ **Chose**: kind (local development)
   - **Why**: Fast, lightweight, free, simulates real K8s
   - **Alternative**: EKS/GKE = expensive, slower feedback loops

---

### 1.3 System Constraints & Trade-offs
**Q: What constraints did you work within, and how did they influence design?**

**Model Answer**:

| Constraint | Impact | Solution |
|-----------|--------|----------|
| Local kind cluster | Can't use cloud LoadBalancer | Used NodePort + port mapping |
| WSL2 networking | Pods can't reach localhost | Used 172.17.0.1 (docker0 gateway) |
| No external CA | Needed HTTPS for demo | Self-signed + cert-manager |
| Demo simplicity | No real databases | Stateless app + Kafka events |
| Single host | Limited total pod capacity | HPA min 2, max 10 per tenant |

---

## 2. Kubernetes & Container Orchestration

### 2.1 Cluster Setup
**Q: How did you set up the kind cluster? Walk through the bootstrap process.**

**Model Answer**:

```bash
bash scripts/bootstrap.sh
```

Does 12 things automatically:

1. **Create kind cluster** with kind-config.yaml
   ```yaml
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
   - role: control-plane
     extraPortMappings:
     - containerPort: 80
       hostPort: 80
     - containerPort: 443
       hostPort: 443
     labels:
       ingress-ready: "true"
   - role: worker
   - role: worker
   ```

2. **Install ingress-nginx**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
   ```

3. **Install cert-manager** with CRDs
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml
   helm install cert-manager cert-manager/cert-manager -n cert-manager --create-namespace
   ```

4. **Install metrics-server** (HPA requirement)
   - Patch: `--kubelet-insecure-tls` (kind uses self-signed certs)

5. **Create 5 tenant namespaces** (user1-5)
   - Each with ResourceQuota + NetworkPolicy

6. **Install ArgoCD**
   - Create ApplicationSet pointing to git repo

7. **Deploy ApplicationSet**
   - Scans for values-*.yaml files
   - Auto-creates Application per file

8. **Start Kafka** via Docker Compose
   - Creates topic: `website-events`
   - Broker: 172.17.0.1:9092 (host gateway)

9. **Install Prometheus + Grafana**
   - kube-prometheus-stack Helm chart
   - Pre-built dashboards

10. **Create Ingress resources** per tenant
    - cert-manager issues TLS certs

11. **Deploy applications** via Helm
    - All 3 tenants running

12. **Setup local DNS** (optional)
    - Add hosts file entries

---

### 2.2 Namespace Isolation
**Q: How do you isolate tenants in Kubernetes? What mechanisms are in place?**

**Model Answer**:

```
user1 namespace → Deployment → Pods → Ingress (user1.example.com)
  ├── NetworkPolicy (strict ingress)
  ├── ResourceQuota (CPU/memory limits)
  ├── PodDisruptionBudget (min 1 replica)
  └── ServiceAccount (RBAC ready)

user2 namespace → [same structure]
user3 namespace → [same structure]
```

**Isolation mechanisms**:

1. **Namespace Boundaries**
   - Each tenant in separate namespace
   - Enables RBAC, quota, policy enforcement

2. **NetworkPolicy** (strict ingress)
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: tenant-isolation
     namespace: user1
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
     - Egress
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: ingress-nginx
     egress:
     - to:
       - namespaceSelector: {}  # Any namespace for Kafka, DNS
       - podSelector:
           matchLabels:
             app: prometheus  # Allow Prometheus scraping
   ```

   **Effect**: Only ingress-nginx can send traffic to pods

3. **ResourceQuota** (prevent over-consumption)
   ```yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: user1-quota
     namespace: user1
   spec:
     hard:
       requests.cpu: "1"
       limits.cpu: "2"
       requests.memory: "1Gi"
       limits.memory: "2Gi"
       pods: "20"
       services: "10"
   ```

   **Effect**: Total tenant CPU/memory capped

4. **PodDisruptionBudget** (maintain availability)
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: user1-website-pdb
     namespace: user1
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: user1-website
   ```

   **Effect**: During node drain, min 1 pod stays alive

5. **Pod Security Context**
   - Non-root user (uid 1000)
   - Read-only filesystem (except /tmp)
   - Dropped capabilities (ALL)

---

### 2.3 Deployment & Rolling Updates
**Q: How do you deploy application updates? Describe the rollout process.**

**Model Answer**:

**Traditional Rolling Update** (❌ risky):
```
1. Kill pod v1
2. Start pod v2
3. Repeat
Risk: Mixed versions during update
```

**Our approach** (✅ Helm + Blue-Green):
```
1. Helm upgrade with new image tag
2. New pod starts alongside old pods
3. Old pods terminate once new ones pass readiness
4. If failure detected, helm rollback to v0
```

**Deployment workflow**:

```
git push code → GitHub Actions pipeline
  ↓
build-and-push: Docker build + push to Hub
  - Tag: sha-<commit-hash>
  - Output: sha-abc123def456
  ↓
update-helm-values: Update all values-*.yaml
  - sed "s|tag: .*|tag: sha-abc123def456|"
  - git push → triggers ArgoCD
  ↓
ArgoCD detects change (3 min interval, or webhook)
  - Syncs ApplicationSet
  - Renders Helm templates
  - kubectl apply new Deployment
  ↓
Kubernetes rollout:
  - HPA creates new pods with new image
  - Service switches traffic once ready
  - Old ReplicaSet scales to 0
  ↓
verify-deployment: Checks pod readiness
  - kubectl rollout status deployment
  - If fails → helm rollback
  ↓
Kafka event: DeploymentSucceeded (or DeploymentRolledBack)
```

**Key advantages**:
- Fast rollback: `helm rollback user1-website -n user1`
- Atomic: All-or-nothing deployment
- No manual cutover needed

---

### 2.4 Ingress & Routing
**Q: How does HTTP traffic get routed to tenant pods? Describe the ingress flow.**

**Model Answer**:

```
User Request: https://user1.example.com
  ↓
Host:443 → kind control-plane:443 (port mapping)
  ↓
ingress-nginx pod (running on control-plane)
  - Watches Ingress resources
  - Reloads nginx config when Ingress changes
  - Has cert from cert-manager Secret
  ↓
Ingress rule: user1.example.com → Service: user1-website (port 3000)
  ↓
Service: Load balances across pods (TCP 3000)
  - Endpoints updated by kubelet as pods start/stop
  ↓
Pod receives request → app responds
```

**Ingress resource** (generated by Helm):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: user1-website
  namespace: user1
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - user1.example.com
    secretName: user1-website-tls  # Created by cert-manager
  rules:
  - host: user1.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: user1-website
            port:
              number: 3000
```

**DNS resolution**:
- Added to `/etc/hosts`: `127.0.0.1 user1.example.com`
- Or use WSL hostname → port-forward

---

## 3. Multi-Tenancy

### 3.1 Multi-Tenant Model
**Q: Explain your multi-tenancy architecture. How do 5 tenants coexist?**

**Model Answer**:

```
Yotto Platform (Single Cluster)
├── Cluster-level
│   ├── ingress-nginx (shared, single controller)
│   ├── cert-manager (shared, issues certs per tenant)
│   ├── ArgoCD (shared, manages all tenants)
│   ├── Prometheus (shared, scrapes all namespaces)
│   └── Grafana (shared, multi-tenant dashboards)
│
└── Tenant-level (5 separate namespaces)
    ├── user1 namespace
    │   ├── Deployment: user1-website (2-10 pods)
    │   ├── Service: user1-website (ClusterIP)
    │   ├── Ingress: user1.example.com (routes to Service)
    │   ├── NetworkPolicy (strict isolation)
    │   ├── ResourceQuota (CPU/memory limits)
    │   ├── HPA (2-10 replicas based on CPU/memory)
    │   ├── PDB (min 1 pod during disruptions)
    │   ├── ServiceMonitor (Prometheus scraping)
    │   └── Certificate (TLS cert for domain)
    │
    ├── user2 namespace → [same structure]
    ├── user3 namespace → [same structure]
    ├── user4 namespace → [same structure]
    └── user5 namespace → [same structure]
```

**Isolation levels**:

| Level | Mechanism | Isolation Strength |
|-------|-----------|-------------------|
| Network | NetworkPolicy | ⭐⭐⭐⭐⭐ Pods can't reach other tenants |
| Resource | ResourceQuota | ⭐⭐⭐⭐⭐ CPU/memory enforced |
| RBAC | ServiceAccount + RoleBinding | ⭐⭐⭐ (not yet implemented) |
| Data | Separate databases | ⭐⭐⭐⭐⭐ (app-level, not K8s) |

---

### 3.2 Dynamic Tenant Creation
**Q: How can you add a new tenant (e.g., user6) without downtime?**

**Model Answer**:

**Automatic (Recommended)**:
```bash
bash scripts/create-tenant.sh user6
```

**What happens**:
1. Creates `helm/tenant-website/values-user6.yaml` (copy of user1)
2. Edits tenantName, domain, imageTags
3. Creates namespace: `kubectl create namespace user6`
4. Creates ResourceQuota: `k8s/resource-quotas/user6-quota.yaml`
5. Adds to ApplicationSet list generator
6. Git commits and pushes
7. ArgoCD detects change (within 3 min)
8. Helm renders template
9. New Ingress, Service, Deployment created
10. cert-manager issues TLS cert
11. Pod starts, publishes WebsiteCreated event
12. ~2 minutes total

**Why zero downtime?**
- No cluster redeploy
- No existing pod interruption
- Shared ingress-nginx controller
- ArgoCD handles sync

**Manual approach** (if you understand flow):
```bash
# 1. Copy values file
cp helm/tenant-website/values-user1.yaml helm/tenant-website/values-user6.yaml

# 2. Edit values-user6.yaml
nano helm/tenant-website/values-user6.yaml
# Change: tenantName: user6, domain: user6.example.com

# 3. Add to ApplicationSet
kubectl edit applicationset tenant-websites -n argocd
# Add: - tenant: user6 to spec.generators[0].list.elements

# 4. Create namespace
kubectl create namespace user6

# 5. Create ResourceQuota
kubectl apply -f k8s/resource-quotas/user6-quota.yaml

# 6. Push to git (triggers ArgoCD)
git add helm/tenant-website/values-user6.yaml k8s/resource-quotas/user6-quota.yaml
git commit -m "feat: add user6 tenant"
git push origin master
```

**ApplicationSet generator** (Helm templating):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-websites
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - tenant: user1
      - tenant: user2
      - tenant: user3
      - tenant: user4
      - tenant: user5
  template:
    metadata:
      name: '{{.tenant}}-website'
      namespace: argocd
    spec:
      source:
        repoURL: https://github.com/Harry737/Yotto-Assignment
        path: helm/tenant-website
        helm:
          valuesFiles:
          - values-{{.tenant}}.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.tenant}}'
```

**How it works**:
- Scans `helm/tenant-website/` for `values-*.yaml`
- Creates Application per file
- Template variable `{{.tenant}}` replaced with file name
- Example: `values-user6.yaml` → Application `user6-website`

---

### 3.3 Tenant Data Isolation
**Q: How do you ensure data isolation between tenants?**

**Model Answer**:

**Current approach** (app-level):
- Stateless app (no local data)
- Each pod publishes to same Kafka topic
- Event includes tenant name for filtering

**Data isolation layers**:

1. **Network Isolation** (NetworkPolicy)
   ```
   user1 pods ← → only ingress-nginx & Prometheus
              → X user2 pods (blocked)
   ```

2. **Storage Isolation** (not implemented)
   - StatefulSet per tenant (if persistent storage needed)
   - PersistentVolumeClaim per tenant namespace
   - Kubernetes storage controller enforces isolation

3. **Application-Level** (Kafka filtering)
   ```javascript
   // Consumer filters by tenant
   const tenant = message.value.tenant;
   if (tenant === 'user1') {
     // process user1 event
   }
   ```

4. **Database Isolation** (future)
   - Separate database per tenant
   - Database credentials in per-tenant Secret
   - RBAC ensures tenant can only access own Secret

---

## 4. CI/CD & Deployment

### 4.1 GitHub Actions Pipeline
**Q: Walk through the GitHub Actions CI/CD pipeline. What happens on `git push`?**

**Model Answer**:

**Trigger**: `git push origin master` to apps/website/

**Pipeline stages**:

```
Stage 1: build-and-push (5-10 min)
├── Checkout code
├── Set image tag to sha-<commit-hash>
├── Setup Docker Buildx (layer caching)
├── Login to Docker Hub (using secrets)
├── Docker build + push
│   ├── Build context: ./apps/website
│   ├── Image: docker.io/YOUR_USERNAME/tenant-website:sha-abc123
│   └── GHA cache for layers
└── Output: image_tag = sha-abc123

Stage 2: update-helm-values (2 min)
├── Checkout code
├── Update all values-*.yaml files
│   ├── for file in helm/tenant-website/values-*.yaml
│   ├── sed 's|tag: ".*"|tag: "sha-abc123"|'
│   └── Replaces tag in all tenant configs simultaneously
├── Git commit "ci: update image tag to sha-abc123"
└── Git push → triggers ArgoCD

Stage 3: verify-deployment (3-5 min)
├── Wait 10 seconds for ArgoCD to start sync
├── Get all tenant namespaces (kubectl get ns)
├── For each namespace with tenant-website deployment:
│   ├── kubectl rollout status --timeout=120s
│   └── Wait for pods to become Ready
├── List all pods (sanity check)
├── Publish DeploymentSucceeded event to Kafka
└── Continue on error (Kafka optional)

Stage 4: rollback-on-failure (if Stage 3 fails)
├── For each tenant namespace:
│   ├── kubectl rollout undo deployment
│   └── Reverts to previous image tag
├── Publish DeploymentRolledBack event to Kafka
└── Pipeline marked as failed
```

**Configuration** (`.github/workflows/ci.yml`):

```yaml
on:
  push:
    branches:
      - master
    paths:
      - 'apps/website/**'      # Only trigger on app changes
      - '.github/workflows/ci.yml'

jobs:
  build-and-push:
    runs-on: self-hosted        # Requires self-hosted runner (local cluster)
    outputs:
      image_tag: sha-${{ github.sha }}
    steps:
      # Docker build & push

  update-helm-values:
    needs: build-and-push       # Dependency: wait for image
    runs-on: self-hosted
    steps:
      # Update all values-*.yaml files
      # Git push (triggers ArgoCD sync)

  verify-deployment:
    needs: update-helm-values
    runs-on: self-hosted
    steps:
      # Check all pods are running
      # Publish Kafka event

  rollback-on-failure:
    needs: [build-and-push, update-helm-values]
    runs-on: self-hosted
    if: failure()              # Only if previous jobs failed
    steps:
      # Rollback all deployments
      # Publish failure event
```

---

### 4.2 Why Self-Hosted Runner?
**Q: Why does the pipeline use a self-hosted runner instead of GitHub's Ubuntu runners?**

**Model Answer**:

**Problem**: GitHub-hosted runners run on GitHub infrastructure (AWS)
- Can't reach kind cluster on your local machine
- Can't access kubeconfig
- Can't reach Kafka on localhost

**Solution**: Self-hosted runner on your development machine
```
Your machine (Windows)
  └─ WSL2 (Linux environment)
      └─ Self-hosted GitHub Actions runner
          ├── Access to kind cluster (via kubectl)
          ├── Access to Docker daemon (docker build)
          └── Access to Kafka (via 172.17.0.1:9092)
```

**Setup**:
```bash
# On your machine in WSL
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.x.tar.gz https://github.com/actions/runner/releases/...
tar xzf actions-runner-linux-x64-2.x.tar.gz
./config.sh --url https://github.com/YOUR_ORG/REPO --token TOKEN
sudo ./svc.sh install
sudo ./svc.sh start
```

**Alternative**: GitHub-hosted runner + deploy to cloud
- Push image to Docker Hub ✅
- Trigger webhook to self-hosted runner ✅
- Self-hosted runner pulls new image, deploys locally

---

### 4.3 Rollback Strategy
**Q: What happens if the deployment fails? How do you rollback?**

**Model Answer**:

**Automatic Rollback** (via pipeline):

```
verify-deployment job fails (pod not ready after 120s)
  ↓
Pipeline status: FAILURE
  ↓
rollback-on-failure job triggered (if: failure())
  ↓
For each tenant namespace:
  kubectl rollout undo deployment -n user1
  kubectl rollout undo deployment -n user2
  kubectl rollout undo deployment -n user3
  ↓
Kubernetes rolls back to previous ReplicaSet
  - Old pods (previous image tag) scaled back up
  - New pods (failed image) scaled down
  ↓
Service traffic re-routes to old pods
  ↓
DeploymentRolledBack event published to Kafka
```

**Manual Rollback**:
```bash
# Rollback specific tenant
helm rollout undo deployment user1-website -n user1

# Show rollout history
kubectl rollout history deployment user1-website -n user1

# Rollback to specific revision
kubectl rollout undo deployment user1-website -n user1 --to-revision=2
```

**Alternative via Helm**:
```bash
# Show release history
helm history user1-website -n user1

# Rollback to previous release
helm rollback user1-website -n user1

# Rollback to specific revision
helm rollback user1-website 1 -n user1
```

**Why automatic?**
- Fast feedback (detect failure early)
- Prevent cascading failures
- Maintain service availability
- Explicit event (for audit trail)

---

## 5. Scaling & Performance

### 5.1 Horizontal Pod Autoscaler (HPA)
**Q: How does auto-scaling work in this platform?**

**Model Answer**:

**HPA Configuration** (v2, metrics-based):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user1-website
  namespace: user1
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user1-website
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

**Scaling logic**:

```
Monitor metrics every 15 seconds (via metrics-server)
  ↓
If CPU > 60% OR Memory > 70%:
  → Scale UP (add pods)
  → Check: current pods < max (10)
  → Target pods = current × 2 or +4 (whichever more)
  ↓
If CPU < 60% AND Memory < 70% for 5 minutes (300s):
  → Scale DOWN (remove pods)
  → Check: current pods > min (2)
  → Remove 1 pod (stabilization: don't thrash)
```

**Scaling example**:

```
Baseline: 2 pods, CPU 10%, Memory 150MB

[T=0] Load test starts: 5000 requests, 50 concurrent

[T=30s] CPU spike detected
  metrics-server reports: avg CPU = 65%
  → 65% > 60% threshold
  → Scale UP: 2 → 4 pods

[T=60s] More CPU spike
  metrics-server reports: avg CPU = 75%
  → 75% > 60% threshold
  → Scale UP: 4 → 8 pods

[T=120s] Load stabilizes
  metrics-server reports: avg CPU = 72%
  → Still > 60%
  → Scale UP: 8 → 10 pods (max reached)

[T=300s] Load test finishes (0 requests)
  metrics-server reports: avg CPU = 15%
  → 15% < 60% for 5 minutes
  → Scale DOWN: 10 → 5 pods (50% reduction)

[T=360s] Still idle
  → Scale DOWN: 5 → 2 pods (min reached)

[T=420s] Stabilize at minimum
  → 2 pods, CPU 10%, Memory 150MB
```

**Testing HPA**:

```bash
# Watch HPA in real-time
kubectl get hpa -n user1 -w

# Watch pods scaling
kubectl get pods -n user1 -w

# Check current metrics
kubectl top pods -n user1

# Load test
bash scripts/load-test.sh user1 5000 50

# Describe HPA to see scaling decisions
kubectl describe hpa user1-website -n user1
```

**Requirements**:

1. **metrics-server** (Kubernetes default)
   - Collects CPU/memory metrics from kubelets
   - For kind, needs patch: `--kubelet-insecure-tls`

2. **Resource requests/limits**
   ```yaml
   resources:
     requests:
       cpu: 100m         # 0.1 core baseline
       memory: 128Mi     # 128MB baseline
     limits:
       cpu: 500m         # 0.5 core max
       memory: 512Mi     # 512MB max
   ```
   HPA uses requests for % calculations

3. **Service running** (needs traffic to measure)
   - HPA won't scale without metrics

---

### 5.2 Load Testing & Monitoring
**Q: How do you validate that scaling works correctly?**

**Model Answer**:

**Load testing workflow**:

```bash
bash scripts/load-test.sh user1 5000 50
```

Does:
1. Install 'hey' tool if not present
2. Fire 5000 HTTP requests to https://user1.example.com
3. Use 50 concurrent connections
4. Monitor HPA metrics in real-time
5. Watch pod count increase
6. Stop and report results

**Metrics to verify**:

```
Before load:
  kubectl top pods -n user1
  → POD                          CPU(m)   MEMORY(Mi)
    user1-website-7d8f9         45       156

During load (5000 req, 50 concurrent):
  kubectl top pods -n user1
  → POD                          CPU(m)   MEMORY(Mi)
    user1-website-7d8f9         450      256
    user1-website-8f9d2         420      250
    user1-website-9d2a3         430      252
    user1-website-a3b4c         410      248
    user1-website-b4c5d         450      260
    user1-website-c5d6e         440      254
    user1-website-d6e7f         430      256
    user1-website-e7f8g         420      250
    [8 pods instead of 2]

HPA status:
  kubectl describe hpa user1-website -n user1
  → Min/Max replicas: 2/10
  → Current/Desired: 8/8
  → CPU: 435m/600m (72% utilization) ← triggers scale
  → Memory: 251Mi/768Mi (32%)

After load stops (idle 5 minutes):
  kubectl top pods -n user1
  → [back to 2 pods, CPU 10%, Memory 150MB]
```

**Grafana dashboards**:

```
HPA Current Replicas
├── X-axis: Time
├── Y-axis: Replica count
└── Shows: 2 → 8 → 2 trend

Memory Usage per Tenant
├── Shows: baseline ~150MB, peak ~250MB

Pods per Tenant
├── Shows: 2 baseline, 8 peak

CPU Usage per Tenant
├── Shows: 0% baseline, 70%+ during load
```

---

### 5.3 Performance Bottlenecks
**Q: What are the performance bottlenecks, and how would you optimize?**

**Model Answer**:

| Bottleneck | Current | Ideal | Why Hard |
|-----------|---------|-------|----------|
| ArgoCD sync | 3 min | 10s | Git polling loop |
| ingress-nginx reload | 30s | 10s | Nginx signal handling |
| Pod startup | 3-5s | 1s | App initialization |
| HPA decision lag | 30s | 5s | Metrics aggregation |

**Optimization strategies**:

1. **ArgoCD sync time** (3 min → 10s)
   ```bash
   # Reduce sync interval
   kubectl -n argocd patch cm argocd-cm -p '{"data":{"application.instanceLabelKey":"argocd.argoproj.io/instance"}}'

   # Or use webhooks (GitHub → ArgoCD instant trigger)
   # Setup: GitHub Webhook → ArgoCD → /api/webhook
   ```

2. **ingress-nginx reload** (30s → 10s)
   - Can't improve without sacrificing stability
   - Trade-off: Fast reload vs correct config

3. **Pod startup** (3-5s → 1s)
   - Startup probe: don't fail during startup
   - Pre-pull images: imagePullPolicy=IfNotPresent

4. **HPA lag** (30s → 5s)
   - Reduce evaluation period (default 15s)
   - Use prediction metrics (not yet in v2)

---

## 6. Monitoring & Observability

### 6.1 Prometheus Setup
**Q: How is Prometheus configured to collect metrics?**

**Model Answer**:

**Prometheus Architecture**:

```
Prometheus Pod (kube-prometheus-stack)
├── ServiceMonitor: tenant-website-monitor
│   └── Selector: app=user1-website
│       ↓ (discovers Service + endpoints)
├── Scrape Job: kubernetes-pods
│   └── Scrapes /metrics endpoint
│       ├── Pod IP: 10.244.x.x:3000
│       ├── Path: /metrics
│       └── Interval: 30s
│
Pods publish metrics on :3000/metrics
├── http_requests_total{tenant="user1", method="GET"}
├── http_request_duration_seconds{tenant="user1"}
├── process_resident_memory_bytes
└── [Kubernetes native metrics from kubelet]
```

**ServiceMonitor** (auto-discovery):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tenant-website-monitor
  namespace: user1
spec:
  selector:
    matchLabels:
      app: user1-website
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
```

**Why ServiceMonitor?**
- ✅ Auto-discovery (no manual scrape config)
- ✅ Updates when Service endpoints change
- ✅ Per-namespace isolation
- ❌ Alternative: Manual scrape job in prometheus.yml (harder to scale)

**Metrics collected**:

1. **Application metrics** (from /metrics endpoint)
   ```
   http_requests_total{tenant="user1", method="GET", status="200"}
   http_request_duration_seconds{tenant="user1", path="/health"}
   process_resident_memory_bytes
   process_cpu_seconds_total
   ```

2. **Kubernetes metrics** (from kubelet)
   ```
   container_cpu_usage_seconds_total
   container_memory_usage_bytes
   container_network_receive_bytes_total
   pod_memory_usage_bytes
   ```

3. **HPA metrics** (from metrics-server)
   ```
   kube_hpa_status_current_replicas
   kube_hpa_status_desired_replicas
   kube_horizontalpodautoscaler_status_current_metrics
   ```

---

### 6.2 Grafana Dashboards
**Q: What dashboards are available to monitor tenants?**

**Model Answer**:

**Pre-built Dashboards** (kube-prometheus-stack):

1. **HPA Current Replicas**
   ```
   Query: max(kube_hpa_status_current_replicas{namespace=~"user.*"})
   Visualization: Time series graph
   Shows: Scaling from 2 to 10 during load
   ```

2. **Memory Usage per Tenant**
   ```
   Query: container_memory_usage_bytes{pod=~"user.*"}
   Visualization: Time series, stacked
   Shows: Baseline ~150MB, peak ~250MB per pod
   Baseline × num_pods = total
   ```

3. **Pods per Tenant**
   ```
   Query: count(count(container_cpu_usage_seconds_total) by (pod)) by (namespace)
   Visualization: Time series
   Shows: 2 baseline, 8 peak
   ```

4. **CPU Usage per Tenant**
   ```
   Query: rate(container_cpu_usage_seconds_total[5m]) by (namespace)
   Visualization: Time series, stacked
   Shows: 0% baseline, 70%+ during load
   ```

**Access**:

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80 --address 172.24.160.103 &

# Open: http://172.24.160.103:3000
# Login: admin / admin
```

**Custom dashboard** (optional):

```json
{
  "dashboard": {
    "title": "Yotto Multi-Tenant Platform",
    "panels": [
      {
        "title": "Requests per Second",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~'5..'}[5m])"
          }
        ]
      }
    ]
  }
}
```

---

### 6.3 Alerting & Thresholds
**Q: If you were to set up alerting, what conditions would you monitor?**

**Model Answer**:

**Alert Rules** (PrometheusRule):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: tenant-alerts
  namespace: monitoring
spec:
  groups:
  - name: tenant.rules
    interval: 30s
    rules:
    # High CPU usage
    - alert: TenantHighCPU
      expr: >
        (sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace))
        > 0.8
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "{{ $labels.namespace }} CPU > 80%"

    # Pod evictions
    - alert: PodEvicted
      expr: kube_pod_status_reason{reason="Evicted"} == 1
      for: 1m
      labels:
        severity: critical

    # HPA at max
    - alert: HPAMaxReplicas
      expr: >
        kube_hpa_status_current_replicas
        == kube_hpa_status_desired_replicas
        and kube_hpa_status_desired_replicas
        == kube_hpa_spec_max_replicas
      for: 5m
      labels:
        severity: warning

    # Deployment replica mismatch
    - alert: DeploymentReplicasMismatch
      expr: >
        kube_deployment_status_replicas_updated{namespace=~"user.*"}
        != kube_deployment_spec_replicas{namespace=~"user.*"}
      for: 2m
      labels:
        severity: critical

    # Certificate expiration
    - alert: CertExpiringSoon
      expr: >
        (certmanager_certificate_expiration_timestamp_seconds - time())
        / 86400 < 30
      for: 1h
      labels:
        severity: warning
```

**Alert destinations**:
- Slack webhook
- PagerDuty
- Email
- Custom webhook

---

## 7. Kafka & Event Streaming

### 7.1 Kafka Architecture
**Q: How is Kafka configured? What events does the platform publish?**

**Model Answer**:

**Kafka Setup** (Docker Compose):

```yaml
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.x
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:7.x
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://172.17.0.1:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
```

**Key configuration**:
- `KAFKA_ADVERTISED_LISTENERS`: Dual endpoints
  - `kafka:29092` (pod-to-broker, internal)
  - `172.17.0.1:9092` (host gateway, from pods)
- `ZOOKEEPER_CLIENT_PORT`: Zookeeper coordination
- Replication factor 1 (single broker, sufficient for demo)

**Topics**:

```
Topic: website-events
├── Partitions: 3
├── Replication factor: 1
└── Retention: 7 days (default)

Event schema:
{
  "event": "WebsiteCreated|DeploymentTriggered|DeploymentSucceeded|DeploymentRolledBack",
  "tenant": "user1",
  "timestamp": "2026-03-16T10:30:00Z",
  "version": "sha-abc123def456"
}
```

**Events published**:

1. **WebsiteCreated** (app startup)
   ```javascript
   // apps/website/src/index.js
   const producer = kafka.producer();
   await producer.send({
     topic: 'website-events',
     messages: [{
       value: JSON.stringify({
         event: 'WebsiteCreated',
         tenant: process.env.TENANT_NAME,
         timestamp: new Date().toISOString(),
         version: process.env.VERSION
       })
     }]
   });
   ```

2. **DeploymentTriggered** (CI pipeline starts)
   - Published manually: `node notify.js --event DeploymentTriggered`

3. **DeploymentSucceeded** (pods ready)
   - CI/CD pipeline, after verify-deployment succeeds

4. **DeploymentRolledBack** (rollback executed)
   - CI/CD pipeline, if verify-deployment fails

**Kafka consumer** (listens for events):

```javascript
// kafka/consumer/consumer.js
const consumer = kafka.consumer({ groupId: 'yotto-consumers' });
await consumer.subscribe({ topic: 'website-events' });
await consumer.run({
  eachMessage: async ({ topic, partition, message }) => {
    const event = JSON.parse(message.value.toString());
    console.log(`Event: ${event.event}, Tenant: ${event.tenant}`);
    // Process event (e.g., update UI, trigger webhook)
  }
});
```

---

### 7.2 Kafka Access from Pods
**Q: Why do pods use 172.17.0.1:9092 instead of localhost:9092?**

**Model Answer**:

**Problem**: Network isolation in Docker + Kubernetes

```
Pod (10.244.x.x) → needs to reach Kafka (localhost on host)

Option 1: localhost:9092 ❌
  └─ "localhost" inside pod = 127.0.0.1 (pod loopback)
     └─ No service on pod loopback → connection refused

Option 2: host.docker.internal:9092 ❌
  └─ Not available in WSL2 (WSL limitation)

Option 3: 172.17.0.1:9092 ✅
  └─ 172.17.0.1 = docker0 bridge gateway (host from pod perspective)
     └─ Kafka listens on 9092 on the host
        └─ Traffic routes: pod → docker0 → host → Kafka
```

**Configured in Helm values**:

```yaml
# helm/tenant-website/values-user1.yaml
kafka:
  broker: "172.17.0.1:9092"
  topic: "website-events"
```

**App code**:

```javascript
const kafka = new Kafka({
  clientId: 'tenant-website',
  brokers: [process.env.KAFKA_BROKER]  // 172.17.0.1:9092
});
```

**Verification**:

```bash
# From inside pod
kubectl exec -it user1-website-7d8f9 -n user1 -- sh
$ nc -zv 172.17.0.1 9092
Connection to 172.17.0.1 9092 port [tcp/*] succeeded!
```

---

### 7.3 Event-Driven Architecture
**Q: How does the event-driven design benefit the platform?**

**Model Answer**:

**Benefits**:

1. **Async Communication**
   - Pipeline doesn't wait for webhook responses
   - Kafka acts as buffer
   - Consumers process at own pace

2. **Audit Trail**
   - All deployments recorded as events
   - Easy to investigate failures
   - Retention policy (7 days) for debugging

3. **Extensibility**
   - Add consumers without changing pipeline
   - Example: trigger Slack notification on DeploymentSucceeded
   - Kafka topic as integration point

4. **Decoupling**
   - CI/CD pipeline independent of consumers
   - Scale consumers separately
   - Failures don't block pipeline

**Event flow example**:

```
git push → GitHub Actions
  ├─ Build image
  ├─ Update Helm values
  ├─ Git push (triggers ArgoCD)
  └─ [Done, non-blocking]

ArgoCD sync (parallel)
  ├─ Detects git change
  ├─ Renders Helm
  ├─ kubectl apply
  └─ [Pods starting]

Deployment verification (parallel)
  ├─ Wait for pods ready
  ├─ Publish DeploymentSucceeded → Kafka topic
  └─ [Done]

Kafka consumers (independent):
  Consumer A: Update UI dashboard
  Consumer B: Send Slack notification
  Consumer C: Update analytics
  [All process independently]
```

---

## 8. Security

### 8.1 Network Isolation
**Q: How do you enforce network isolation between tenants?**

**Model Answer**:

**NetworkPolicy** (per-tenant):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-isolation
  namespace: user1
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

  # Ingress: who can send traffic TO pods
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring  # Prometheus scraping
    ports:
    - protocol: TCP
      port: 3000

  # Egress: where pods can send traffic
  egress:
  - to:
    - namespaceSelector: {}  # Any namespace
    ports:
    - protocol: TCP
      port: 9092  # Kafka
  - to:
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53  # DNS
  - to:
    - namespaceSelector: {}  # External APIs
    ports:
    - protocol: TCP
      port: 443
```

**Isolation enforced**:

```
✅ ALLOWED:
  - ingress-nginx:80 → user1 pods:3000 (routing)
  - Prometheus:9090 → user1 pods:3000/metrics (monitoring)
  - user1 pods → 172.17.0.1:9092 (Kafka)
  - user1 pods → DNS (10.96.0.10:53)

❌ BLOCKED:
  - user1 pods → user2 pods (cross-tenant)
  - user1 pods → user3 pods (cross-tenant)
  - user2 pods → user1 pods (blocked)
  - External → user1 pods (only ingress-nginx allowed)
```

**Verification**:

```bash
# From user1 pod
kubectl exec -it user1-website-7d8f9 -n user1 -- sh

# ✅ Can reach Kafka
$ curl 172.17.0.1:9092
# [Kafka protocol response]

# ✅ Can reach DNS
$ nslookup kubernetes.default.svc.cluster.local
# [DNS resolution]

# ❌ Cannot reach user2 pods
$ curl 10.244.x.x:3000  # user2 pod IP
# [timeout/connection refused]
```

---

### 8.2 Pod Security
**Q: What pod security controls are in place?**

**Model Answer**:

**Pod Security Context**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: user1-website
  namespace: user1
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000        # Don't run as root
    fsGroup: 1000

  containers:
  - name: app
    image: user1-website:sha-abc123
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true   # No write to /
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL                         # Drop all Linux caps

    volumeMounts:
    - name: tmp
      mountPath: /tmp                # Writable /tmp only
    - name: var-cache
      mountPath: /var/cache

  volumes:
  - name: tmp
    emptyDir: {}
  - name: var-cache
    emptyDir: {}
```

**Security benefits**:

| Control | Benefit | Why |
|---------|---------|-----|
| `runAsUser: 1000` | Can't write to system files | Limits blast radius |
| `readOnlyRootFilesystem: true` | Can't modify app binaries | Prevents privilege escalation |
| `capabilities.drop: ALL` | Can't use privileged syscalls | Reduces attack surface |
| `allowPrivilegeEscalation: false` | Can't gain root via suid | Defense in depth |

**Immutability enforced**:

```bash
# From pod
$ touch /test.txt
touch: cannot touch '/test.txt': Read-only file system

# But /tmp is writable
$ touch /tmp/test.txt
$ cat /tmp/test.txt
```

---

### 8.3 TLS & Encryption
**Q: How is HTTPS secured? Walk through certificate issuance.**

**Model Answer**:

**TLS Certificate Flow**:

```
1. Ingress created with annotation
   ├── cert-manager.io/cluster-issuer: selfsigned-issuer
   └── TLS hosts: user1.example.com

2. cert-manager webhook intercepts Ingress
   ├── Creates Certificate resource
   └── Watches for completion

3. cert-manager controller processes Certificate
   ├── Verifies domain ownership (not needed for self-signed)
   ├── Creates CSR (certificate signing request)
   └── Sends to issuer

4. Issuer (self-signed) signs cert
   ├── Uses bootstrap CA certificate
   ├── Signs user1.example.com cert
   └── Stores in Secret: user1-website-tls

5. ingress-nginx reads Secret
   ├── TLS termination on :443
   ├── Serves cert to clients
   └── Routes decrypted traffic to pods

6. Client (browser) receives cert
   ├── Verifies against trusted CA (browser's CA store)
   ├── For self-signed: browser shows warning
   └── With `-k` flag: curl ignores warning
```

**Certificate resource**:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: user1-website
  namespace: user1
spec:
  secretName: user1-website-tls
  commonName: user1.example.com
  dnsNames:
  - user1.example.com
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
```

**Issuer (self-signed)**:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

**Certificate verification**:

```bash
# Check cert in cluster
kubectl get certificate -n user1
kubectl describe certificate user1-website -n user1

# View cert details
kubectl get secret user1-website-tls -n user1 -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

# Test from client
curl -k https://user1.example.com
# -k: ignore self-signed warning (in production, use real CA)
```

---

## 9. Troubleshooting & Operations

### 9.1 Common Issues
**Q: What are common issues you'd encounter? How would you debug?**

**Model Answer**:

**Issue 1: Pods not starting**

**Symptoms**: `kubectl get pods -n user1` shows `ImagePullBackOff` or `CrashLoopBackOff`

```bash
# Debug steps:
kubectl logs -n user1 user1-website-7d8f9            # Container logs
kubectl describe pod user1-website-7d8f9 -n user1   # Events tab shows error
kubectl events -n user1 --field-selector involvedObject.name=user1-website-7d8f9

# Common causes:
1. Image not found in Docker Hub
   → Fix: Build & push image first

2. Image tag wrong in Helm values
   → Fix: Check helm/tenant-website/values-user1.yaml

3. Container crash (port binding, env var missing)
   → Fix: Check kubectl logs
```

---

**Issue 2: Ingress not routing traffic**

**Symptoms**: `curl user1.example.com` times out or 404

```bash
# Debug steps:
kubectl get ingress -n user1                      # Ingress exists?
kubectl get svc -n user1                          # Service exists?
kubectl get endpoints -n user1 user1-website      # Endpoints populated?
kubectl get pods -n ingress-nginx                 # Controller pod running?

# Common causes:
1. ingress-nginx not installed
   → Fix: kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/.../deploy.yaml

2. Ingress not ready (TLS cert not issued)
   → Check: kubectl describe ingress user1-website -n user1
   → Fix: Check cert-manager logs

3. Service has no endpoints (pods not running)
   → Fix: Debug pods first (Issue 1)

4. DNS not resolving
   → Fix: Add to /etc/hosts: 127.0.0.1 user1.example.com
```

---

**Issue 3: HPA not scaling**

**Symptoms**: `kubectl get hpa -n user1` shows TARGETS `<unknown>`

```bash
# Debug steps:
kubectl describe hpa user1-website -n user1       # Status, conditions
kubectl top pods -n user1                         # Metrics available?
kubectl get deployment -n user1 -o yaml | grep -A5 resources  # Requests/limits set?

# Common causes:
1. metrics-server not installed or not patched
   → Fix: Install with --kubelet-insecure-tls for kind

2. Pod doesn't have resource requests
   → Fix: Add requests in Deployment/Helm values

3. HPA evaluation lag (metrics take 2-3 min to appear)
   → Wait: metrics-server collects data before HPA acts
```

---

**Issue 4: Kafka unreachable from pods**

**Symptoms**: App logs show `ECONNREFUSED 172.17.0.1:9092`

```bash
# Debug steps:
docker-compose -f kafka/docker-compose.yml ps    # Kafka running?
docker network inspect kind | grep Gateway        # Get gateway IP
kubectl exec -it user1-website-7d8f9 -n user1 -- nc -zv 172.17.0.1 9092

# Common causes:
1. Kafka container not running
   → Fix: docker-compose -f kafka/docker-compose.yml up -d

2. Gateway IP changed (172.17.0.x varies)
   → Fix: Update helm/tenant-website/values.yaml with new IP

3. App env var not set
   → Fix: Check KAFKA_BROKER env var in Deployment
```

---

**Issue 5: ArgoCD not syncing**

**Symptoms**: ApplicationSet created but no Applications, or Applications not syncing

```bash
# Debug steps:
kubectl get applicationset -n argocd                  # ApplicationSet exists?
kubectl get applications -n argocd                    # Applications generated?
kubectl describe applicationset tenant-websites -n argocd  # Errors in status?

# Common causes:
1. Git credentials invalid
   → Fix: kubectl edit secret git-creds -n argocd

2. ApplicationSet template syntax error
   → Fix: Validate YAML, check generator

3. ArgoCD not watching git repo
   → Fix: Create Repository secret with git URL + token
```

---

### 9.2 Operational Tasks
**Q: What are the day-to-day operational tasks?**

**Model Answer**:

**Monitoring**:

```bash
# Daily health check
kubectl get nodes                                 # Nodes healthy?
kubectl get pods --all-namespaces                # All pods running?
kubectl top nodes                                # Node CPU/memory?
kubectl logs -n argocd deployment/argocd-server  # Any errors?
kubectl logs -n cert-manager deployment/cert-manager  # Cert issues?

# Grafana dashboard review
# http://localhost:3000
# Check: HPA, CPU, Memory, Error rates
```

**Scaling actions**:

```bash
# Manual pod scaling (if HPA misconfigured)
kubectl scale deployment user1-website -n user1 --replicas=5

# Update HPA limits
kubectl patch hpa user1-website -n user1 -p '{"spec":{"maxReplicas":20}}'

# Disable HPA temporarily
kubectl patch hpa user1-website -n user1 -p '{"spec":{"minReplicas":5,"maxReplicas":5}}'
```

**Deployments**:

```bash
# Check deployment status
kubectl rollout status deployment user1-website -n user1

# View rollout history
kubectl rollout history deployment user1-website -n user1

# Rollback if needed
kubectl rollout undo deployment user1-website -n user1

# Manual Helm upgrade
helm upgrade user1-website ./helm/tenant-website -f helm/tenant-website/values-user1.yaml -n user1
```

**Tenant management**:

```bash
# Add new tenant
bash scripts/create-tenant.sh user6

# Remove tenant
kubectl delete namespace user4
kubectl delete -f k8s/resource-quotas/user4-quota.yaml

# Update tenant config
kubectl set env deployment user1-website -n user1 ENVIRONMENT=production
```

**Backup & recovery**:

```bash
# Backup Helm values (git already handles this)
cp -r helm/tenant-website ~/backup/helm-$(date +%Y%m%d)

# Restore entire cluster
kind delete cluster --name yotto-cluster
bash scripts/bootstrap.sh

# Restore single tenant
git checkout helm/tenant-website/values-user1.yaml
kubectl apply -f argocd/applicationset.yaml
```

---

## 10. Design Decisions & Trade-offs

### 10.1 Why kind Instead of Cloud K8s?
**Q: Why did you choose kind for local development instead of deploying to AWS/GCP?**

**Pros of kind**:
- ✅ Free (no cloud costs)
- ✅ Fast cluster creation/destruction (2-3 min)
- ✅ Full K8s simulation (real Kubernetes API)
- ✅ Easy to debug (full access to cluster nodes)
- ✅ Perfect for CI/CD learning

**Cons of kind**:
- ❌ Single host (limited total CPU/memory)
- ❌ No managed services (you manage everything)
- ❌ NetworkPolicy requires CNI (not all K8s distributions)

**Alternative**: EKS/GKE
- ✅ Fully managed (AWS handles control plane)
- ✅ HA (built-in multi-AZ)
- ✅ Scales to 1000s of nodes
- ❌ Expensive ($73+ per month for control plane)
- ❌ Slower feedback loops

**Decision**: kind is ideal for learning, prototyping, and interviewing

---

### 10.2 Why ArgoCD Instead of Flux?
**Q: Why choose ArgoCD over Flux for GitOps?**

**ArgoCD**:
- ✅ UI dashboard (visualize apps)
- ✅ ApplicationSet (multi-tenancy native)
- ✅ Manual sync option (safer for demos)
- ✅ Rollback via UI

**Flux**:
- ✅ Lighter weight
- ✅ Native Kustomize support
- ✅ Faster deployment
- ❌ No UI (logs only)
- ❌ Auto-sync (harder to demo safely)

**Decision**: ArgoCD's UI and ApplicationSet are perfect for multi-tenant demos

---

### 10.3 Why Prometheus Instead of Commercial APM?
**Q: Why open-source Prometheus instead of Datadog/New Relic?**

**Prometheus**:
- ✅ Open-source (free)
- ✅ Kubernetes-native
- ✅ ServiceMonitor (easy auto-discovery)
- ✅ PrometheusRule (alerting)
- ✅ Industry standard for K8s

**Datadog/New Relic**:
- ✅ Managed (we don't operate it)
- ✅ More integrations
- ✅ Better UX
- ❌ Expensive ($0.30+ per host/hour)
- ❌ Overkill for demo

**Decision**: Prometheus sufficient for learning, upgradeable to commercial APM in production

---

## 11. Future Enhancements

### 11.1 What Would You Add?
**Q: If you had more time, what features would you implement?**

**Model Answer**:

1. **Persistent Storage for Tenants**
   ```
   Current: Stateless (app) + Kafka (transient events)
   Future: PostgreSQL per tenant + PersistentVolumeClaim

   Benefits:
   - Store user data
   - Multi-tenant databases with RBAC
   - Backup/restore per tenant
   ```

2. **Service Mesh (Istio)**
   ```
   Current: NetworkPolicy (network layer)
   Future: Istio for advanced traffic management

   Benefits:
   - Circuit breaker (fail-fast)
   - Retries with exponential backoff
   - Canary deployments (gradual rollouts)
   - mTLS (pod-to-pod encryption)
   ```

3. **Canary Deployments (Flagger)**
   ```
   Current: Blue-green (instant cutover)
   Future: Canary (5% → 50% → 100%)

   Benefits:
   - Catch errors early
   - Gradual rollout reduces blast radius
   - Automatic rollback on error rate spike
   ```

4. **Per-Tenant Logging (Loki)**
   ```
   Current: kubectl logs only
   Future: Centralized logging with tenant filtering

   Benefits:
   - Historical log retention
   - Full-text search
   - Multi-tenant isolation in logs
   ```

5. **Cost Allocation (Kubecost)**
   ```
   Current: No cost tracking
   Future: Kubecost for per-tenant cost breakdown

   Benefits:
   - Know which tenant costs most
   - Chargeback to tenants
   - Optimize resource allocation
   ```

6. **Multi-Region (GitOps Across Regions)**
   ```
   Current: Single kind cluster
   Future: Multiple clusters (us-west, eu-central, ap-southeast)

   Benefits:
   - Global availability
   - Disaster recovery
   - Regulatory compliance (data residency)
   ```

7. **Per-Tenant RBAC (Service Accounts)**
   ```
   Current: All pods same service account
   Future: RoleBinding per tenant

   Benefits:
   - Audit (who did what)
   - Fine-grained permissions
   - Prevent privilege escalation
   ```

8. **Webhook Triggers for ArgoCD**
   ```
   Current: 3-minute git polling
   Future: GitHub Webhook → ArgoCD REST API

   Benefits:
   - Immediate deployment (3 min → 10 sec)
   - Reduced API calls
   - Webhook confirmation
   ```

---

## Summary: 30-Second Elevator Pitch

**Interviewer asks: "Tell me about your Yotto project"**

**Your answer** (30 seconds):

> "Yotto is a multi-tenant DevOps platform deployed on Kubernetes. It uses kind (local K8s) with 5 tenant namespaces, each isolated via NetworkPolicy and ResourceQuota. The platform features:
>
> - **GitOps via ArgoCD ApplicationSet** for declarative multi-tenant deployments
> - **HPA auto-scaling** (2-10 pods per tenant based on CPU/memory)
> - **CI/CD pipeline** using GitHub Actions with auto-rollback on failure
> - **Kafka event streaming** for deployment notifications
> - **Prometheus/Grafana monitoring** with auto-discovery via ServiceMonitor
> - **HTTPS via cert-manager** with self-signed CA chain
>
> The design prioritizes isolation, scalability, and GitOps best practices—all demonstrated locally without cloud costs."

---

## Interview Tips

✅ **DO**:
- Explain concepts clearly (assume non-Kubernetes audience)
- Use diagrams/sketches to illustrate architecture
- Reference specific files (e.g., "see bootstrap.sh line 45")
- Discuss trade-offs (why this over that)
- Show hands-on expertise (run `kubectl get pods` in demo)

❌ **DON'T**:
- Memorize answers verbatim (sounds robotic)
- Dive into implementation details unless asked
- Overcomplicate explanations (KISS principle)
- Skip troubleshooting questions (shows operational maturity)
- Claim expertise you don't have (be honest about learning)

---

**Last Updated**: 2026-03-17
**Confidence Level**: 🟢 Ready for Interview
