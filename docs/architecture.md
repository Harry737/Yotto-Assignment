# System Architecture & Design Decisions

## High-Level System Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet / LAN                           │
│                     (user1.example.com, etc.)                    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    localhost:80/443 (iptables port forward)
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
    ┌────────────────────────────────────────────────────────────┐
    │  KIND Cluster (Kubernetes 1.29+)                          │
    │  ┌────────────────────────────────────────────────────┐   │
    │  │  Control Plane (ingress-ready=true)               │   │
    │  │  - kubelet port 80/443 exposed to host            │   │
    │  │  - runs ingress-nginx controller pod              │   │
    │  └────────────────────────────────────────────────────┘   │
    │  ┌────────────────────────────────────────────────────┐   │
    │  │  Worker Node 1                                    │   │
    │  └────────────────────────────────────────────────────┘   │
    │  ┌────────────────────────────────────────────────────┐   │
    │  │  Worker Node 2                                    │   │
    │  └────────────────────────────────────────────────────┘   │
    └────────────────────────────────────────────────────────────┘
            │                                        │
            ▼                                        ▼
    ┌─────────────────────┐              ┌─────────────────────┐
    │  ingress-nginx      │              │  ArgoCD             │
    │  Controller         │              │  (GitOps Operator)  │
    │  watches Ingress    │              │  watches Git repo   │
    │  reloads nginx      │              │  syncs Helm charts  │
    └─────────────────────┘              └─────────────────────┘
            │
            ▼ (routes by hostname)
    ┌─────────────────────────────────────────┐
    │  Tenant Namespaces                     │
    │  ├── user1 (Namespace)                  │
    │  │   ├── Deployment: user1-website     │
    │  │   ├── Service: user1-website        │
    │  │   ├── Ingress: user1.example.com    │
    │  │   ├── HPA: 2-10 replicas            │
    │  │   ├── PDB: min 1 replica            │
    │  │   ├── NetworkPolicy: isolation      │
    │  │   └── ResourceQuota: limits         │
    │  ├── user2 (Namespace)                  │
    │  │   └── [same structure]              │
    │  └── user3 (Namespace)                  │
    │      └── [same structure]              │
    └─────────────────────────────────────────┘
            │
            ├─ (DNS resolve) ──────────────┐
            │                              │
            ▼                              ▼
    ┌─────────────────────┐      ┌─────────────────────┐
    │  Pod (Deployment)   │      │  /etc/hosts or      │
    │  Node.js Express    │      │  CoreDNS            │
    │  Listens :3000      │      │  (localhost → IP)   │
    │  /health, /metrics  │      └─────────────────────┘
    │  Sends to Kafka     │
    └─────────────────────┘
            │
            ▼
    ┌─────────────────────────────────────────┐
    │  Docker Compose (Host)                  │
    │  ├── Kafka Broker                       │
    │  │   - PLAINTEXT:9092 (for pods)       │
    │  │   - 172.17.0.1:9092 (pods use)      │
    │  └── Zookeeper                          │
    └─────────────────────────────────────────┘
            │
            ▼
    ┌─────────────────────────────────────────┐
    │  Prometheus + Grafana                   │
    │  (kube-prometheus-stack)                │
    │  - ServiceMonitor scrapes /metrics      │
    │  - Grafana NodePort 32000               │
    │  - Prometheus NodePort 32001            │
    └─────────────────────────────────────────┘
