#!/bin/bash
set -e  # Exit immediately if any command fails

echo "### Kubernetes Cluster Setup on Ubuntu 24.04 ###"
echo "Useful References:"
echo "https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/"
echo "https://kubernetes.io/docs/concepts/cluster-administration/networking/"
echo "Tested with Ubuntu 24.04"

# Ensure required dependencies are installed
echo "Installing required dependencies..."
sudo apt update -y
sudo apt install -y iputils-ping net-tools vim apt-transport-https curl ufw gnupg lsb-release ca-certificates software-properties-common

# Disable firewall
echo "Disabling firewall (ufw)"
sudo ufw disable || true

# Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap /d' /etc/fstab
sudo systemctl mask swap.target || true

# Verify swap removal
if swapon --summary | grep -q "swap"; then
    echo "ERROR: Swap is still enabled. Check /etc/fstab manually."
    exit 1
fi

# Load kernel modules
echo "Loading required kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Apply sysctl settings
echo "Applying sysctl settings..."
cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Configure needrestart settings
echo "Configuring needrestart..."
echo "\$nrconf{restart} = 'a';" | sudo tee -a /etc/needrestart/needrestart.conf || true

# Install containerd (Fixed package for Ubuntu 24.04)
echo "Installing containerd..."
sudo apt update
sudo apt install -y containerd

# Configure containerd
echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Add Docker repository (Fixed GPG Key issue)
echo "Setting up Docker repository..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

# Add Kubernetes repository (Fixed GPG Key issue)
echo "Adding Kubernetes repository..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null


# Install Kubernetes components
echo "Installing Kubernetes components..."
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable Kubernetes services
echo "Enabling Kubernetes services..."
sudo systemctl enable --now kubelet

# Verify installations
echo "Verifying installations..."
kubeadm version
kubectl version --client

# Pull required Kubernetes images
echo "Pulling Kubernetes images..."
sudo kubeadm config images pull

echo "### Kubernetes Cluster Setup Completed Successfully! ###"
