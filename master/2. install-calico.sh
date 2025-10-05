#!/bin/bash
set -e  # Exit immediately if any command fails

# Install Calico networking
echo "### Installing Calico Network Plugin ###"
if [ ! -f calico.yaml ]; then
    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
fi
kubectl apply -f calico.yaml

# Wait until all system pods are running
echo "### Waiting for system pods to become ready ###"
kubectl wait --for=condition=Ready pod -n kube-system --all --timeout=120s || {
    echo "ERROR: Some system pods are not ready!" >&2
    kubectl get pods -A
    exit 1
}

# Show cluster status
echo "### Kubernetes Cluster Information ###"
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A -o wide

echo "############ Run join command on all worker ndoes ####################"

echo "sudo kubeadm join 192.168.210.136:6443 --token rj7thn.3zigamf2kjqv1iug --discovery-token-ca-cert-hash sha256:247a7923a2e3bae6b33d15538c557370da48eb4feb74108c4983744397342d62"