```

## Component Overview

### 1. Kind Cluster

**Purpose**: Local Kubernetes for development/testing

**Configuration**:
- 1 control-plane node (labeled `ingress-ready=true`)
- 2 worker nodes
- Port 80/443 mapped from container to host

**Why kind?**
- Fast cluster creation/destruction
- Simulates real K8s without cloud costs
- Docker-native (runs in containers)

### 2. ingress-nginx

**Purpose**: HTTP/HTTPS traffic routing & TLS termination

**Key Features**:
- Watches all Ingress resources cluster-wide
- Dynamic config reload (no pod restart)
- TLS cert integration with cert-manager
- Load balancing across Service endpoints

**Performance**:
- Single replica running on control-plane
- Can handle ~1000 req/sec per pod
- HPA can scale if needed

**Design decision**: NodePort instead of LoadBalancer (kind limitation)

### 3. cert-manager

**Purpose**: Automatic TLS certificate management

**Workflow**:
1. Ingress created with `cert-manager.io/cluster-issuer` annotation
2. cert-manager webhook intercepts
3. Creates Certificate resource
4. Verifies and signs the cert
5. Stores in Secret
6. ingress-nginx reads Secret and serves

**Security**: Self-signed CA chain (bootstrap issuer → CA cert → real issuer)

### 4. ArgoCD

**Purpose**: GitOps operator for declarative deployments

**Key Features**:
- Watches git repository
- Detects changes (push → ArgoCD sync)
- Helm chart templating
- Multi-tenancy via ApplicationSet

**Decision**: ApplicationSet file generator
- Scans for `values-*.yaml` files
- Auto-creates Applications (one per file)
- New tenant = new values file = auto-deploy

**Alternative considered**: Manual helm install per tenant
- ❌ Requires manual intervention
- ❌ Not declarative
- ❌ Hard to track state

### 5. GitHub Actions CI/CD

**Pipeline**:
1. **Build**: Docker build + push (tag: git SHA)
2. **Update**: Update Helm values with new image tag
3. **Sync**: Git push triggers ArgoCD sync
4. **Verify**: Self-hosted runner checks pod status
5. **Notify**: Publish Kafka event

**Self-hosted runner**: Required because
- kind cluster is local (GitHub-hosted runners can't reach it)
- Runner has kubeconfig and Docker daemon access
- Runs in WSL on Windows developer machine

**Rollback**: Automatic via `helm rollback` on failure

### 6. Kafka

**Purpose**: Event streaming for deployment notifications

**Topics**:
- `website-events` (3 partitions, replication factor 1)

**Events**:
- `WebsiteCreated` (app startup)
- `DeploymentTriggered` (CI pipeline)
- `DeploymentSucceeded` (deployment complete)
- `DeploymentRolledBack` (failure)

**Why Docker Compose?**
- Single-node sufficient for demo
- Easy local testing
- No K8s complexity

**Gotcha**: Pods can't reach localhost:9092 directly
- Solution: Use host gateway IP (172.17.0.1)
- Configured in Helm values.kafka.broker

### 7. Prometheus + Grafana

**Metrics collected**:
- Pod CPU, memory, network
- HTTP request duration (from /metrics endpoint)
- HPA scaling events
- Kubernetes state metrics

**Auto-scraping via ServiceMonitor**:
- Helm chart includes ServiceMonitor resource
- Prometheus discovers pods automatically
- No manual scrape config needed

**Grafana dashboards**:
- Pre-built Kubernetes dashboards
- Custom tenant-specific dashboard (optional)

## Multi-Tenancy Design

### Namespace Isolation

```
user1 namespace
├── Network Policies (only from ingress-nginx)
├── Resource Quotas (max CPU/memory per tenant)
├── Deployments (tenant-specific)
└── Ingress (domain routing)

user2 namespace
├── Network Policies
├── Resource Quotas
├── Deployments
└── Ingress

