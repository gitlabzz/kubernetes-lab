#!/bin/bash
set -e  # Exit on any error

echo "### Installing Cilium ###"

helm repo add cilium https://helm.cilium.io/
helm upgrade --install cilium cilium/cilium \
  --version 1.17.1 \
  --namespace kube-system \
  --create-namespace \
  --set operator.replicas=1 \
  --set kubeProxyReplacement=true \
  --set encryption.enabled=true \
  --set encryption.nodeEncryption=true \
  --set encryption.type=wireguard \
  --set ingressController.enabled=true \
  --set ingressController.loadbalancerMode=dedicated \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --reuse-values \
  --set tetragon.enabled=true


echo "Cilium installation completed successfully!"

# Wait until all system pods are running
echo "### Waiting for system pods to become ready ###"
kubectl wait --for=condition=Ready pod -n kube-system --all --timeout=120s || {
    echo "ERROR: Some system pods are not ready!" >&2
    kubectl get pods -A
    exit 1
}

# Install Tetragon
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon -n kube-system


# Wait until all tetragon pods are running
echo "### Waiting for system pods to become ready ###"
kubectl wait --for=condition=Ready pod -n kube-system --all --timeout=120s || {
    echo "ERROR: Some system pods are not ready!" >&2
    kubectl get pods -A
    exit 1
}

kubectl rollout status -n kube-system ds/tetragon -w

# Example for hubble-ui
kubectl patch svc hubble-ui -n kube-system -p '{"spec": {"type": "LoadBalancer"}}'
# open hubble-ui - open browser at http:<<LOAD-BALANDER>>:80

# Show cluster status
echo "### Kubernetes Cluster Information ###"
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A -o wide

# Install Cilium client
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin/
rm cilium-linux-amd64.tar.gz
sleep 3
cilium version

# Validate the Installation
kubectl get pods -n kube-system

sleep 30
cilium status

# Enable Hubble for Observability
cilium hubble enable

cilium status

# Test Cilium Connectivity
#cilium connectivity test

#curl -L https://github.com/cilium/hubble/releases/latest/download/hubble-linux-amd64.tar.gz | tar -xz
#sudo mv hubble /usr/local/bin

# Install the Hubble Client0
# https://docs.cilium.io/en/stable/observability/hubble/setup/
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
rm hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}

sleep 5

# Validate Hubble API Access
cilium hubble port-forward&
hubble status
hubble observe


sleep 5
kubectl get service -n kube-system

# deploy sample workload
kubectl create deployment nginx --image=nginx --port=80
kubectl get pods -o wide
kubectl expose deployment nginx --port=80 --type=ClusterIP
kubectl get service

kubectl wait --for=condition=Ready pod -n default --all --timeout=120s || {
    echo "ERROR: test pod is not ready!" >&2
    kubectl get pods -n default
    exit 1
}
