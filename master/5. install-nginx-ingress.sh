#!/bin/bash
set -e  # Exit immediately on any error

echo "### Installing Nginx Ingress ###"
echo "Reference: https://kubernetes.github.io/ingress-nginx/deploy/"

# Check if Nginx Ingress is already installed
if helm list -n ingress-nginx | grep -q ingress-nginx; then
    echo "Nginx Ingress is already installed."
else
    # Ensure the Helm repo is added
    if ! helm repo list | grep -q "ingress-nginx"; then
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
    fi

    # Install or upgrade Nginx Ingress
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx --create-namespace
fi

# Wait until Ingress Controller pods are ready
echo "### Waiting for Nginx Ingress pods to be ready ###"
kubectl wait --for=condition=Ready pod -n ingress-nginx --all --timeout=120s || {
    echo "ERROR: Nginx Ingress pods failed to start!" >&2
    kubectl get pods -n ingress-nginx
    exit 1
}

# Display Helm installations
helm list -A

# Show all Ingress resources
kubectl -n ingress-nginx get all

# Get the assigned LoadBalancer External IP
LB_IP=$(kubectl -n ingress-nginx get service ingress-nginx-controller -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "### Validate Ingress Controller Type: LoadBalancer External IP: ${LB_IP:-'Pending'} ###"
