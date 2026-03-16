#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if tenant name is provided
if [ -z "$1" ]; then
  echo -e "${RED}Usage: $0 <tenant-name>${NC}"
  echo "Example: $0 user4"
  exit 1
fi

TENANT_NAME="$1"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="$PROJECT_DIR/helm/tenant-website/values-${TENANT_NAME}.yaml"
APPSET_FILE="$PROJECT_DIR/argocd/applicationset.yaml"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating Tenant: ${TENANT_NAME}${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Check if tenant already exists
if [ -f "$VALUES_FILE" ]; then
  echo -e "${RED}✗ Tenant $TENANT_NAME already exists${NC}"
  exit 1
fi

# Step 2: Create values file from user1 template
echo -e "${BLUE}Step 1: Creating Helm values file...${NC}"
cp "$PROJECT_DIR/helm/tenant-website/values-user1.yaml" "$VALUES_FILE"
sed -i "s/user1/${TENANT_NAME}/g" "$VALUES_FILE"
echo -e "${GREEN}✓ Created $VALUES_FILE${NC}"

# Step 3: Check if ApplicationSet needs updating
echo -e "${BLUE}Step 2: Updating ApplicationSet...${NC}"

# Check if tenant already in ApplicationSet
if grep -q "tenant: ${TENANT_NAME}" "$APPSET_FILE"; then
  echo -e "${GREEN}✓ Tenant already in ApplicationSet${NC}"
else
  # Add tenant to ApplicationSet before the last "- tenant:" entry
  # Find the line number of the last tenant entry
  LAST_LINE=$(grep -n "tenant: user3" "$APPSET_FILE" | tail -1 | cut -d: -f1)

  if [ -z "$LAST_LINE" ]; then
    echo -e "${RED}✗ Could not find user3 in ApplicationSet${NC}"
    exit 1
  fi

  # Insert new tenant after the last tenant entry
  INSERT_LINE=$((LAST_LINE + 2))
  sed -i "${INSERT_LINE}i\\      - tenant: ${TENANT_NAME}\\n        namespace: ${TENANT_NAME}" "$APPSET_FILE"
  echo -e "${GREEN}✓ Updated ApplicationSet${NC}"
fi

# Step 4: Create namespace
echo -e "${BLUE}Step 3: Creating Kubernetes namespace...${NC}"
if kubectl get namespace "$TENANT_NAME" &>/dev/null; then
  echo -e "${GREEN}✓ Namespace $TENANT_NAME already exists${NC}"
else
  kubectl create namespace "$TENANT_NAME"
  echo -e "${GREEN}✓ Created namespace: $TENANT_NAME${NC}"
fi

# Step 5: Create resource quota and network policy if needed
echo -e "${BLUE}Step 4: Creating ResourceQuota...${NC}"
if [ -f "$PROJECT_DIR/k8s/resource-quotas/${TENANT_NAME}-quota.yaml" ]; then
  echo -e "${GREEN}✓ ResourceQuota file already exists${NC}"
else
  # Create quota from user1 template
  cp "$PROJECT_DIR/k8s/resource-quotas/user1-quota.yaml" "$PROJECT_DIR/k8s/resource-quotas/${TENANT_NAME}-quota.yaml"
  sed -i "s/user1/${TENANT_NAME}/g" "$PROJECT_DIR/k8s/resource-quotas/${TENANT_NAME}-quota.yaml"
  kubectl apply -f "$PROJECT_DIR/k8s/resource-quotas/${TENANT_NAME}-quota.yaml"
  echo -e "${GREEN}✓ Applied ResourceQuota${NC}"
fi

# Step 6: Update domain ConfigMap
echo -e "${BLUE}Step 5: Updating domain mappings...${NC}"
if [ -f "$PROJECT_DIR/k8s/ingress/domain-configmap.yaml" ]; then
  if ! grep -q "${TENANT_NAME}.example.com" "$PROJECT_DIR/k8s/ingress/domain-configmap.yaml"; then
    # Add domain mapping to ConfigMap (this is manual, user needs to do it)
    echo -e "${BLUE}Note: Add this to k8s/ingress/domain-configmap.yaml manually:${NC}"
    echo -e "${BLUE}  ${TENANT_NAME}.example.com: ${TENANT_NAME}/${TENANT_NAME}-website-tenant-website${NC}"
  fi
fi

# Step 7: Add to /etc/hosts (optional)
echo -e "${BLUE}Step 6: Adding to /etc/hosts (requires sudo)...${NC}"
if grep -q "${TENANT_NAME}.example.com" /etc/hosts 2>/dev/null; then
  echo -e "${GREEN}✓ Already in /etc/hosts${NC}"
else
  if sudo grep -q "127.0.0.1.*example.com" /etc/hosts 2>/dev/null; then
    # Add to existing example.com line
    sudo sed -i "/example.com/s/$/ ${TENANT_NAME}.example.com/" /etc/hosts
    echo -e "${GREEN}✓ Added to /etc/hosts${NC}"
  else
    echo -e "${BLUE}⚠ Please add manually: 127.0.0.1 ${TENANT_NAME}.example.com${NC}"
  fi
fi

# Step 8: Git commit and push
echo -e "${BLUE}Step 7: Committing and pushing changes...${NC}"
cd "$PROJECT_DIR"

git add "helm/tenant-website/values-${TENANT_NAME}.yaml"
git add "argocd/applicationset.yaml"

# Only add quota file if it was newly created
if [ -f "$PROJECT_DIR/k8s/resource-quotas/${TENANT_NAME}-quota.yaml" ]; then
  git add "k8s/resource-quotas/${TENANT_NAME}-quota.yaml"
fi

if git diff --cached --quiet; then
  echo -e "${BLUE}No changes to commit${NC}"
else
  git commit -m "feat: add ${TENANT_NAME} tenant"
  git push origin master
  echo -e "${GREEN}✓ Pushed to repository${NC}"
fi

# Step 8.5: Wait for ArgoCD to create Application from ApplicationSet
echo -e "${BLUE}Step 8.5: Waiting for ArgoCD to create Application...${NC}"
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  if kubectl get application ${TENANT_NAME}-website -n argocd &>/dev/null; then
    echo -e "${GREEN}✓ Application ${TENANT_NAME}-website created by ArgoCD${NC}"
    break
  fi
  echo -e "${BLUE}Waiting for Application creation... ($ELAPSED/$TIMEOUT seconds)${NC}"
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${BLUE}⚠ Application not auto-created, applying ApplicationSet manually...${NC}"
  kubectl apply -f "$PROJECT_DIR/argocd/applicationset.yaml"
  sleep 5
fi

# Step 9: Wait for ArgoCD sync
echo -e "${BLUE}Step 9: Waiting for ArgoCD to sync...${NC}"
echo -e "${BLUE}This may take 30-60 seconds...${NC}"
sleep 10

# Check deployment status
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  POD_COUNT=$(kubectl get pods -n "$TENANT_NAME" -l app.kubernetes.io/name=tenant-website 2>/dev/null | grep -c Running || echo 0)

  if [ "$POD_COUNT" -ge 2 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    break
  fi

  echo -e "${BLUE}Waiting for pods... ($ELAPSED/$TIMEOUT seconds)${NC}"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${RED}✗ Timeout waiting for deployment${NC}"
  exit 1
fi

# Step 10: Verify
echo -e "${BLUE}Step 9: Verifying deployment...${NC}"
echo ""
echo -e "${BLUE}Pods in namespace ${TENANT_NAME}:${NC}"
kubectl get pods -n "$TENANT_NAME" -o wide

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Tenant ${TENANT_NAME} created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Access your website:${NC}"
echo -e "${BLUE}  https://${TENANT_NAME}.example.com${NC}"
echo ""
echo -e "${BLUE}View logs:${NC}"
echo -e "${BLUE}  kubectl logs -n ${TENANT_NAME} -l app.kubernetes.io/name=tenant-website${NC}"
echo ""
echo -e "${BLUE}Watch deployment:${NC}"
echo -e "${BLUE}  kubectl get pods -n ${TENANT_NAME} -w${NC}"
echo ""
