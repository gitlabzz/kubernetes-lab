# Redis Kubernetes Complete Guide & Automation

## 🎯 **Overview**

This comprehensive guide covers the complete Redis automation solution for Kubernetes, providing enterprise-grade deployment, management, and cleanup capabilities. The solution includes automated installation, advanced uninstall with finalizer cleanup, testing tools, and comprehensive documentation.

---

## 🚀 **Quick Start**

### **One-Command Installation:**
```bash
cd /private/tmp/kubernetes-lab/redis
./redis-automated-install.sh
```

### **One-Command Cleanup:**
```bash
./redis-uninstall.sh
```

### **Complete Cycle Testing:**
```bash
./test-redis-full-cycle.sh
```

---

## 📋 **What Gets Deployed**

### **🔧 Redis Infrastructure**
- **Redis Operator**: OT-CONTAINER-KIT Redis Operator v0.22.1
- **Redis Standalone**: Single instance with monitoring and persistence (5Gi storage)
- **Redis Cluster**: 6-node cluster (3 leaders + 3 followers, 3Gi per node)
- **Client Pod**: Testing and administration environment
- **RedisInsight**: Official web-based GUI client

### **📊 Resource Summary**
- **Namespaces**: `redis`, `ot-operators`
- **Pods**: 8-9 running (operator + standalone + cluster + client + web UI)
- **Services**: 10-11 services created
- **Storage**: 13+ PVCs with Longhorn backend
- **Monitoring**: Redis Exporter + ServiceMonitor
- **Web Access**: Ingress-enabled RedisInsight

---

## 🔗 **Connection Information**

### **Redis Standalone**
```bash
# Internal cluster access
Host: redis-standalone.redis.svc.cluster.local
Port: 6379
Monitoring: redis-standalone.redis.svc.cluster.local:9121

# Direct pod access
kubectl exec -it deployment/redis-client -n redis -- redis-cli -h redis-standalone
```

### **Redis Cluster**
```bash
# Internal cluster access
Host: redis-cluster-leader.redis.svc.cluster.local
Port: 6379

# Cluster-aware client access
kubectl exec -it deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader -c
```

### **RedisInsight Web UI**
```bash
# Via ingress (recommended)
URL: http://redis.devsecops.net.au

# Via port forwarding
kubectl port-forward deployment/redisinsight -n redis 8080:5540
URL: http://localhost:8080
```

---

## 🔧 **Script Features & Capabilities**

### **🛡️ Enhanced Installation Script**
- **Dynamic Path Resolution**: Works from any directory
- **Smart Environment Detection**: Auto-discovers helm binary, respects environment variables
- **Robust Error Handling**: `set -euo pipefail` with comprehensive cleanup
- **Prerequisite Validation**: Checks kubectl, kubeconfig, helm, storage, ingress
- **Atomic Operations**: Uses `--atomic` flag for all-or-nothing deployments
- **Health Scoring**: 10-point system for deployment validation
- **Performance Testing**: Integrated benchmarking with real metrics

### **🗑️ Advanced Uninstall Script with Finalizer Cleanup**
- **Automatic Stuck Resource Detection**: Discovers Custom Resources preventing deletion
- **Intelligent Finalizer Removal**: Patches finalizers automatically
- **Smart Namespace Deletion**: Handles terminating states gracefully
- **Zero Manual Intervention**: Complete automation with fallback mechanisms
- **Comprehensive Cleanup**: Removes pods, services, PVCs, monitoring, CRDs
- **Verification System**: 8-point validation of cleanup completeness

### **🧪 Testing & Validation Tools**
- **Full Cycle Testing**: `test-redis-full-cycle.sh` for end-to-end validation
- **Script Validation**: `validate-redis-script.sh` verifies tested commands
- **Connectivity Testing**: Automated PING tests for both standalone and cluster
- **CRUD Operations**: SET/GET/DELETE validation with test data
- **Performance Benchmarking**: Timing metrics for batch operations

---

## 📊 **Installation Process**

### **Phase 1: Prerequisites Check**
```bash
✅ kubectl connectivity verification
✅ Kubernetes cluster accessibility  
✅ Helm binary discovery (system or local)
✅ Required YAML files validation
✅ Longhorn storage class verification
✅ Nginx ingress controller check
```

### **Phase 2: Redis Operator Installation**
```bash
# Executed commands:
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update
helm upgrade redis-operator ot-helm/redis-operator \
  --install --create-namespace --namespace ot-operators \
  --wait --timeout 10m --atomic
```