user3 namespace
├── Network Policies
├── Resource Quotas
├── Deployments
└── Ingress
```

**Why namespaces?**
- ✅ RBAC boundaries (future: per-tenant service accounts)
- ✅ Resource quota enforcement
- ✅ Network policy isolation
- ✅ Easy to audit (logs, events per namespace)

**Alternative considered**: RBAC-only without namespaces
- ❌ No resource quota enforcement
- ❌ Harder to enforce network isolation
- ❌ Single namespace = single failure domain

### Resource Quotas

Per-tenant limits:
```
CPU requests: 1 core
CPU limits: 2 cores
Memory requests: 1 GiB
Memory limits: 2 GiB
Pod count: 20
Services: 10
```

**Purpose**:
- Prevent one tenant from starving others
- Budget-aware (unit economics)
- Cluster-wide resource planning

### Network Policies

Tenant pods can receive traffic from:
1. ingress-nginx controller pods
2. Other pods in same namespace (for monitoring, etc.)

Tenant pods can send traffic to:
1. Any namespace (for Kafka, DNS, external APIs)

**Why this design?**
- Strict ingress policy (only from ingress-nginx)
- Relaxed egress (pods need external connectivity)
- Monitors can scrape /metrics from same namespace

## Auto-Scaling Strategy

### Horizontal Pod Autoscaler (HPA v2)

```yaml
minReplicas: 2
maxReplicas: 10
cpu: 60%
memory: 70%
```

**Scaling thresholds**:
- CPU utilization > 60% → scale up
- Memory utilization > 70% → scale up
- Idle for 5 minutes → scale down

**Why v2?**
- Multiple metrics (CPU + memory)
- Better scale-up behavior (metrics.k8s.io API)
- More predictable than v1

**Required**: metrics-server with `--kubelet-insecure-tls` patch (for kind)

### Pod Disruption Budget

```yaml
minAvailable: 1
```

**Purpose**: During cluster maintenance (node drain), ensure min 1 pod stays running
- Prevents all pods from being evicted simultaneously
- Maintains service availability during updates

## Load Testing & Validation

### Load Test Workflow

```bash
bash scripts/load-test.sh user1 5000 50
```

This:
1. Sends 5000 HTTP requests with 50 concurrent connections
2. Monitors HPA metrics in real-time
3. Pod count increases as CPU > 60%
4. After traffic stops, pods scale down after 5 minutes

**Validation points**:
- ✅ HPA detects CPU utilization spike
- ✅ New pods created (watch pods)
- ✅ Traffic distributed by Service
- ✅ Pods scale down after idle period
- ✅ Grafana shows scaling graph

## Deployment Strategy: Blue-Green via Helm

**Traditional rolling update**:
- Gradually replace old pods with new ones
- Risk: Brief period where mixed versions serve traffic

**Our approach** (Helm + ArgoCD):
1. Old release still active (all pods running)
2. New release deployed with new image
3. Old pods terminated once new ones are ready
4. Rollback: `helm rollback` to previous release

**Advantages**:
- Fast rollback (just Helm command)
- No manual traffic cutover
- Atomic deployment (all-or-nothing)

**Gotcha**: Both releases can't have same pod selector
- Solved by: Helm release name in labels

## Security Posture

### Pod-Level Security

- **Non-root user**: uid 1000
- **Read-only filesystem**: Except /tmp
- **Dropped capabilities**: ALL (minimal attack surface)
- **Resource limits**: Prevent resource exhaustion attacks

### Network-Level Security

- **NetworkPolicy**: Strict ingress, egress to Kafka only
- **TLS enforcement**: All traffic encrypted
- **TLS cert verification**: cert-manager validates

### RBAC (Future)

- Per-tenant service accounts (not yet implemented)
- RoleBindings for audit/access logs

## Disaster Recovery

### Backup Strategy

**What to backup**:
1. Helm values files (in git = backup free)
2. Kubernetes secrets (TLS certs, ArgoCD token)
3. Kafka topics (for event audit trail)

**Current state**:
- ✅ Helm values in git (version controlled)
- ⚠️ Secrets not backed up (cert-manager re-issues)
- ⚠️ Kafka data not persistent (for demo only)

**Production recommendations**:
- Velero for cluster backups
- External secret store (HashiCorp Vault, AWS Secrets)
- Persistent Kafka volumes

### Recovery Plan

**Cluster failure**:
1. `kind delete cluster --name yotto-cluster`
2. `bash scripts/bootstrap.sh` (recreate entire cluster)
3. ArgoCD re-deploys all applications from git

**Pod failure**:
- Deployment controller automatically recreates
- HPA ensures min replicas

**Tenant data loss**:
- Not applicable (stateless app)
- Kafka events are ephemeral (demo only)

## Performance Metrics

### Expected Performance

| Metric | Value |
|--------|-------|
| Cluster creation | 2-3 minutes |
| Application deployment | 30-60 seconds |
| Ingress reload | 30 seconds |
| TLS cert issuance | 10-20 seconds |
| HPA scaling | 30-60 seconds |
| Pod startup time | 3-5 seconds |
| Request latency (empty) | 5-10ms |
| Throughput (per pod) | 500-1000 req/sec |

### Bottlenecks

1. **ArgoCD sync interval**: Default 3 minutes (configurable)
   - Can reduce to 1 minute for faster deployments
   - Or use webhooks (GitHub → ArgoCD) for immediate trigger

2. **ingress-nginx reload**: ~30 seconds
   - innate to nginx reloading
   - Can't be improved without sacrificing stability

3. **kind cluster performance**: Single host
   - Fine for demo (3 tenants × 10 pods max)
   - Production: Use managed K8s (EKS, GKE, AKS)

## Cost Analysis (Cloud Deployment)

**If deployed to AWS EKS**:

| Component | Cost |
|-----------|------|
| EKS control plane | $73/month |
| 3 m5.large nodes | $150/month |
| NAT gateway | $32/month |
| Total | ~$255/month |

**Optimization**:
- Use spot instances for workers (30-70% savings)
- Scale down non-prod clusters at night
- Consolidated tenants → fewer nodes

## Future Enhancements

1. **Multiple clusters**: Federation for HA
2. **Persistent storage**: StatefulSets for databases
3. **Service mesh**: Istio for advanced traffic management
4. **Cost optimization**: Kubecost for chargeback
5. **Multi-region**: Global load balancing
6. **Canary deployments**: Flagger for gradual rollouts

---

**Last Updated**: March 2024
