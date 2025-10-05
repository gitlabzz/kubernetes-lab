#!/bin/bash
set -e  # Exit on any error

echo "### Installing Helm ###"

# Check if Helm is already installed
if command -v helm &>/dev/null; then
    echo "Helm is already installed: $(helm version --short)"
    exit 0
fi

# Download Helm install script with verification
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

# Verify script integrity (Optional: If Helm provides checksum, you can validate it)
chmod 700 get_helm.sh

# Install Helm
./get_helm.sh

# Verify Helm installation
helm version

# Enable auto-completion for bash and zsh
echo "### Enabling Helm Auto-Completion ###"
source <(helm completion bash)
echo "source <(helm completion bash)" >> ~/.bashrc
echo "source <(helm completion zsh)" >> ~/.zshrc  # Support zsh as well

# Cleanup installation script
rm -f get_helm.sh

echo "Helm installation completed successfully!"