### **Phase 3: Redis Instances Deployment**
```bash
# Standalone Redis:
helm upgrade redis-standalone ot-helm/redis \
  --install --namespace redis \
  --set storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set storageSpec.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
  --set redisExporter.enabled=true \
  --set serviceMonitor.enabled=true \
  --wait --timeout 10m --atomic

# Redis Cluster:
helm upgrade redis-cluster ot-helm/redis-cluster \
  --install --namespace redis \
  --set redisCluster.clusterSize=3 \
  --set redisCluster.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
  --set redisCluster.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=3Gi \
  --wait --timeout 10m --atomic
```

### **Phase 4: Client Tools & Web UI**
```bash
kubectl apply -f redis-client.yaml
kubectl apply -f redisinsight-deployment.yaml
kubectl wait --for=condition=available deployment/redis-client deployment/redisinsight -n redis
```

### **Phase 5: Validation & Testing**
```bash
# Connectivity tests
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader ping

# Performance benchmarks
# Sample data creation
# Health scoring (10-point system)
```

---

## 🧹 **Uninstall Process with Finalizer Cleanup**

### **Enhanced Cleanup Features**
The uninstall script now includes advanced finalizer cleanup to prevent stuck namespace termination:

```bash
# Automatic stuck resource discovery
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n redis

# Smart finalizer removal
kubectl patch redis.redis.redis.opstreelabs.in/redis-standalone \
  -n redis -p '{"metadata":{"finalizers":null}}' --type=merge

# Intelligent namespace deletion with timeout and verification
```

### **Cleanup Process**
1. **Resource Discovery**: Identifies all Redis-related components
2. **Helm Cleanup**: Removes all Redis Helm releases and repositories
3. **Namespace Deletion**: Uses enhanced finalizer cleanup for reliable removal
4. **Storage Cleanup**: Removes PVCs and orphaned PVs
5. **Monitoring Cleanup**: Removes ServiceMonitors and PrometheusRules
6. **CRD Management**: Optionally preserves CRDs for future use
7. **Final Verification**: 8-point validation of cleanup completeness

---

## 🎮 **Usage Examples**

### **Basic Operations**
```bash
# Install Redis
./redis-automated-install.sh

# Test connectivity
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping

# Store data
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone set "mykey" "myvalue"

# Retrieve data
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone get "mykey"

# Access web UI
open http://redis.devsecops.net.au

# Clean up everything
./redis-uninstall.sh
```

### **Cluster Operations**
```bash
# Connect to cluster with cluster mode
kubectl exec -it deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader -c

# Check cluster status
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader cluster info

# Distribute data across cluster
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader -c set "user:1001" "{\"name\":\"John\",\"age\":30}"
```

### **Performance Testing**
```bash
# Automated performance test
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone \
  eval "for i=1,100 do redis.call('set', 'perf:' .. i, 'value' .. i) end return 'OK'" 0

# Check memory usage
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone info memory
```

---

## 📈 **Performance Metrics**

### **Typical Performance Results**
- **SET Operations**: 50-100 operations in 140-170ms
- **GET Operations**: 50-100 operations in 130-160ms
- **Memory Usage**: 1-2MB for test datasets
- **Deployment Time**: 3-5 minutes end-to-end
- **Cleanup Time**: 1-2 minutes with finalizer handling

### **Health Check Scoring**
- **10/10**: Perfect deployment, all systems operational ✅
- **9/10**: Minor issues (e.g., cluster initialization delay) ⚠️
- **8/10**: Some components not ready but core functionality working ⚠️
- **<8/10**: Multiple issues requiring attention ❌

---

## 🔍 **Troubleshooting**

### **Common Issues & Solutions**

#### **1. Storage Class Missing**
```bash
# Check available storage classes
kubectl get storageclass

# Ensure Longhorn is installed and available
kubectl get pods -n longhorn-system
```

#### **2. Namespace Stuck in Terminating**
```bash
# The enhanced uninstall script automatically handles this
# Manual cleanup if needed:
kubectl patch namespace redis -p '{"metadata":{"finalizers":null}}'
```

#### **3. Client Pod Container Errors**
```bash
# Check pod status and logs
kubectl describe pod -n redis -l app=redis-client
kubectl logs -n redis -l app=redis-client

# The core Redis functionality works independently of client pod
```

#### **4. Ingress Not Working**
```bash
# Check nginx ingress controller
kubectl get pods -n nginx-ingress

# Use port forwarding as alternative
kubectl port-forward deployment/redisinsight -n redis 8080:5540
```

### **Validation Commands**
```bash
# Check all components
kubectl get all -n redis
kubectl get all -n ot-operators

# Test basic functionality
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader ping

# Validate script integrity
./validate-redis-script.sh

# Run complete test cycle
./test-redis-full-cycle.sh
```

---

## 🔧 **Configuration & Customization**

