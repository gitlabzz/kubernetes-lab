#!/bin/bash
set -e  # Exit immediately if any command fails

echo "### Installing Kubernetes Dashboard with Ingress ###"

# Step 1: Ensure Namespace Exists
if ! kubectl get namespace kubernetes-dashboard &>/dev/null; then
    kubectl create namespace kubernetes-dashboard
else
    echo "Namespace 'kubernetes-dashboard' already exists."
fi

# Step 2: Install Kubernetes Dashboard
if ! kubectl get deployment kubernetes-dashboard -n kubernetes-dashboard &>/dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml -n kubernetes-dashboard
else
    echo "Kubernetes Dashboard is already installed."
fi

# Step 3: Create Service Account & Cluster Role Binding
if ! kubectl get serviceaccount dashboard-admin -n kubernetes-dashboard &>/dev/null; then
    kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
    kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin
else
    echo "Service Account 'dashboard-admin' already exists."
fi

# Step 4: Generate & Retrieve Token for Dashboard Login
echo "### Retrieving Dashboard Token ###"
TOKEN=$(kubectl create token dashboard-admin -n kubernetes-dashboard 2>/dev/null || \
        kubectl describe secret $(kubectl get secrets -n kubernetes-dashboard | awk '/dashboard-admin/{print $1}') -n kubernetes-dashboard | awk '/token:/ {print $2}')
echo "Dashboard Token: $TOKEN"
echo "Use this token to log into the dashboard."

# Step 5: Create TLS Secret for Ingress (if not already present)
if ! kubectl get secret devsecops-tls -n kubernetes-dashboard &>/dev/null; then
    if [[ -f "fullchain.pem" && -f "privkey.pem" ]]; then
        kubectl create secret tls devsecops-tls --cert=fullchain.pem --key=privkey.pem -n kubernetes-dashboard
    else
        echo "ERROR: TLS certificate files (fullchain.pem, privkey.pem) are missing!" >&2
        exit 1
    fi
else
    echo "TLS Secret 'devsecops-tls' already exists."
fi

# Step 6: Check if Nginx Ingress is Installed
if ! kubectl get deployment -n ingress-nginx | grep -q ingress-nginx-controller; then
    echo "ERROR: Nginx Ingress Controller is not installed! Install it before applying Ingress." >&2
    exit 1
fi

# Step 7: Deploy Ingress Resource for Dashboard
echo "### Configuring Ingress for Kubernetes Dashboard ###"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-devsecops-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: k8sdashboard.devsecops.net.au
    http:
      paths:
      - backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - k8sdashboard.devsecops.net.au
    secretName: devsecops-tls
EOF

# Step 8: Verify Deployment
echo "### Waiting for Kubernetes Dashboard pods to be ready ###"
kubectl wait --for=condition=Available deployment/kubernetes-dashboard -n kubernetes-dashboard --timeout=120s || {
    echo "ERROR: Kubernetes Dashboard pods failed to start!" >&2
    kubectl get pods -n ingress-nginx
    exit 1
}
echo "### Verifying Kubernetes Dashboard Installation ###"
kubectl get pods -n kubernetes-dashboard
kubectl get ingress -n kubernetes-dashboard
