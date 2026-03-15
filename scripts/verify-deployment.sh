#!/bin/bash

echo "=========================================="
echo "Deployment Verification"
echo "=========================================="
echo ""

log_section() {
  echo ""
  echo "── $1 ──"
  echo ""
}

# Check cluster status
log_section "Cluster Status"
echo "Nodes:"
kubectl get nodes -o wide

echo ""
echo "Namespaces:"
kubectl get ns

# Check each tenant
for tenant in user1 user2 user3; do
  log_section "Tenant: $tenant"

  echo "All resources:"
  kubectl get all -n "$tenant"

  echo ""
  echo "Pods (detailed):"
  kubectl get pods -n "$tenant" -o wide

  echo ""
  echo "Ingress:"
  kubectl get ingress -n "$tenant" -o wide

  echo ""
  echo "Services:"
  kubectl get svc -n "$tenant" -o wide

  echo ""
  echo "HPA Status:"
  kubectl get hpa -n "$tenant"

  echo ""
  echo "ResourceQuota:"
  kubectl get resourcequota -n "$tenant"

  echo ""
  echo "Certificates:"
  kubectl get certificate -n "$tenant" 2>/dev/null || echo "  (No certificates in namespace)"

  echo ""
  echo "Pod Logs (last 10 lines):"
  POD=$(kubectl get pods -n "$tenant" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    echo "  Latest pod: $POD"
    kubectl logs -n "$tenant" "$POD" --tail=10 || echo "    (Unable to get logs)"
  else
    echo "  (No pods found)"
  fi
done

# Check cert-manager
log_section "cert-manager Status"
echo "ClusterIssuers:"
kubectl get clusterissuer

echo ""
echo "Certificates (all namespaces):"
kubectl get certificate -A

# Check ArgoCD
log_section "ArgoCD Status"
echo "ArgoCD Applications:"
kubectl get applications -n argocd -o wide 2>/dev/null || echo "  (ArgoCD not found)"

# Check Kafka
log_section "Kafka Status"
echo "Kafka containers (Docker):"
docker ps --filter "label=com.docker.compose.project=yotto-assignment" --format "table {{.Names}}\t{{.Status}}" || \
  docker ps --filter "name=kafka" --filter "name=zookeeper" --format "table {{.Names}}\t{{.Status}}" || \
  echo "  (Kafka containers not found)"

# Health checks with curl
log_section "Health Checks (curl)"
for tenant in user1 user2 user3; do
  domain="$tenant.example.com"
  echo "Testing https://$domain/health:"

  response=$(curl -s -k -w "\n%{http_code}" "https://$domain/health" 2>&1 | tail -2)
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n-1)

  if [ "$http_code" = "200" ]; then
    echo "  ✓ HTTP $http_code"
    echo "  Response: $body"
  else
    echo "  ✗ HTTP $http_code"
    echo "  Response: $body"
  fi
  echo ""
done

# Monitoring
log_section "Monitoring Stack"
echo "Prometheus:"
kubectl get svc -n monitoring prometheus-community-kube-prom-prometheus 2>/dev/null || echo "  (Prometheus not found)"

echo ""
echo "Grafana:"
kubectl get svc -n monitoring prometheus-community-grafana 2>/dev/null || echo "  (Grafana not found)"

# Summary
log_section "Summary"
echo "Access URLs:"
echo "  Kubernetes: kubectl configured"
echo "  ArgoCD: https://localhost:32002 (check initial password)"
echo "  Grafana: http://localhost:32000 (admin/admin123)"
echo "  Prometheus: http://localhost:32001"
echo ""
echo "Test Domains:"
for tenant in user1 user2 user3; do
  echo "  https://$tenant.example.com"
done
echo ""
echo "Useful commands:"
echo "  Watch pods: kubectl get pods -n user1 -w"
echo "  Watch HPA: kubectl get hpa -n user1 -w"
echo "  Pod metrics: kubectl top pods -n user1"
echo "  Pod logs: kubectl logs -n user1 -l app.kubernetes.io/instance=user1-website -f"
echo ""
