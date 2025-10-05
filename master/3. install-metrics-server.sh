#!/bin/bash
set -e  # Exit immediately on any error

echo "### Installing Metrics Server ###"

# Ensure Helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: Helm is not installed. Please install Helm first." >&2
    exit 1
fi

# Ensure kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed. Please install kubectl first." >&2
    exit 1
fi

# Add the Metrics Server Helm repo only if it doesn't exist
if ! helm repo list | grep -q "metrics-server"; then
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo update
fi

# Install or upgrade Metrics Server in default namespace
helm upgrade --install metrics-server metrics-server/metrics-server --set apiService.insecureSkipTLSVerify=true --namespace default --create-namespace

# Patch Metrics Server for worker nodes' TLS certificate issue
# Fix: Remove extra `]` in the original JSON patch
kubectl -n default patch deployment metrics-server --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Restart Metrics Server to apply the patch
kubectl -n default rollout restart deployment metrics-server

# Wait for Metrics Server pods to be ready
echo "### Waiting for Metrics Server to be ready ###"
kubectl wait --for=condition=Available deployment/metrics-server \
    -n default --timeout=120s || {
    echo "ERROR: Metrics Server deployment failed to start!" >&2
    kubectl get pods -n default
    exit 1
}

# Verify Metrics Server installation
echo "### Validating Metrics Server Installation ###"
kubectl get deployment metrics-server -n default
kubectl top nodes
kubectl top pods -A

# Install yq
VERSION=v4.45.1 && BINARY=yq_linux_amd64
sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
