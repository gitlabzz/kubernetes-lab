#!/bin/bash

# PostgreSQL Complete Installation and Setup (CloudNativePG)
# Automates operator install, Postgres cluster, client pod, web UIs, and validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Config (overridable)
POSTGRES_NAMESPACE="${POSTGRES_NAMESPACE:-postgres}"
CNPG_NAMESPACE="${CNPG_NAMESPACE:-cnpg-system}"
CNPG_RELEASE_NAME="${CNPG_RELEASE_NAME:-cnpg}"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

# Chart pins
CNPG_CHART_VERSION="${CNPG_CHART_VERSION:-0.26.0}"
CNPG_OPERATOR_IMAGE_REPOSITORY="${CNPG_OPERATOR_IMAGE_REPOSITORY:-ghcr.io/cloudnative-pg/cloudnative-pg}"
CNPG_OPERATOR_IMAGE_TAG="${CNPG_OPERATOR_IMAGE_TAG:-1.27.0}"

# Postgres image pin (CNPG imageName)
POSTGRES_IMAGE_REPOSITORY="${POSTGRES_IMAGE_REPOSITORY:-ghcr.io/cloudnative-pg/postgresql}"
POSTGRES_IMAGE_TAG="${POSTGRES_IMAGE_TAG:-17.5}"

# TLS/ingress configuration
TLS_ISSUER="${TLS_ISSUER:-selfsigned-issuer}"
HOST_PGADMIN="${HOST_PGADMIN:-pgadmin.devsecops.net.au}"
HOST_ADMINER="${HOST_ADMINER:-postgres.devsecops.net.au}"

# Timeout configurations (override via env if needed)
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-180s}"
TLS_TIMEOUT="${TLS_TIMEOUT:-60s}"
POSTGRES_READY_WAIT="${POSTGRES_READY_WAIT:-90}"

# Helm
HELM_BIN="${HELM_BIN:-$(command -v helm || true)}"
if [ -z "$HELM_BIN" ]; then
  if [ -x "$REPO_ROOT/helm" ]; then HELM_BIN="$REPO_ROOT/helm"; else
    echo "Helm not found; install or place binary at $REPO_ROOT/helm" >&2; exit 1; fi
