# cert-manager Learning Guide

## Overview
This guide documents our complete learning experience with cert-manager in our Kubernetes lab environment, capturing validated steps and configurations.

---

## Current Status (Validated)

### Installation Details
- **Version**: v1.15.3 (currently installed)
- **Installation Method**: Helm chart
- **Namespace**: cert-manager
- **Helm Chart**: jetstack/cert-manager
- **Status**: Fully operational

### Verification Results ✅

#### 1. Pods Status
```bash
kubectl get pods -n cert-manager
```
**Output:**
```
NAME                                     READY   STATUS    RESTARTS   AGE
cert-manager-7b9875fbcc-ksnrx            1/1     Running   0          12h
cert-manager-cainjector-948d47c6-j8vk6   1/1     Running   0          12h
cert-manager-webhook-78bd84d46b-gxmsk    1/1     Running   0          12h
```

#### 2. Custom Resource Definitions (CRDs)
```bash
kubectl get crd | grep cert-manager
```
**Output:**
```
certificaterequests.cert-manager.io                    2025-10-05T14:46:27Z
certificates.cert-manager.io                           2025-10-05T14:46:28Z
challenges.acme.cert-manager.io                        2025-10-05T14:46:28Z
clusterissuers.cert-manager.io                         2025-10-05T14:46:28Z
issuers.cert-manager.io                                2025-10-05T14:46:28Z
orders.acme.cert-manager.io                            2025-10-05T14:46:28Z
```

#### 3. Active Cluster Issuers
```bash
kubectl get clusterissuers
```
**Output:**
```
NAME                  READY   AGE
letsencrypt-staging   True    27m
selfsigned-issuer     True    27m
```

#### 4. Active Certificates
```bash
kubectl get certificates -A
```
**Output:**
```
NAMESPACE         NAME                        READY   SECRET                      AGE
longhorn-system   longhorn-https-secure-tls   True    longhorn-https-secure-tls   27m
longhorn-system   longhorn-tls-cert           True    longhorn-tls-cert           27m
```

---

## Key Components Explained

### Core Components
1. **cert-manager Controller**: Main certificate management logic
2. **cert-manager Webhook**: Validates and mutates cert-manager resources
3. **cert-manager CA Injector**: Injects CA bundles into webhooks and API services

### Available Issuers
1. **selfsigned-issuer**: Creates self-signed certificates for lab use
2. **letsencrypt-staging**: Let's Encrypt staging environment (for testing)

### Working Certificates
- **longhorn-tls-cert**: Self-signed certificate for Longhorn HTTPS access
- **longhorn-https-secure-tls**: Certificate for secure Longhorn ingress

---

## Installation Commands (Reference)

The following commands were used for the original installation:

```bash
# Add jetstack repository
helm repo add jetstack https://charts.jetstack.io

# Update repositories
helm repo update

# Install cert-manager with CRDs
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.3 \
  --set crds.enabled=true
```

---

## Validation Tests Performed

### ✅ Basic Functionality Test
- All pods running and healthy
- CRDs properly installed
- Cluster issuers operational
- Certificates successfully issued and ready

### ✅ Integration Test
- Successfully integrated with Longhorn ingress
- HTTPS certificates working for web services
- Both self-signed and staging Let's Encrypt issuers functional

---

## Next Steps for Learning

*This section will be updated as we progress with additional cert-manager features and use cases.*

---

*Last Updated: October 2025*
*Environment: Kubernetes Lab v1.31.13*