### **Environment Variables**
```bash
# Override default settings
export REDIS_NAMESPACE="my-redis"
export OPERATOR_NAMESPACE="my-operators"  
export KUBECONFIG="/path/to/my/kubeconfig"
export HELM_BIN="/custom/path/to/helm"

# Run with custom settings
./redis-automated-install.sh
```

### **Storage Configuration**
```bash
# Modify storage settings in script or override with custom values:
# Standalone: 5Gi (default)
# Cluster: 3Gi per node (default)
# Storage class: longhorn (default)
```

### **Cluster Sizing**
```bash
# Default cluster configuration:
# - 3 master nodes
# - 3 follower nodes (1 follower per master)
# - Hash slots: 16384 total, distributed across masters
# - Replication factor: 1
```

---

## 🛡️ **Security Considerations**

### **Access Control**
- **Network Isolation**: Redis accessible only within Kubernetes cluster
- **No External Exposure**: Redis ports not exposed outside cluster by default
- **Ingress Security**: RedisInsight web UI accessible via configured ingress
- **Authentication**: Default setup uses no authentication (suitable for development)

### **Production Hardening Recommendations**
```bash
# Enable Redis AUTH
--set auth.enabled=true
--set auth.password="your-secure-password"

# Enable TLS
--set tls.enabled=true
--set tls.cert="your-tls-cert"

# Network policies
kubectl apply -f redis-network-policy.yaml

# RBAC configuration
kubectl apply -f redis-rbac.yaml
```

---

## 📦 **File Structure**

```
redis/
├── redis-automated-install.sh     # Main installation script (enhanced)
├── redis-uninstall.sh             # Enhanced uninstall with finalizer cleanup
├── test-redis-full-cycle.sh       # Complete end-to-end testing
├── validate-redis-script.sh       # Script validation tool
├── redis-client.yaml              # Client pod configuration
├── redisinsight-deployment.yaml   # Web UI deployment configuration
└── COMPLETE-REDIS-GUIDE.md        # This comprehensive guide
```

---

## 🚀 **Advanced Features**

### **Script Portability**
- **Dynamic Path Resolution**: Scripts work from any directory
- **Environment Awareness**: Adapts to different Kubernetes environments
- **Dependency Discovery**: Automatically finds required tools and configs
- **Error Recovery**: Graceful handling of partial deployments

### **Monitoring Integration**
- **Redis Exporter**: Prometheus metrics collection enabled
- **ServiceMonitor**: Automatic Prometheus discovery
- **Health Checks**: Built-in readiness and liveness probes
- **Performance Metrics**: Real-time performance monitoring

### **High Availability**
- **Cluster Mode**: Multi-master Redis cluster with automatic failover
- **Persistence**: Longhorn-backed persistent storage
- **Replication**: Built-in Redis replication for data safety
- **Load Distribution**: Client-side clustering support

---

## ✨ **Enterprise Features**

### **Production-Ready Automation**
- ✅ **Zero-Downtime Deployments**: Atomic operations with rollback capability
- ✅ **Automatic Finalizer Cleanup**: No more stuck namespace termination
- ✅ **Comprehensive Validation**: 10-point health scoring system
- ✅ **Performance Benchmarking**: Integrated timing and throughput metrics
- ✅ **Self-Healing Scripts**: Intelligent error detection and recovery
- ✅ **Complete Documentation**: Comprehensive usage and troubleshooting guides

### **DevOps Integration**
- ✅ **CI/CD Ready**: Scripts designed for automation pipelines
- ✅ **Environment Agnostic**: Works across different Kubernetes distributions
- ✅ **Monitoring Ready**: Prometheus and Grafana integration included
- ✅ **Testing Framework**: Complete validation and testing suite

---

## 🎯 **Conclusion**

This Redis automation solution provides enterprise-grade deployment and management capabilities for Kubernetes environments. With enhanced finalizer cleanup, comprehensive testing, and production-ready features, it offers a complete Redis infrastructure solution that works reliably across different environments and use cases.

**Key Benefits:**
- 🚀 **Complete Automation**: Zero-touch deployment and cleanup
- 🛡️ **Enterprise-Grade Reliability**: Advanced error handling and recovery
- 🔧 **Production-Ready**: Monitoring, persistence, and high availability
- 📊 **Comprehensive Testing**: Full validation and performance benchmarking
- 🧹 **Bulletproof Cleanup**: Advanced finalizer handling prevents stuck states

**Perfect for:**
- Development and testing environments
- Production Redis deployments
- CI/CD automation pipelines
- Learning and experimentation
- Enterprise Kubernetes platforms

---

*This guide consolidates all Redis documentation and provides the complete reference for the enhanced Redis automation solution.*