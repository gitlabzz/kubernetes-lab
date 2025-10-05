#!/bin/bash
set -e  # Exit on any error

echo "### Installing MetalLB ###"

# Check if MetalLB is already installed
if helm list -n metallb-system | grep -q metallb; then
    echo "MetalLB is already installed."
else
    # Ensure Helm repo exists
    if ! helm repo list | grep -q metallb; then
        helm repo add metallb https://metallb.github.io/metallb
        helm repo update
    fi

    # Install MetalLB
    helm install metallb metallb/metallb --namespace metallb-system --create-namespace
fi

# Wait for MetalLB to be ready instead of arbitrary sleep
echo "### Waiting for MetalLB pods to be ready ###"
kubectl wait --for=condition=Ready pod -n metallb-system --all --timeout=120s || {
    echo "ERROR: MetalLB pods failed to start!" >&2
    kubectl get pods -n metallb-system
    exit 1
}

# Define and apply MetalLB IP pool and L2 advertisement
echo "### Configuring MetalLB IP Pool and L2 Advertisement ###"
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.210.200-192.168.210.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF

# Verify MetalLB Configuration
echo "### Verifying MetalLB Configuration ###"
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisements -n metallb-system

echo "MetalLB installation and configuration completed successfully!"