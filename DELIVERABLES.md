# Assignment Deliverables ✅

## Overview

Complete DevOps solution for multi-tenant website hosting platform with Kubernetes, GitOps, CI/CD, Kafka, and observability.

---

## 1. Multi-Tenant Deployment & Dynamic Domain Mapping ✅

### Deliverable: Deploy 3 user websites in separate namespaces with dynamic domain mapping

**Completed**:

- ✅ **3 tenant namespaces** with isolation:
  - `k8s/namespaces/user1-namespace.yaml`
  - `k8s/namespaces/user2-namespace.yaml`
  - `k8s/namespaces/user3-namespace.yaml`

- ✅ **Helm chart for multi-tenant deployment**:
  - `helm/tenant-website/` — Single chart used for all 3 tenants
  - `helm/tenant-website/values-user1.yaml`
  - `helm/tenant-website/values-user2.yaml`
  - `helm/tenant-website/values-user3.yaml`

- ✅ **Ingress with TLS**:
  - `helm/tenant-website/templates/ingress.yaml` — Auto-TLS with cert-manager
  - Self-signed CA chain via `k8s/cert-manager/cluster-issuer.yaml`

- ✅ **Readiness & liveness probes**:
  - Deployed in `helm/tenant-website/templates/deployment.yaml`
  - Endpoint: `/health` on port 3000
  - Initial delay: 5s / 15s (readiness/liveness)

- ✅ **Resource limits & requests**:
  - Deployment: 100m/128Mi (request), 500m/256Mi (limit)
  - ResourceQuota per namespace: max 1 CPU, 1 GiB memory per tenant

- ✅ **Network policies**:
  - `helm/tenant-website/templates/networkpolicy.yaml`
  - Ingress only from ingress-nginx controller namespace
  - Egress to Kafka broker & DNS

- ✅ **Dynamic domain mapping**:
  - `k8s/ingress/domain-configmap.yaml` — Domain registry
  - `docs/dynamic-domain-mapping.md` — Detailed explanation
  - Approach: ingress-nginx dynamic reload (no cluster restart)
  - Add new domain = push new values file → ArgoCD auto-deploys → ingress-nginx syncs
  - Zero downtime, zero cluster redeploy

### Proof of Work

To verify post-deployment:
```bash
# Check all resources
bash scripts/verify-deployment.sh

# kubectl get all per tenant
kubectl get all -n user1
kubectl get all -n user2
kubectl get all -n user3

# Test via curl (with TLS)
curl -k https://user1.example.com
curl -k https://user2.example.com
curl -k https://user3.example.com

# Should return: "Welcome to user{N}"
```

---

## 2. CI/CD Pipeline with Rollback & Event Trigger ✅

### Deliverable: GitHub Actions pipeline with build, deploy, rollback, and Kafka events

**Completed**:

- ✅ **Single CI/CD workflow file**:
  - `.github/workflows/ci.yml`
  - Triggers on push to `main` affecting `apps/website/**` or `helm/**`

- ✅ **Build pipeline**:
  - Job: `build-and-push`
  - Builds Docker image from `apps/website/Dockerfile`
  - Pushes to Docker Hub with tag: `sha-{git-sha}`
  - Outputs image tag for downstream jobs

- ✅ **Multi-tenant deployment**:
  - Job: `update-helm-values`
  - Updates `helm/tenant-website/values-user{1,2,3}.yaml` with new image tag
  - Commits back to git → triggers ArgoCD sync
  - Deploys to all 3 tenants in parallel via ArgoCD

- ✅ **Rollback on failure**:
  - Job: `rollback-on-failure` (runs if previous jobs fail)
  - Executes: `helm rollback user{1,2,3} 0 -n user{1,2,3}`
  - Reverts to previous release version

- ✅ **Kafka event trigger**:
  - Job: `notify-kafka`
  - Publishes: `DeploymentTriggered` event on pipeline start
  - Publishes: `DeploymentSucceeded` event on success
  - Publishes: `DeploymentRolledBack` event on rollback
  - Via: `node kafka/consumer/notify.js --event {EVENT} --tenant {TENANT}`

- ✅ **Verification step**:
  - Job: `verify-deployment` (self-hosted runner)
  - Checks pod rollout status: `kubectl rollout status deployment/...`
  - Runs on self-hosted runner (has access to local kind cluster)

### GitHub Secrets Required

Set in GitHub repo settings:
```
DOCKERHUB_USERNAME    # Your Docker Hub username
DOCKERHUB_TOKEN       # Docker Hub access token
```

### Proof of Work

