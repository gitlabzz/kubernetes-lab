#!/bin/bash
set -e  # Exit immediately on any error

echo "### Installing NFS Server and Storage Classes ###"

### Step 1: Install and Configure NFS Server ###
echo "### Configuring NFS Server on Control Plane ###"
if ! dpkg -l | grep -q nfs-kernel-server; then
    sudo apt-get update
    sudo apt-get install -y nfs-kernel-server net-tools openssh-server
else
    echo "NFS Server is already installed."
fi

# Disable firewall (Ensure it's safe for your setup)
sudo ufw disable || true  # Suppresses error if UFW is not installed

# Ensure the NFS directory exists with correct permissions
NFS_DIR="/home/dev/nfs_share"
if [ ! -d "$NFS_DIR" ]; then
    mkdir -p "$NFS_DIR"
    sudo chown nobody:nogroup "$NFS_DIR"
    sudo chmod -R 777 "$NFS_DIR"
fi

# Configure NFS exports
echo "### Setting up NFS exports ###"
cat <<EOF | sudo tee /etc/exports
$NFS_DIR *(fsid=0,rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure)
EOF

# Apply export changes
sudo exportfs -a
sudo exportfs -rav

# Restart and enable NFS service
sudo systemctl restart nfs-server
sudo systemctl enable nfs-server
sudo systemctl status nfs-server --no-pager

# Get the Control Plane Node IP dynamically
NFS_SERVER_IP=$(hostname -I | awk '{print $1}')
echo "Detected NFS Server IP: $NFS_SERVER_IP"

### Step 2: Install NFS Provisioner ###
echo "### Installing NFS Provisioner ###"
if ! helm repo list | grep -q "nfs-subdir-external-provisioner"; then
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm repo update
fi

# Install NFS Provisioner with dynamically determined NFS server IP
helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server="$NFS_SERVER_IP" \
    --set nfs.path="$NFS_DIR" \
    -n nfs-provisioner --create-namespace

# Wait until NFS Provisioner is ready
kubectl wait --for=condition=Ready pod -n nfs-provisioner --all --timeout=120s || {
    echo "ERROR: NFS Provisioner pods failed to start!" >&2
    kubectl get pods -n nfs-provisioner
    exit 1
}

# Set NFS provisioner as the default storage class
echo "### Setting NFS as the default storage class ###"
kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || {
    echo "ERROR: Failed to set default storage class!" >&2
    exit 1
}

### Step 3: Install Local Path Provisioner ###
echo "### Installing Local Path Provisioner ###"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Verify storage classes
kubectl get storageclass

### Step 4: Minion Configuration Instructions ###
echo "### Run the following commands on worker nodes ###"

echo "sudo mkdir -p /opt/local-path-provisioner"
echo "sudo chmod -R 777 /opt/local-path-provisioner"
echo "sudo chown nobody:nogroup /opt/local-path-provisioner"

echo "### NFS Installation and Configuration Completed Successfully! ###"
