#!/bin/bash

TENANT="${1:-user1}"
DOMAIN="${TENANT}.example.com"
REQUESTS="${2:-10000}"
CONCURRENCY="${3:-50}"

echo "=========================================="
echo "Load Test for $TENANT"
echo "=========================================="
echo ""

# Check if 'hey' is installed
if ! command -v hey &> /dev/null; then
  echo "[INFO] 'hey' not found. Installing from GitHub..."
  GO111MODULE=on go install github.com/rakyll/hey@latest
  if [ $? -ne 0 ]; then
    echo "✗ Failed to install 'hey'. Please install manually:"
    echo "  Windows: choco install hey"
    echo "  macOS: brew install hey"
    echo "  Linux: go install github.com/rakyll/hey@latest"
    exit 1
  fi
fi

echo "Configuration:"
echo "  Tenant: $TENANT"
echo "  Domain: $DOMAIN"
echo "  URL: https://$DOMAIN/"
echo "  Requests: $REQUESTS"
echo "  Concurrency: $CONCURRENCY"
echo ""

# Verify domain is reachable
echo "Verifying domain is reachable..."
if timeout 5 curl -k -s https://"$DOMAIN"/ > /dev/null 2>&1; then
  echo "✓ Domain is reachable"
else
  echo "✗ Domain is not reachable. Check if:"
  echo "  1. Cluster is running: kind get clusters"
  echo "  2. Domain is in /etc/hosts: grep example.com /etc/hosts"
  echo "  3. Ingress is configured: kubectl get ingress -n $TENANT"
  exit 1
fi

echo ""
echo "Starting load test in 3 seconds..."
sleep 3

echo ""
echo "[Load Test Output]"
hey -n "$REQUESTS" -c "$CONCURRENCY" -t 30 --insecure "https://$DOMAIN/"

echo ""
echo "=========================================="
echo "Checking HPA Status"
echo "=========================================="
echo ""

echo "HPA Metrics:"
kubectl get hpa -n "$TENANT" -o wide

echo ""
echo "Pod Count (should increase during load):"
kubectl get pods -n "$TENANT" -o wide

echo ""
echo "Deployment Replicas:"
kubectl get deployment -n "$TENANT" -o wide

echo ""
echo "✓ Load test complete"
echo ""
echo "Next steps:"
echo "  Watch HPA in real-time: kubectl get hpa -n $TENANT -w"
echo "  Watch pods scaling: kubectl get pods -n $TENANT -w"
echo "  Check metrics: kubectl top pods -n $TENANT"