Screenshots/logs to capture:
```bash
# 1. Successful deployment
# In GitHub Actions: see all jobs pass
# URL: https://github.com/YOUR_ORG/YOUR_REPO/actions

# 2. Rollback (intentional failure)
# Push a Dockerfile that fails to build
# Watch rollback job execute

# 3. Kafka event notifications
cd kafka/consumer
npm ci
node consumer.js
# Wait for:
# [Event #N] Event Type: DeploymentTriggered
# [Event #N+1] Event Type: DeploymentSucceeded
```

---

## 3. Scaling, Resource Optimization & Observability ✅

### Deliverable: HPA, resource quotas, PDB, load simulation, Prometheus/Grafana

**Completed**:

- ✅ **HPA per website**:
  - `helm/tenant-website/templates/hpa.yaml`
  - Auto-scaling v2 (CPU + memory metrics)
  - Min: 2 replicas, Max: 10 replicas
  - Triggers: CPU > 60%, Memory > 70%

- ✅ **Resource quotas per tenant**:
  - `k8s/resource-quotas/user{1,2,3}-quota.yaml`
  - Hard limits: 1 CPU / 1 GiB memory (requests), 2 CPU / 2 GiB (limits)
  - Enforces fair resource sharing

- ✅ **Pod Disruption Budget**:
  - `helm/tenant-website/templates/pdb.yaml`
  - Min available: 1 pod during cluster updates
  - Prevents service degradation during maintenance

- ✅ **Load testing script**:
  - `scripts/load-test.sh`
  - Usage: `bash scripts/load-test.sh user1 10000 50`
  - Sends 10k requests with 50 concurrent connections
  - Monitors HPA scaling in real-time
  - Uses 'hey' tool (auto-installed)

- ✅ **Prometheus + Grafana**:
  - Installed via: `kube-prometheus-stack` Helm chart
  - Prometheus NodePort: 32001
  - Grafana NodePort: 32000 (admin/admin123)
  - Auto-scrapes pod metrics via ServiceMonitor

- ✅ **Application metrics**:
  - `apps/website/src/index.js` exports `/metrics` endpoint
  - Uses `prom-client` library
  - Tracks: HTTP request duration, pod health, custom counters

- ✅ **ServiceMonitor for auto-discovery**:
  - `helm/tenant-website/templates/servicemonitor.yaml`
  - Prometheus auto-discovers and scrapes pods
  - Interval: 15 seconds

### Expected Scaling Behavior

```bash
# Before load test:
# Pods: 2 replicas per tenant
# CPU: ~5-10% idle

# During load test (10k req/s):
# Pods: Scale up from 2 → 10 replicas (within 1-2 min)
# CPU: >60% utilization
# Memory: >70% utilization

# After load test:
# Pods: Scale down from 10 → 2 replicas (after 5 min idle)
# CPU: Back to 5-10%
```

### Proof of Work

```bash
# 1. Run load test
bash scripts/load-test.sh user1 10000 50

# 2. Watch metrics (in parallel terminals)
kubectl get hpa -n user1 -w
kubectl get pods -n user1 -w
kubectl top pods -n user1

# 3. Open Grafana and screenshot dashboard
# http://localhost:32000
# Look for: pod CPU, memory, request latency spikes

# Expected screenshots:
# - HPA metrics showing scale-up
# - Pod count increasing
# - Grafana dashboard with graphs
```

---

## 4. Kafka Event-Driven Pipeline ✅

### Deliverable: Single-node Kafka, event publishing, consumer verification

**Completed**:

- ✅ **Single-node Kafka setup**:
  - `kafka/docker-compose.yml`
  - Confluent Kafka + Zookeeper
  - Dual listener (PLAINTEXT:9092 for host, INTERNAL:29092 for inter-broker)
  - Health checks, auto-restart

- ✅ **Topic initialization**:
  - `kafka/topics/init-topics.sh`
  - Creates topic: `website-events` (3 partitions, RF=1)
  - Waits for Kafka to be healthy before creating

- ✅ **Event schema**:
  ```json
  {
    "event": "WebsiteCreated|DeploymentTriggered|DeploymentSucceeded|DeploymentRolledBack",
    "tenant": "user1",
    "domain": "user1.example.com",
    "timestamp": "2024-03-15T10:00:00Z",
    "version": "sha-abc123"
  }
  ```

- ✅ **Event producer** (in app):
  - `apps/website/src/kafka-producer.js`
  - Publishes `WebsiteCreated` on pod startup
  - Connects to Kafka broker (configured via env var)

- ✅ **Event consumer**:
  - `kafka/consumer/consumer.js`
  - Subscribes to `website-events` topic
  - Prints events real-time (useful for verification)
  - Usage: `node kafka/consumer/consumer.js`

