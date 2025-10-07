# Kubernetes Lab Cluster

This repository contains the configuration and setup for a Kubernetes lab cluster environment.

## Cluster Topology

### Utility/LB:
```
utilities.lab:   172.16.176.168    # external LB for kube-apiserver (6443)
```

### etcd (external, 3 nodes):
```
etcd1.lab:       172.16.176.162
etcd2.lab:       172.16.176.172
etcd3.lab:       172.16.176.163
```

### Control planes (3 nodes):
```
cp1.lab:         172.16.176.157
cp2.lab:         172.16.176.161
cp3.lab:         172.16.176.164
```

### Workers (1 node):
```
worker1.lab:     172.16.176.166
```

### VIP/DNS for API server via HAProxy:
```
k8s-api.lab      -> 172.16.176.168:6443
```

**Note:** This lab environment does not have a DNS service. All hostname resolution is handled via `/etc/hosts` files on each node.

### Kubernetes:
```
Version:         v1.31.13
Runtime:         containerd://1.7.28
OS:              Red Hat Enterprise Linux 9.6 (Plow)
```

### Networking:
```
Pod IPAM:        10.0.0.0/8 (Cilium cluster-pool, per-node /24)
Service CIDR:    10.96.0.0/12
CNI:             Cilium v1.18.0 (eBPF-based)
Load Balancer:   MetalLB L2 mode (172.16.176.200-250)
```

### Storage:
```
NFS:             External NFS server on utilities.lab
Local Path:      Node-local storage provisioner
Longhorn:        Distributed storage with replication
```
- **Default Storage Class**: `longhorn` (changed from `nfs-client`)
- **Available Storage Classes**: `longhorn` (default), `longhorn-static`, `nfs-client`, `local-path`

## Web Services and Ingress

All services are accessible via MetalLB load balancer IP: **172.16.176.201**

### Longhorn Storage Management
- **HTTP**: `http://longhorn.devsecops.net.au`
- **HTTPS**: `https://longhorn-ssl.devsecops.net.au` (self-signed cert)
- **HTTPS + Auth**: `https://longhorn-https-secure.devsecops.net.au` (admin/admin)
- **HTTP + Auth**: `http://longhorn-secure.devsecops.net.au` (admin/admin)

### Elasticsearch & Kibana (ECK)
- **Elasticsearch**: `http://elasticsearch.devsecops.net.au`
- **Kibana**: `http://kibana.devsecops.net.au`

## Host Mapping Reference

| Hostname | IP Address | Role |
|----------|------------|------|
| utilities.lab | 172.16.176.168 | Load Balancer / Utilities |
| etcd1.lab | 172.16.176.162 | ETCD Node 1 |
| etcd2.lab | 172.16.176.172 | ETCD Node 2 |
| etcd3.lab | 172.16.176.163 | ETCD Node 3 |
| cp1.lab | 172.16.176.157 | Control Plane Node 1 |
| cp2.lab | 172.16.176.161 | Control Plane Node 2 |
| cp3.lab | 172.16.176.164 | Control Plane Node 3 |
| worker1.lab | 172.16.176.166 | Worker Node 1 |

## Prerequisites

- Red Hat Enterprise Linux 9
- SSH key-based authentication configured
- Root access to all nodes
- Network connectivity between all nodes

## Important Notes

⚠️ **No DNS Service Available**: This lab environment does not have a DNS service running. All hostname resolution is handled via `/etc/hosts` files on each node. Each host has been configured with entries for all other hosts in the cluster.

## Getting Started

1. Verify connectivity to all nodes
2. Ensure all hostnames resolve correctly
3. Configure HAProxy on utilities.lab for API server load balancing
4. Setup external etcd cluster
5. Initialize Kubernetes control plane nodes
6. Join worker nodes to the cluster

---

*Last updated: October 2025*
