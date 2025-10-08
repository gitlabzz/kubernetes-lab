#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

POSTGRES_NAMESPACE="${POSTGRES_NAMESPACE:-postgres}"
CNPG_NAMESPACE="${CNPG_NAMESPACE:-cnpg-system}"
CNPG_RELEASE_NAME="${CNPG_RELEASE_NAME:-cnpg}"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

HELM_BIN="${HELM_BIN:-$(command -v helm || true)}"
if [ -z "$HELM_BIN" ] && [ -x "$REPO_ROOT/helm" ]; then HELM_BIN="$REPO_ROOT/helm"; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning(){ echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1"; }
log_header(){ echo -e "\n${PURPLE}=== $1 ===${NC}"; }
log_step(){ echo -e "${CYAN}[$1]${NC} $2"; }

cleanup_on_error(){
    log_error "Uninstallation encountered an error: $?"
    log_warning "Some resources may remain in the cluster"
    log_info "Check namespaces manually: kubectl get ns | grep -E '(postgres|cnpg)'"
    exit 1
}

confirm(){
  log_header "DELETION CONFIRMATION"
  echo -e "${YELLOW}This will delete Postgres namespaces, data, and operator. Continue? [y/N]${NC}"
  read -r ans; [[ "$ans" =~ ^[Yy]$ ]] || { log_info "Cancelled"; exit 0; }
}

remove_helm(){
  log_header "REMOVING CNPG HELM RELEASE"
  if [ -n "$HELM_BIN" ]; then
    $HELM_BIN uninstall "$CNPG_RELEASE_NAME" -n "$CNPG_NAMESPACE" || log_warning "Release not found"
    $HELM_BIN repo remove cloudnative-pg >/dev/null 2>&1 || true
    log_success "Operator helm release removed"
  else
    log_warning "Helm not found; skipping release removal"
  fi
}

delete_namespaces(){
  log_header "DELETING NAMESPACES"
  log_step "1/2" "Deleting postgres namespace"
  kubectl delete ns "$POSTGRES_NAMESPACE" --timeout=180s || true
  # If stuck terminating, remove finalizers from common CNPG resources and namespace
  if kubectl get ns "$POSTGRES_NAMESPACE" 2>/dev/null | grep -q Terminating; then
    log_info "🗑️ Force deleting namespace with finalizer cleanup: $POSTGRES_NAMESPACE"
    # Attempt to strip finalizers from CRs
    if kubectl get cluster.postgresql.cnpg.io -n "$POSTGRES_NAMESPACE" >/dev/null 2>&1; then
      for cr in $(kubectl get cluster.postgresql.cnpg.io -n "$POSTGRES_NAMESPACE" -o name); do
        kubectl patch "$cr" -n "$POSTGRES_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || true
      done
    fi
    # Patch namespace finalizers
    kubectl patch namespace "$POSTGRES_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || true
    log_success "Finalizer cleanup completed"
  fi
  log_step "2/2" "Deleting operator namespace"
  kubectl delete ns "$CNPG_NAMESPACE" --timeout=180s || true
  log_success "Namespace deletions issued"
}

cleanup_crds(){
  log_header "CRD CLEANUP (Optional)"
  echo -e "${YELLOW}Delete CloudNativePG CRDs (postgresql.cnpg.io)? [y/N]${NC}"
  read -r ans; [[ "$ans" =~ ^[Yy]$ ]] || { log_info "Keeping CRDs"; return 0; }
  kubectl get crd | awk '/postgresql.cnpg.io/ {print $1}' | xargs -r kubectl delete crd || true
  log_success "CRDs removed"
}

main(){
  log_header "POSTGRES COMPLETE UNINSTALLATION"
  trap cleanup_on_error ERR
  confirm
  remove_helm
  delete_namespaces
  cleanup_crds
  log_success "🧹 Uninstallation completed"
}

main "$@"