- ✅ **Event publisher CLI** (for CI/CD):
  - `kafka/consumer/notify.js`
  - Used by GitHub Actions to publish deployment events
  - Usage: `node notify.js --event {EVENT} --tenant {TENANT} --version {VERSION}`

### Proof of Work

```bash
# 1. Start consumer (in terminal 1)
cd kafka/consumer
npm ci
node consumer.js

# 2. Deploy an app (in terminal 2)
helm install user1-site-demo ./helm/tenant-website \
  -f helm/tenant-website/values-user1.yaml \
  -n user1

# 3. Watch events appear in consumer (terminal 1)
# [Event #1]
#   Topic: website-events
#   Event Type: WebsiteCreated
#   Tenant: user1
#   Domain: user1.example.com
#   Timestamp: 2024-03-15T10:00:00Z

# 4. Publish event via CLI
node kafka/consumer/notify.js \
  --event CustomEvent \
  --tenant user1 \
  --version v1.2.3

# 5. See event in consumer
```

---

## 5. Complete Deliverables List

### Git Repository Structure ✅

```
d:\Yotto-Assignment/
├── README.md                        # Main documentation
├── QUICK_START.md                   # 5-min setup guide
├── DELIVERABLES.md                  # This file
├── .gitignore                       # Git ignore rules
│
├── .github/
│   └── workflows/
│       └── ci.yml                   # GitHub Actions pipeline
│
├── apps/website/
│   ├── Dockerfile                   # Node.js container
│   ├── package.json                 # Dependencies
│   ├── .dockerignore
│   └── src/
│       ├── index.js                 # Express app + Kafka producer
│       └── kafka-producer.js        # Kafka event publisher
│
├── helm/tenant-website/
│   ├── Chart.yaml
│   ├── values.yaml                  # Default values
│   ├── values-user1.yaml
│   ├── values-user2.yaml
│   ├── values-user3.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── pdb.yaml
│       ├── networkpolicy.yaml
│       └── servicemonitor.yaml
│
├── k8s/
│   ├── cluster/
│   │   └── kind-config.yaml         # Kind cluster config
│   ├── namespaces/
│   │   ├── user1-namespace.yaml
│   │   ├── user2-namespace.yaml
│   │   └── user3-namespace.yaml
│   ├── resource-quotas/
│   │   ├── user1-quota.yaml
│   │   ├── user2-quota.yaml
│   │   └── user3-quota.yaml
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml      # TLS certificate issuance
│   └── ingress/
│       └── domain-configmap.yaml    # Domain registry
│
├── argocd/
│   └── applicationset.yaml          # Declarative app deployments
│
├── kafka/
│   ├── docker-compose.yml           # Kafka + Zookeeper
│   ├── consumer/
│   │   ├── consumer.js              # Event consumer
│   │   ├── notify.js                # Event publisher CLI
│   │   └── package.json
│   └── topics/
│       └── init-topics.sh           # Topic creation script
│
├── monitoring/
│   └── prometheus/
│       └── values.yaml              # Prometheus/Grafana config
│
├── scripts/
│   ├── bootstrap.sh                 # Full cluster setup (automated)
│   ├── setup-hosts.sh               # DNS setup (/etc/hosts)
│   ├── load-test.sh                 # Load testing + HPA demo
│   └── verify-deployment.sh         # Health check & verification
│
└── docs/
    ├── dynamic-domain-mapping.md    # Domain mapping explanation
    ├── architecture.md              # System architecture & design
    └── screenshots/                 # Proof-of-work screenshots
```

### Key Features Implemented ✅

| Feature | File(s) | Status |
|---------|---------|--------|
| Multi-tenant namespaces | `k8s/namespaces/` | ✅ |
| Helm chart (reusable) | `helm/tenant-website/` | ✅ |
| TLS certificates | `k8s/cert-manager/`, cert-manager Helm | ✅ |
| Ingress routing | `helm/tenant-website/templates/ingress.yaml` | ✅ |
| Health probes | `helm/tenant-website/templates/deployment.yaml` | ✅ |
| Resource quotas | `k8s/resource-quotas/` | ✅ |
| Network policies | `helm/tenant-website/templates/networkpolicy.yaml` | ✅ |
| HPA scaling | `helm/tenant-website/templates/hpa.yaml` | ✅ |
| PodDisruptionBudget | `helm/tenant-website/templates/pdb.yaml` | ✅ |
| Dynamic domain mapping | `docs/dynamic-domain-mapping.md` | ✅ |
| CI/CD pipeline | `.github/workflows/ci.yml` | ✅ |
| Deployment rollback | `.github/workflows/ci.yml` rollback job | ✅ |
| Kafka event streaming | `kafka/docker-compose.yml` + app integration | ✅ |
| Prometheus/Grafana | kube-prometheus-stack Helm + ServiceMonitor | ✅ |
| ArgoCD GitOps | `argocd/applicationset.yaml` | ✅ |
| Load testing | `scripts/load-test.sh` | ✅ |

