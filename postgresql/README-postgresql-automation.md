# PostgreSQL Complete Automation (CloudNativePG)

## Overview

`postgresql-automated-install.sh` provides end-to-end automation for PostgreSQL on Kubernetes using CloudNativePG:

- ✅ Operator install (CloudNativePG)
- ✅ HA Postgres cluster (2 instances)
- ✅ Client pod with test scripts
- ✅ Web UIs: pgAdmin + Adminer
- ✅ Data creation + validation + basic performance
- ✅ TLS for web UIs via cert-manager (self-signed by default)

---

## Quick Start

```bash
cd /private/tmp/kubernetes-lab/postgresql
./postgresql-automated-install.sh
```

Uninstall everything:
```bash
./postgresql-uninstall.sh
```

Full cycle test (uninstall → install → validate):
```bash
./test-postgresql-full-cycle.sh
```

---

## Prerequisites

- `kubectl` access to cluster
- `kubeconfig` at `/private/tmp/kubernetes-lab/admin.conf` (override: `KUBECONFIG`)
- `helm` available (`$PATH` or repo `./helm`)
- StorageClass `longhorn` present
- Ingress controller (nginx) for web UIs (optional)
- cert-manager with `ClusterIssuer selfsigned-issuer` (optional TLS)

---

## What It Does

1) Installs CloudNativePG operator via Helm (pinned chart version)
2) Creates namespace `postgres`
3) Applies cluster CR, client pod, and web UIs
4) Waits for readiness (operator/cluster/client/UI)
5) Pins Postgres image version via CR `spec.imageName` (best-effort)
6) Runs connection + data + query tests
7) Configures TLS on pgAdmin/Adminer via cert-manager (issuer configurable)
8) Computes a 10-point health score and prints a clear summary

---

## Pinned Versions

- Chart: `cloudnative-pg/cloudnative-pg` → `CNPG_CHART_VERSION=0.26.0`
- Operator image: `CNPG_OPERATOR_IMAGE_REPOSITORY=ghcr.io/cloudnative-pg/cloudnative-pg`, `CNPG_OPERATOR_IMAGE_TAG=1.27.0`
- Postgres image: `POSTGRES_IMAGE_REPOSITORY=ghcr.io/cloudnative-pg/postgresql`, `POSTGRES_IMAGE_TAG=17.5`

Override when running:
```bash
CNPG_CHART_VERSION=0.26.0 \
CNPG_OPERATOR_IMAGE_REPOSITORY=ghcr.io/cloudnative-pg/cloudnative-pg \
CNPG_OPERATOR_IMAGE_TAG=1.27.0 \
POSTGRES_IMAGE_REPOSITORY=ghcr.io/cloudnative-pg/postgresql \
POSTGRES_IMAGE_TAG=17.5 \
./postgresql-automated-install.sh
```

---

## Access

- pgAdmin: https://pgadmin.devsecops.net.au (TLS via cert-manager; browser may warn on self-signed)
- Adminer: https://postgres.devsecops.net.au (TLS configured)
- Client pod: `kubectl exec -it deployment/postgres-client -n postgres -- psql`

---

## Validation Commands

```bash
# From client pod
kubectl exec deployment/postgres-client -n postgres -- psql -c "SELECT version();"
kubectl exec deployment/postgres-client -n postgres -- /scripts/create-test-data.sh
kubectl exec deployment/postgres-client -n postgres -- /scripts/insert-test-data.sh
kubectl exec deployment/postgres-client -n postgres -- /scripts/query-test-data.sh

# Import Grafana dashboard (kube-prometheus-stack)
./import-grafana-dashboard.sh
```

---

## Notes

- The client reads credentials from secret `postgres-credentials` (owner user created at bootstrap).
- TLS for web UIs uses `cert-manager.io/cluster-issuer: selfsigned-issuer` by default. Switch to Let’s Encrypt by setting `TLS_ISSUER=letsencrypt-staging` (or prod) and ensuring DNS/HTTP-01 reachability.
- Hosts are configurable: `HOST_PGADMIN`, `HOST_ADMINER`.
- CR patching for image pinning is best-effort and may need adjustments if the CRD schema changes.
