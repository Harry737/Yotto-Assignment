# Setting Up Prerequisites

You need to install these tools on your system. Follow the instructions for your OS.

## Windows (WSL2 Recommended)

### 1. Install WSL2 (Ubuntu)
```powershell
# Run as Administrator in PowerShell
wsl --install
wsl --install -d Ubuntu
```

### 2. Install Docker Desktop
- Download: https://www.docker.com/products/docker-desktop
- Enable WSL2 backend in settings
- Verify: `docker --version`

### 3. Install kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### 4. Install kind
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/
```

### 5. Install Helm
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 6. Verify All Installed
```bash
kind --version
kubectl version --client
helm version
docker --version
```

---

## macOS (Homebrew)

```bash
# Install kind
brew install kind

# Install kubectl
brew install kubectl

# Install helm
brew install helm

# Verify
kind --version
kubectl version --client
helm version
docker --version
```

Docker Desktop for macOS: https://www.docker.com/products/docker-desktop

---

## Linux (Ubuntu/Debian)

```bash
# Update package list
sudo apt update

# Install Docker
sudo apt install -y docker.io
sudo usermod -aG docker $USER
newgrp docker

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
kind --version
kubectl version --client
helm version
docker --version
```

---

## Verify Everything Works

Once installed, run:
```bash
cd d:\Yotto-Assignment
bash scripts/bootstrap.sh
```

This will:
1. Create kind cluster (2-3 min)
2. Install ingress-nginx, cert-manager, metrics-server
3. Setup ArgoCD
4. Start Kafka
5. Install Prometheus/Grafana

---

## Troubleshooting

### "docker not found"
- Ensure Docker Desktop is running
- On Linux: Add user to docker group: `sudo usermod -aG docker $USER`

### "kubectl not found in PATH"
- Verify installation: `which kubectl`
- If not found, add to PATH in `~/.bashrc` or `~/.zshrc`

### "kind create cluster fails"
- Ensure Docker daemon is running
- On Windows: Check WSL2 is enabled in Docker Desktop settings

### "Permission denied" errors
- Run: `sudo usermod -aG docker $USER`
- Log out and back in

---

## Quick Install (Copy-Paste for Linux)

```bash
# One-line setup for Linux
curl -LO https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64 && \
chmod +x kind && sudo mv kind /usr/local/bin/ && \
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
echo "✓ All tools installed"

# Verify
kind --version && kubectl version --client && helm version
```

---

Once all prerequisites are installed, run:
```bash
cd d:\Yotto-Assignment
bash scripts/bootstrap.sh
```
