#!/bin/bash

# Quick start script to run the fixed bootstrap
# All issues have been resolved

set -e

echo "🚀 Starting Yotto Platform Bootstrap..."
echo ""

cd "$(dirname "${BASH_SOURCE[0]}")"

# Make scripts executable
chmod +x scripts/*.sh

# Run bootstrap
bash scripts/bootstrap.sh

echo ""
echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Verify cluster: kubectl get nodes"
echo "2. Check ingress-nginx: kubectl get pods -n ingress-nginx"
echo "3. Verify all components: bash scripts/verify-deployment.sh"
echo ""
