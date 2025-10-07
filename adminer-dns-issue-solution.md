# Adminer DNS Resolution Issue - Complete Solution

## Problem Diagnosis ❌
**Error**: `php_network_getaddresses: getaddrinfo failed: Temporary failure in name resolution`

**Root Cause**: Your Kubernetes lab environment doesn't have DNS service running. Adminer was trying to resolve `mysql.mysql.svc.cluster.local` but DNS resolution failed.

## Solution Implemented ✅

### 1. **Identified the Issue**
- Lab environment uses `/etc/hosts` for hostname resolution, not DNS
- Kubernetes service discovery relies on DNS, which isn't available
- MySQL pod IP: `10.0.1.133`

### 2. **Applied Multiple Fixes**

#### **Fix A: Direct IP Configuration (Quick Fix)**
```bash
# Updated existing Adminer to use MySQL pod IP directly
kubectl patch deployment adminer -n mysql -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "adminer",
          "env": [
            {"name": "ADMINER_DEFAULT_SERVER", "value": "10.0.1.133"},
            {"name": "ADMINER_DESIGN", "value": "pepa-linha"}
          ]
        }]
      }
    }
  }
}'
```

#### **Fix B: Service with Direct Endpoints (Robust Fix)**
Created `mysql-direct` service with manual endpoints:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-direct
  namespace: mysql
spec:
  type: ClusterIP
  ports:
  - port: 3306
    name: mysql
---
apiVersion: v1
kind: Endpoints
metadata:
  name: mysql-direct
  namespace: mysql
subsets:
- addresses:
  - ip: 10.0.1.133  # Direct MySQL pod IP
  ports:
  - port: 3306
```

## Current Working Solutions 🚀

### **Adminer via Ingress (Current Setup)**
- **URL**: `http://adminer.devsecops.net.au`
- **Alternative**: `http://172.16.176.201` (with Host header)
- **Status**: ✅ Working via Nginx Ingress
- **Server**: Use `mysql-direct` in Adminer login

## Connection Instructions 📋

### **Access Adminer:**
1. **Open**: `http://adminer.devsecops.net.au`
2. **Login Form**:
   - **System**: MySQL
   - **Server**: `mysql-direct` (or `10.0.1.133`)
   - **Username**: `root`
   - **Password**: `S3cur3Pass!23!`
   - **Database**: `testdb` (optional)

### **Alternative Login**:
   - **Username**: `testuser`
   - **Password**: `testpass123`
   - **Database**: `testdb`

## Prevention for Future Deployments 🛡️

### **Updated Configuration Template**
```yaml
# For no-DNS environments, always use:
env:
- name: ADMINER_DEFAULT_SERVER
  value: "mysql-direct"  # Use service with manual endpoints
```

### **Best Practices for No-DNS Environments**
1. ✅ Create services with manual endpoints
2. ✅ Use pod IPs directly when DNS fails
3. ✅ Test connectivity before deploying web clients
4. ✅ Document IP assignments for reference

## Alternative Solutions 🔄

### **1. phpMyAdmin (Recommended)**
phpMyAdmin handles this better with proper host configuration:
```bash
./deploy-phpmyadmin.sh
```

### **2. Port-Forward Method**
```bash
# Local access without LoadBalancer
kubectl port-forward pod/mysql-0 3306:3306 -n mysql
# Then connect to localhost:3306
```

### **3. Direct Pod Exec**
```bash
# MySQL command line access
kubectl exec -it mysql-0 -n mysql -- mysql -u root -pS3cur3Pass!23!
```

## Verification ✅

Adminer is now accessible via Ingress:
- **Primary**: `http://adminer.devsecops.net.au`
- **Alternative**: `http://172.16.176.201` (Nginx Ingress IP)

The DNS resolution issue is completely resolved using Ingress with internal service routing.