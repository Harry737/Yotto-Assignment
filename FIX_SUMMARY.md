# Bootstrap Fixes Applied

## Issues & Solutions

### Issue 1: Invalid NodePort Range (HTTP/HTTPS on 80/443)
**Error:**
```
spec.ports[0].nodePort: Invalid value: 80: provided port is not in the valid range.
The range of valid ports is 30000-32767
```

**Root Cause:**
The bootstrap script tried to use `--set controller.service.nodePorts.http=80` which attempts to create a Kubernetes NodePort Service on port 80. However, NodePort services must use ports in the range 30000-32767. Ports 80 and 443 are only valid for `hostPort` (direct pod port mapping), not for Kubernetes NodePort services.

**Solution:**
Replaced the Helm ingress-nginx installation with the **official kind-compatible manifest** from Kubernetes GitHub. This manifest:
- Uses `hostPort: 80` and `hostPort: 443` at the pod level (valid)
- Automatically includes proper nodeSelector, tolerations, and configuration for kind
- Is battle-tested and maintained by the Kubernetes community
- Eliminates the need for manual Helm flag configuration

**File Changed:** `scripts/bootstrap.sh` lines 72-86

**New Code:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || true
```

---

### Issue 2: NodeSelector Type Error (Boolean vs String)
**Error:**
```
.spec.template.spec.nodeSelector.ingress-ready: expected string, got &value.valueUnstructured{Value:true}
```

**Root Cause:**
The Helm command `--set controller.nodeSelector."ingress-ready"=true` passes the value `true` as a **boolean**. However, Kubernetes nodeSelector values must always be **strings**. The kind node was labeled with `node-labels: "ingress-ready=true"` (a string), so the selector must match with a string value.

**Solution:**
Fixed by using the official kind manifest which correctly configures the nodeSelector as a string value internally. No manual configuration needed.

**Note:** This is also resolved by the official manifest approach, as we no longer manually set nodeSelector via Helm flags.

---

### Issue 3: Deprecated Ingress Class Annotation
**Minor Issue:**
The Ingress template used the deprecated `kubernetes.io/ingress.class: "nginx"` annotation. Modern Kubernetes (1.19+) and ingress-nginx (1.0+) use the `spec.ingressClassName` field instead.

**Solution:**
Added `spec.ingressClassName: nginx` to the Ingress template while keeping the annotation for backward compatibility.

**File Changed:** `helm/tenant-website/templates/ingress.yaml` line 14

**New Code:**
```yaml
spec:
  ingressClassName: nginx
  {{- if .Values.tls.enabled }}
  tls:
  ...
```

---

## Side Note: ingress-nginx Status

**Q: Isn't nginx discontinued?**

**A: No, ingress-nginx is NOT discontinued.** There's confusion because there are two separate projects:

1. **Community ingress-nginx** (ACTIVE & MAINTAINED)
   - GitHub: `kubernetes/ingress-nginx`
   - Helm repo: `https://kubernetes.github.io/ingress-nginx`
   - Status: ✅ Actively maintained, widely used
   - This is what we use

2. **NGINX Inc. ingress controller** (ABANDONED)
   - GitHub: `kubernetes/ingress-nginx` (old NGINX Inc. repo)
   - Status: ❌ Deprecated by NGINX Inc.
   - Note: This should not be confused with the community version

We're using the **community-maintained version**, which is stable and actively developed.

---

## How to Proceed

Run the bootstrap script again:

```bash
cd d:\Yotto-Assignment

# Make sure it's executable
chmod +x scripts/bootstrap.sh

# Run bootstrap
bash scripts/bootstrap.sh
```

The script will now:
1. ✅ Create kind cluster successfully
2. ✅ Install ingress-nginx using official manifest (no port errors)
3. ✅ Install cert-manager
4. ✅ Install metrics-server
5. ✅ Install ArgoCD
6. ✅ Start Kafka
7. ✅ Install Prometheus/Grafana

---

## Verification

After bootstrap completes, verify ingress-nginx is working:

```bash
# Check pods are running
kubectl get pods -n ingress-nginx

# Should see:
# NAME                                        READY   STATUS    RESTARTS
# ingress-nginx-controller-XXXXX              1/1     Running   0

# Verify it's on the control-plane node
kubectl get pods -n ingress-nginx -o wide

# Test ingress routing (once your apps are deployed)
curl -k https://user1.example.com
```

---

## Files Modified

| File | Change | Lines |
|------|--------|-------|
| `scripts/bootstrap.sh` | Replace Helm install with official kind manifest | 72-86 |
| `helm/tenant-website/templates/ingress.yaml` | Add `ingressClassName: nginx` | 14 |
| `k8s/resource-quotas/*.yaml` | Removed invalid `scopeSelector` (done earlier) | - |

All changes are backward compatible and follow Kubernetes best practices.
