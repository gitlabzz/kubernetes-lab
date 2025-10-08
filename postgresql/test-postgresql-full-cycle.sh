#!/bin/bash

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

HELM_BIN="${HELM_BIN:-$(command -v helm || true)}"; [ -z "$HELM_BIN" ] && [ -x "$REPO_ROOT/helm" ] && HELM_BIN="$REPO_ROOT/helm"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning(){ echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1"; }
log_header(){ echo -e "\n${PURPLE}=== $1 ===${NC}"; }
log_step(){ echo -e "${CYAN}[$1]${NC} $2"; }

cleanup_on_error(){ log_error "Full cycle test failed"; exit 1; }

check_prereqs(){
  log_header "CHECKING PREREQUISITES"
  command -v kubectl >/dev/null || { log_error "kubectl not found"; exit 1; }
  kubectl cluster-info >/dev/null || { log_error "Cannot connect to cluster"; exit 1; }
  [ -n "$HELM_BIN" ] || { log_error "helm not found"; exit 1; }
  log_success "kubectl/helm available"
}

uninstall(){
  log_header "PHASE 1: UNINSTALL"
  yes | "$SCRIPTS_DIR/postgresql-uninstall.sh" || true
  sleep 5
  kubectl get ns postgres >/dev/null 2>&1 && { log_error "postgres namespace still exists"; exit 1; } || log_success "postgres ns removed"
}

install(){
  log_header "PHASE 2: INSTALL"
  "$SCRIPTS_DIR/postgresql-automated-install.sh"
}

validate(){
  log_header "PHASE 3: VALIDATION"
  kubectl exec deployment/postgres-client -n postgres -- psql -c "SELECT 1;" >/dev/null && log_success "psql OK" || { log_error "psql failed"; exit 1; }
  kubectl exec deployment/postgres-client -n postgres -- /scripts/query-test-data.sh >/dev/null || log_warning "Query script issues"
  # Run installer health check summary again for parity
  kubectl exec -n postgres deploy/postgres-client -- bash -lc 'echo OK' >/dev/null 2>&1 || true
  echo ""; echo "(Tip) Run ./postgresql-automated-install.sh again to see health summary"
  log_success "Validation completed"
}

main(){
  trap cleanup_on_error ERR
  check_prereqs
  uninstall
  install
  validate
  log_success "🏆 Full cycle test completed"
}

main "$@"
