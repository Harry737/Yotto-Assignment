#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Yotto Multi-Tenant Platform - Bootstrap"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_step() {
  echo -e "${GREEN}[STEP]${NC} $1"
}

log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
log_step "Checking prerequisites..."

for cmd in kind kubectl helm docker docker-compose; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "$cmd not found. Please install it first."
    exit 1
  fi
done

echo "✓ All prerequisites are installed"

# Phase 1: Create kind cluster
log_step "Creating kind cluster..."

if kind get clusters 2>/dev/null | grep -q "yotto-cluster"; then
  log_info "Cluster 'yotto-cluster' already exists. Skipping creation."
else
  kind create cluster --config "$PROJECT_DIR/k8s/cluster/kind-config.yaml"
  echo "✓ Kind cluster created"
fi

# Wait for API server
log_info "Waiting for API server..."
kubectl wait --for=condition=ready node --all --timeout=300s || true
sleep 5

# Phase 2: Create namespaces
log_step "Creating namespaces..."
kubectl apply -f "$PROJECT_DIR/k8s/namespaces/"
echo "✓ Namespaces created"

# Phase 3: Create resource quotas
log_step "Creating resource quotas..."
kubectl apply -f "$PROJECT_DIR/k8s/resource-quotas/"
echo "✓ Resource quotas created"

# Phase 4: Install ingress-nginx
log_step "Installing ingress-nginx..."

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=80 \
  --set controller.service.nodePorts.https=443 \
  --set controller.nodeSelector."ingress-ready"=true \
  --set controller.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set controller.tolerations[0].operator=Equal \
  --set controller.tolerations[0].effect=NoSchedule \
  --wait \
  --timeout 300s

echo "✓ ingress-nginx installed"

# Phase 5: Install cert-manager
log_step "Installing cert-manager..."

helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install CRDs first
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml
sleep 10

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --wait \
  --timeout 300s

echo "✓ cert-manager installed"

# Install ClusterIssuer
log_step "Creating cert-manager ClusterIssuer..."
kubectl apply -f "$PROJECT_DIR/k8s/cert-manager/cluster-issuer.yaml"
sleep 5
echo "✓ ClusterIssuer created"

# Phase 6: Install metrics-server
log_step "Installing metrics-server..."

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server to skip TLS verification (required for kind)
sleep 10
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  || true

echo "✓ metrics-server installed and patched"

# Phase 7: Create domain ConfigMap
log_step "Creating domain registry ConfigMap..."
kubectl apply -f "$PROJECT_DIR/k8s/ingress/domain-configmap.yaml"
echo "✓ Domain registry created"

# Phase 8: Install ArgoCD
log_step "Installing ArgoCD..."

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePort=32002 \
  --wait \
  --timeout 300s

echo "✓ ArgoCD installed"

# Phase 9: Create ApplicationSet
log_step "Creating ApplicationSet for multi-tenant deployments..."

# Get the current repo URL from git (assuming this repo is on GitHub)
REPO_URL=$(cd "$PROJECT_DIR" && git config --get remote.origin.url || echo "https://github.com/YOUR_ORG/YOUR_REPO.git")

# Create a version of the ApplicationSet with the repo URL embedded
sed "s|'{{ .repo.url }}'|'$REPO_URL'|g" "$PROJECT_DIR/argocd/applicationset.yaml" | kubectl apply -f -

echo "✓ ApplicationSet created"
echo "  Repository: $REPO_URL"

# Phase 10: Start Kafka
log_step "Starting Kafka..."

cd "$PROJECT_DIR/kafka"
docker-compose up -d --remove-orphans

sleep 5
echo "✓ Kafka started"

# Phase 11: Initialize Kafka topics
log_step "Initializing Kafka topics..."

bash "$PROJECT_DIR/kafka/topics/init-topics.sh"

echo "✓ Kafka topics initialized"

# Phase 12: Install kube-prometheus-stack
log_step "Installing kube-prometheus-stack..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$PROJECT_DIR/monitoring/prometheus/values.yaml" \
  --wait \
  --timeout 300s

echo "✓ kube-prometheus-stack installed"

# Final: Print access information
echo ""
echo "=========================================="
echo "Bootstrap Complete!"
echo "=========================================="
echo ""
echo "Access Information:"
echo "  Kubernetes API:    kubectl (already configured)"
echo "  ArgoCD UI:          https://localhost:32002 (password: admin)"
echo "  Grafana:            http://localhost:32000 (admin/admin123)"
echo "  Prometheus:         http://localhost:32001"
echo ""
echo "Next steps:"
echo "  1. Configure GitHub Actions self-hosted runner (optional)"
echo "  2. Push code to trigger CI/CD pipeline"
echo "  3. Monitor ArgoCD for deployment status"
echo "  4. Verify deployments: kubectl get all -n user1"
echo "  5. Test curl: curl -k https://user1.example.com"
echo ""
echo "To access ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
