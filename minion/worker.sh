#!/bin/bash
set -e  # Exit immediately if any command fails

echo "### Configuring NFS Client ###"

# Ensure NFS client utilities are installed
if ! dpkg -l | grep -q nfs-common; then
    sudo apt update
    sudo apt install -y nfs-common
else
    echo "NFS client utilities are already installed."
fi

# Disable firewall (Ensure it's safe for your setup)
sudo ufw disable || true  # Suppresses error if UFW is not installed

# Define NFS Server and Share
NFS_SERVER="${1:-master}"  # Default to "master" if not passed as an argument
NFS_SHARE="/home/dev/nfs_share"
MOUNT_POINT="$HOME/client_nfs_share"

# Ensure the master node is resolvable (Manual step may be required)
if ! grep -q "$NFS_SERVER" /etc/hosts; then
    echo "WARNING: Ensure $NFS_SERVER is resolvable or added in /etc/hosts!"
fi

# Ensure the mount directory exists
mkdir -p "$MOUNT_POINT"

# Check if already mounted
if mount | grep -q "$MOUNT_POINT"; then
    echo "NFS share is already mounted at $MOUNT_POINT."
else
    echo "Mounting NFS share from $NFS_SERVER:$NFS_SHARE to $MOUNT_POINT"
    sudo mount "$NFS_SERVER:$NFS_SHARE" "$MOUNT_POINT" || {
        echo "ERROR: Failed to mount $NFS_SERVER:$NFS_SHARE" >&2
        exit 1
    }
fi

# Verify mount
mount | grep "$MOUNT_POINT"

# Create a test file to verify write access
echo "$(hostname)" > "$MOUNT_POINT/$(hostname).txt"
ls -l "$MOUNT_POINT"

# Wait for changes to propagate
sleep 5

# Unmount only if mounted
if mount | grep -q "$MOUNT_POINT"; then
    echo "Unmounting $MOUNT_POINT"
    sudo umount "$MOUNT_POINT"
    mount | grep "$MOUNT_POINT" || echo "Successfully unmounted."
else
    echo "No need to unmount, NFS share is not mounted."
fi

# Configure Local Path Provisioner
LOCAL_PATH="/opt/local-path-provisioner"
echo "### Configuring Local Path Provisioner ###"
sudo mkdir -p "$LOCAL_PATH"
sudo chown nobody:nogroup "$LOCAL_PATH"
sudo chmod 755 "$LOCAL_PATH"

echo "NFS client setup completed successfully!"