---

## 6. How to Run & Verify

### Step 1: Bootstrap Cluster (10 minutes)

```bash
cd d:\Yotto-Assignment
chmod +x scripts/*.sh
bash scripts/bootstrap.sh
sudo bash scripts/setup-hosts.sh  # For Linux/macOS/WSL
```

### Step 2: Verify Everything Works

```bash
bash scripts/verify-deployment.sh

# Expected output:
# ✅ Cluster nodes ready
# ✅ Namespaces created
# ✅ Pods deployed
# ✅ Ingress configured
# ✅ Certificates issued
```

### Step 3: Test Each Deliverable

**Test 1: Multi-tenant websites**
```bash
curl -k https://user1.example.com
curl -k https://user2.example.com
curl -k https://user3.example.com
# Expected: HTML pages for each tenant
```

**Test 2: Scaling (HPA)**
```bash
bash scripts/load-test.sh user1 10000 50
# Watch: kubectl get hpa -n user1 -w
# Expected: Pods scale from 2 → 10
```

**Test 3: Kafka events**
```bash
cd kafka/consumer && npm ci
node consumer.js
# Expected: WebsiteCreated events appear
```

**Test 4: Grafana dashboards**
```bash
# Open: http://localhost:32000
# Login: admin / admin123
# Expected: Dashboards showing metrics
```

**Test 5: ArgoCD deployments**
```bash
# Open: https://localhost:32002
# Expected: Applications for user1, user2, user3 all Synced
```

**Test 6: CI/CD pipeline** (requires GitHub setup)
```bash
git push origin main
# Expected: GitHub Actions runs, builds image, updates values, ArgoCD syncs
```

---

## 7. Assignment Completion Summary

| Requirement | Evidence | Status |
|-------------|----------|--------|
| 3 user websites in separate namespaces | `k8s/namespaces/`, `kubectl get ns` | ✅ |
| Helm charts for deployment | `helm/tenant-website/Chart.yaml` | ✅ |
| Ingress with TLS | ingress annotations + cert-manager | ✅ |
| Health probes | deployment.yaml readiness/liveness | ✅ |
| Resource limits/requests | deployment.yaml resources | ✅ |
| Network policies | networkpolicy.yaml | ✅ |
| Dynamic domain mapping | docs/dynamic-domain-mapping.md | ✅ |
| CI/CD pipeline (build/push) | .github/workflows/ci.yml build job | ✅ |
| Rollback on failure | ci.yml rollback-on-failure job | ✅ |
| Kafka event trigger | ci.yml notify-kafka job | ✅ |
| HPA for scaling | hpa.yaml + load-test.sh | ✅ |
| Resource quotas | k8s/resource-quotas/ | ✅ |
| PodDisruptionBudget | pdb.yaml | ✅ |
| Prometheus/Grafana | kube-prometheus-stack | ✅ |
| Single-node Kafka | kafka/docker-compose.yml | ✅ |
| Kafka event consume | kafka/consumer/consumer.js | ✅ |
| Kafka event publish | kafka/consumer/notify.js | ✅ |
| Load simulation | scripts/load-test.sh | ✅ |

---

## 8. Time to Complete

- **Bootstrap cluster**: 5-10 minutes
- **Verify all components**: 2-3 minutes
- **Run load test**: 2-3 minutes
- **Capture screenshots**: 5-10 minutes
- **Total**: ~20-30 minutes from zero to fully operational platform

---

## 9. Proof-of-Work Artifacts

Screenshots/logs to capture for submission:

1. `kubectl get all -n user1/user2/user3` output
2. `curl -k https://user{1,2,3}.example.com` responses
3. HPA scaling during load test (kubectl watch)
4. Grafana dashboard showing metrics
5. Kafka consumer receiving events
6. GitHub Actions successful deployment log
7. ArgoCD UI showing synced applications
8. Prometheus scrape targets

All can be generated via:
```bash
bash scripts/verify-deployment.sh > verification_output.txt
bash scripts/load-test.sh user1 > load_test_output.txt
```

---

## ✨ Summary

A **production-ready DevOps platform** implementing all assignment requirements:
- ✅ Multi-tenant isolation
- ✅ Auto-scaling
- ✅ GitOps deployments
- ✅ CI/CD pipeline
- ✅ Event-driven architecture
- ✅ Observability
- ✅ Zero-downtime domain addition

**Status**: Ready for deployment and demonstration. All deliverables complete.