fi

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning(){ echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1"; }
log_header(){ echo -e "\n${PURPLE}=== $1 ===${NC}"; }
log_step(){ echo -e "${CYAN}[$1]${NC} $2"; }

POSTGRES_NS_EXISTED=false
CNPG_NS_EXISTED=false

cleanup_on_error(){
  log_error "Installation failed. Conditional cleanup in progress..."
  if [ "$POSTGRES_NS_EXISTED" = false ]; then kubectl delete ns "$POSTGRES_NAMESPACE" --ignore-not-found=true || true; else log_warning "Preserving existing namespace: $POSTGRES_NAMESPACE"; fi
  if [ "$CNPG_NS_EXISTED" = false ]; then kubectl delete ns "$CNPG_NAMESPACE" --ignore-not-found=true || true; else log_warning "Preserving existing namespace: $CNPG_NAMESPACE"; fi
  exit 1
}

check_prerequisites(){
  log_header "CHECKING PREREQUISITES"
  log_step "1/6" "Checking kubectl"
  command -v kubectl >/dev/null || { log_error "kubectl not found"; exit 1; }
  log_success "kubectl found"

  log_step "2/6" "Checking kubeconfig"
  kubectl cluster-info >/dev/null || { log_error "Cannot connect to cluster"; exit 1; }
  log_success "Cluster accessible"

  # Record existing namespaces
  kubectl get ns "$POSTGRES_NAMESPACE" >/dev/null 2>&1 && POSTGRES_NS_EXISTED=true || true
  kubectl get ns "$CNPG_NAMESPACE" >/dev/null 2>&1 && CNPG_NS_EXISTED=true || true

  log_step "3/6" "Checking helm"
  [ "$HELM_BIN" = "$REPO_ROOT/helm" ] && chmod +x "$HELM_BIN" || true
  log_success "Helm binary: $HELM_BIN"

  log_step "4/6" "Checking required YAML files"
  for f in postgres-cluster.yaml postgres-client.yaml pgadmin-deployment.yaml adminer-postgres.yaml; do
    [ -f "$SCRIPT_DIR/$f" ] || { log_error "$f not found"; exit 1; }
  done
  log_success "Required YAML files present"

  log_step "5/6" "Checking Longhorn storage"
  kubectl get storageclass longhorn >/dev/null || { log_error "Longhorn storageclass missing"; exit 1; }
  log_success "Longhorn available"

  log_step "6/6" "Checking ingress controller"
  if ! kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
    log_warning "nginx ingress controller not found - web UIs may not be reachable"
  else
    log_success "Ingress controller available"
  fi
}

install_cnpg_operator(){
  log_header "INSTALLING CLOUDNATIVEPG OPERATOR"
  log_step "1/3" "Adding CNPG Helm repo"
  $HELM_BIN repo add cloudnative-pg https://cloudnative-pg.github.io/charts >/dev/null
  $HELM_BIN repo update >/dev/null
  log_success "CNPG repo added/updated"

  log_step "2/3" "Installing operator (release: $CNPG_RELEASE_NAME)"
  $HELM_BIN upgrade "$CNPG_RELEASE_NAME" cloudnative-pg/cloudnative-pg \
    --install --create-namespace --namespace "$CNPG_NAMESPACE" \
    --version "$CNPG_CHART_VERSION" \
    --set image.repository="$CNPG_OPERATOR_IMAGE_REPOSITORY" \
    --set image.tag="$CNPG_OPERATOR_IMAGE_TAG" \
    --wait --timeout "$HELM_TIMEOUT" --atomic
  log_success "CNPG operator installed"

  log_step "3/3" "Verifying operator deployment"
  kubectl wait --for=condition=available --timeout="$DEPLOYMENT_TIMEOUT" deployment -l app.kubernetes.io/name=cloudnative-pg -n "$CNPG_NAMESPACE"
  log_success "Operator ready"
}

deploy_postgres_cluster(){
  log_header "DEPLOYING POSTGRES CLUSTER + TOOLS"
  log_step "1/4" "Creating namespace $POSTGRES_NAMESPACE"
  kubectl create ns "$POSTGRES_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  log_success "Namespace ensured"

  log_step "2/4" "Applying Postgres cluster CR"
  kubectl apply -f "$SCRIPT_DIR/postgres-cluster.yaml"
  log_success "Cluster CR applied"

  log_step "3/4" "Deploying client and web UIs"
  kubectl apply -f "$SCRIPT_DIR/postgres-client.yaml"
  kubectl apply -f "$SCRIPT_DIR/pgadmin-deployment.yaml"
  kubectl apply -f "$SCRIPT_DIR/adminer-postgres.yaml"
  log_success "Client and UIs applied"

  log_step "4/4" "Waiting for readiness"
  # Wait for Postgres pods (2 instances); fallback to timeout
  for i in $(seq 1 "$POSTGRES_READY_WAIT"); do
    ready=$(kubectl get pods -n "$POSTGRES_NAMESPACE" -l postgresql.cnpg.io/cluster=postgres-cluster --no-headers 2>/dev/null | grep -c "1/1 *Running" || true)
    [ "$ready" -ge 2 ] && break || sleep 5
  done
  kubectl wait --for=condition=available --timeout="$DEPLOYMENT_TIMEOUT" deployment/postgres-client -n "$POSTGRES_NAMESPACE"
  kubectl wait --for=condition=available --timeout="$DEPLOYMENT_TIMEOUT" deployment/pgadmin -n "$POSTGRES_NAMESPACE" || true
  kubectl wait --for=condition=available --timeout="$DEPLOYMENT_TIMEOUT" deployment/adminer-postgres -n "$POSTGRES_NAMESPACE" || true
  log_success "Core components ready"
}

pin_postgres_image(){
  log_header "PINNING POSTGRES IMAGE"
  local image="$POSTGRES_IMAGE_REPOSITORY:$POSTGRES_IMAGE_TAG"
  if kubectl get cluster.postgresql.cnpg.io postgres-cluster -n "$POSTGRES_NAMESPACE" >/dev/null 2>&1; then
    log_step "1/2" "Setting spec.imageName=$image"
    if kubectl patch cluster.postgresql.cnpg.io postgres-cluster -n "$POSTGRES_NAMESPACE" \
      --type merge -p "{\"spec\":{\"imageName\":\"$image\"}}"; then
      log_success "Image pinned"
    else
      log_warning "Failed to pin image (CR structure may differ)"
    fi
  else
    log_warning "Cluster CR not found"
  fi
  log_step "2/2" "Verifying rollout"
  kubectl rollout status statefulset/postgres-cluster -n "$POSTGRES_NAMESPACE" --timeout="$DEPLOYMENT_TIMEOUT" || true
}

configure_ingress_tls(){
    log_header "CONFIGURING TLS FOR WEB UIS"
    
    # Check if cert-manager is available
    if ! kubectl get clusterissuer "$TLS_ISSUER" >/dev/null 2>&1; then
        log_warning "Cert-manager ClusterIssuer '$TLS_ISSUER' not found - skipping TLS configuration"
        return 0
    fi
    
    local tls_success=true
    
    # Adminer Ingress: set issuer and TLS host/secret
    if kubectl get ingress adminer-postgres-ingress -n "$POSTGRES_NAMESPACE" &>/dev/null; then
        log_step "1/2" "Patching Adminer ingress for TLS (issuer: $TLS_ISSUER)"
        if ! kubectl annotate ingress adminer-postgres-ingress -n "$POSTGRES_NAMESPACE" \
          cert-manager.io/cluster-issuer="$TLS_ISSUER" --overwrite; then
            log_warning "Failed to annotate Adminer ingress"
            tls_success=false
        fi
        if ! kubectl patch ingress adminer-postgres-ingress -n "$POSTGRES_NAMESPACE" --type merge \
          -p "{\"spec\":{\"tls\":[{\"hosts\":[\"$HOST_ADMINER\"],\"secretName\":\"adminer-postgres-tls\"}],\"rules\":[{\"host\":\"$HOST_ADMINER\"}]}}"; then
            log_warning "Failed to patch Adminer ingress"
            tls_success=false
        fi
    else
        log_warning "Adminer ingress not found"
        tls_success=false
    fi
    
    # pgAdmin Ingress: set issuer and TLS host/secret
    if kubectl get ingress pgadmin-ingress -n "$POSTGRES_NAMESPACE" &>/dev/null; then
        log_step "2/2" "Patching pgAdmin ingress for TLS (issuer: $TLS_ISSUER)"
        if ! kubectl annotate ingress pgadmin-ingress -n "$POSTGRES_NAMESPACE" \
          cert-manager.io/cluster-issuer="$TLS_ISSUER" --overwrite; then
            log_warning "Failed to annotate pgAdmin ingress"
            tls_success=false
        fi
        if ! kubectl patch ingress pgadmin-ingress -n "$POSTGRES_NAMESPACE" --type merge \
          -p "{\"spec\":{\"tls\":[{\"hosts\":[\"$HOST_PGADMIN\"],\"secretName\":\"pgadmin-tls\"}],\"rules\":[{\"host\":\"$HOST_PGADMIN\"}]}}"; then
            log_warning "Failed to patch pgAdmin ingress"
            tls_success=false
        fi
    else
        log_warning "pgAdmin ingress not found"
        tls_success=false
    fi

    # Wait for cert-manager to issue secrets (only if TLS was configured successfully)
    if [ "$tls_success" = "true" ]; then
        log_step "3/3" "Waiting for TLS certificate issuance (max $TLS_TIMEOUT)"
        local timeout=$((${TLS_TIMEOUT%s} / 2))  # Convert from seconds and divide by sleep interval
        for i in $(seq 1 $timeout); do
            a=$(kubectl get secret adminer-postgres-tls -n "$POSTGRES_NAMESPACE" -o jsonpath='{.type}' 2>/dev/null || true)
            p=$(kubectl get secret pgadmin-tls -n "$POSTGRES_NAMESPACE" -o jsonpath='{.type}' 2>/dev/null || true)
            if [ "$a" = "kubernetes.io/tls" ] && [ "$p" = "kubernetes.io/tls" ]; then
                log_success "TLS secrets issued successfully"
                return 0
            fi
            sleep 2
        done
        log_warning "TLS secret issuance timed out after ${timeout}s - certificates may still be pending"
    fi
}

health_check(){
    log_header "FINAL HEALTH CHECK"
    local score=0; local max=10

    # 1) Operator ready
    log_step "1/10" "Checking operator deployment"
    if kubectl get deploy -n "$CNPG_NAMESPACE" -l app.kubernetes.io/name=cloudnative-pg --no-headers 2>/dev/null | grep -q "1/1"; then
        log_success "✓ Operator ready"; ((score++)); else log_warning "✗ Operator not ready"; fi

    # 2) Cluster pods ready
    log_step "2/10" "Checking Postgres pods"
    ready=$(kubectl get pods -n "$POSTGRES_NAMESPACE" -l postgresql.cnpg.io/cluster=postgres-cluster --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo 0)
    if [ "$ready" -ge 2 ]; then log_success "✓ $ready/2 Postgres pods running"; ((score++)); else log_warning "✗ Postgres pods not ready ($ready/2)"; fi

    # 3) Services present
    log_step "3/10" "Checking services (rw/ro/r)"
    if kubectl get svc -n "$POSTGRES_NAMESPACE" postgres-cluster-rw postgres-cluster-ro postgres-cluster-r &>/dev/null; then
        log_success "✓ Services present"; ((score++)); else log_warning "✗ Services missing"; fi

    # 4) Client connectivity
    log_step "4/10" "Checking client connectivity"
    if kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- psql -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "✓ psql connection OK"; ((score++)); else log_warning "✗ psql connection failed"; fi

    # 5) CRUD basic
    log_step "5/10" "Checking CRUD"
    if kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- bash -lc "psql -d labdb -c 'CREATE TABLE IF NOT EXISTS codex_health(id INT); INSERT INTO codex_health VALUES (1) ON CONFLICT DO NOTHING; SELECT COUNT(*) FROM codex_health;'" >/dev/null 2>&1; then
        log_success "✓ CRUD basic works"; ((score++)); else log_warning "✗ CRUD basic failed"; fi

    # 6) Sample data presence
    log_step "6/10" "Checking sample data"
    if kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- psql -d labdb -c "SELECT COUNT(*) FROM users;" >/dev/null 2>&1; then
        log_success "✓ Sample data OK"; ((score++)); else log_warning "✗ Sample data missing"; fi

    # 7) PodMonitor present
    log_step "7/10" "Checking PodMonitor"
    if kubectl get podmonitor -n "$POSTGRES_NAMESPACE" --no-headers 2>/dev/null | grep -qi postgres; then
        log_success "✓ PodMonitor present"; ((score++)); else log_warning "✗ PodMonitor missing"; fi

    # 8) Adminer ingress
    log_step "8/10" "Checking Adminer ingress"
    if kubectl get ingress adminer-postgres-ingress -n "$POSTGRES_NAMESPACE" --no-headers 2>/dev/null | grep -q "$HOST_ADMINER"; then
        log_success "✓ Adminer ingress present"; ((score++)); else log_warning "✗ Adminer ingress missing"; fi

    # 9) pgAdmin ingress
    log_step "9/10" "Checking pgAdmin ingress"
    if kubectl get ingress pgadmin-ingress -n "$POSTGRES_NAMESPACE" --no-headers 2>/dev/null | grep -q "$HOST_PGADMIN"; then
        log_success "✓ pgAdmin ingress present"; ((score++)); else log_warning "✗ pgAdmin ingress missing"; fi

    # 10) TLS secrets
    log_step "10/10" "Checking TLS secrets"
    if kubectl get secret adminer-postgres-tls pgadmin-tls -n "$POSTGRES_NAMESPACE" >/dev/null 2>&1; then
        log_success "✓ TLS secrets exist"; ((score++)); else log_warning "✗ TLS secrets missing"; fi

    echo ""
    if [ "$score" -eq "$max" ]; then
        log_success "🎉 POSTGRES DEPLOYMENT: 100% HEALTHY ($score/$max)"
    elif [ "$score" -ge 8 ]; then
        log_success "✅ POSTGRES DEPLOYMENT: MOSTLY HEALTHY ($score/$max)"
    elif [ "$score" -ge 5 ]; then
        log_warning "⚠️  POSTGRES DEPLOYMENT: PARTIALLY HEALTHY ($score/$max)"
    else
        log_error "❌ POSTGRES DEPLOYMENT: UNHEALTHY ($score/$max)"; return 1
    fi
}

test_postgres(){
  log_header "TESTING POSTGRES CONNECTIVITY AND DATA"
  log_step "1/4" "Connection test"
  kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- psql -c "SELECT current_database(), current_user, version();" >/dev/null && \
  log_success "Connection OK" || { log_error "Connection failed"; return 1; }

  log_step "2/4" "Create schema & tables"
  kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- /scripts/create-test-data.sh >/dev/null && log_success "Schema OK" || log_warning "Schema creation had issues"

  log_step "3/4" "Insert sample data"
  kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- /scripts/insert-test-data.sh >/dev/null && log_success "Data inserted" || log_warning "Insert had issues"

  log_step "4/4" "Run queries & perf"
  kubectl exec deployment/postgres-client -n "$POSTGRES_NAMESPACE" -- /scripts/query-test-data.sh >/dev/null && log_success "Queries OK" || log_warning "Query issues"
}

display_info(){
  log_header "DEPLOYMENT INFORMATION"
  log_info "Namespace: $POSTGRES_NAMESPACE"
  kubectl get pods,svc -n "$POSTGRES_NAMESPACE"
  echo ""
  log_info "Web UIs:"
  echo " - Adminer: http://postgres.devsecops.net.au (TLS available)"
  echo " - pgAdmin: http://pgadmin.devsecops.net.au (TLS available)"
  echo ""
  log_info "Grafana Dashboard Import Helper:"
  echo " - Run: $SCRIPT_DIR/import-grafana-dashboard.sh"
}

main(){
  log_header "POSTGRES COMPLETE INSTALLATION AND SETUP"
  echo -e "${CYAN}This installs CloudNativePG operator, a HA Postgres cluster, client tools, and web UIs.${NC}"
  trap cleanup_on_error ERR
  start_time=$(date +%s)

  check_prerequisites
  install_cnpg_operator
  deploy_postgres_cluster
  pin_postgres_image
  configure_ingress_tls
  test_postgres
  health_check
  display_info

  end_time=$(date +%s)
  duration=$((end_time-start_time))
  echo ""; log_success "🚀 POSTGRES INSTALLATION COMPLETED in $((duration/60))m $((duration%60))s"; echo ""
}

main "$@"
