#!/bin/bash
set -e  # Exit immediately if any command fails

echo "### Verifying Swap & Kubernetes Services ###"
free -h
swapon --summary

echo "### Setting up control plane node ###"
if sudo kubeadm init --image-repository=registry.k8s.io --pod-network-cidr=192.168.0.0/16; then
    echo "Kubernetes control plane initialized successfully!"
else
    echo "ERROR: kubeadm init failed!" >&2
    exit 1
fi

# Setup kubeconfig for kubectl
echo "### Configuring kubectl for user ###"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config  # Set environment variable for current session

# Verify kubeconfig
ls -la $HOME/.kube/config

# kubectl autocomplete for bash
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc

# Set alias for convenience
echo "alias k='kubectl'" >> ~/.bashrc
source ~/.bashrc