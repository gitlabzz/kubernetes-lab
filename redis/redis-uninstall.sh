#!/bin/bash

# Redis Complete Uninstall Script
# This script removes all Redis-related components from the Kubernetes cluster
# Including: Operator, Instances, Client Pod, Web UI, Storage, and Configurations

set -euo pipefail  # Safer bash options

# Resolve paths and environment
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration Variables (overridable via env)
REDIS_NAMESPACE="${REDIS_NAMESPACE:-redis}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-ot-operators}"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

# Resolve Helm binary: prefer system helm, fallback to repo-local helm
HELM_BIN="${HELM_BIN:-$(command -v helm || true)}"
if [ -z "$HELM_BIN" ]; then
  if [ -x "$REPO_ROOT/helm" ]; then
    HELM_BIN="$REPO_ROOT/helm"
  else
    echo "Helm not found. Install helm or place binary at $REPO_ROOT/helm" >&2
    exit 1
  fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

log_step() {
    echo -e "${CYAN}[$1]${NC} $2"
}

# Check prerequisites
check_prerequisites() {
    log_header "CHECKING PREREQUISITES"
    
    log_step "1/2" "Checking kubectl"
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    log_success "kubectl found"
    
    log_step "2/2" "Checking kubeconfig"
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Kubernetes cluster accessible"
}

# Show current Redis resources
show_current_resources() {
    log_header "CURRENT REDIS RESOURCES"
    
    echo ""
    log_info "📊 Resources to be removed:"
    
    # Count namespaces
    redis_ns_exists=false
    operator_ns_exists=false
    
    if kubectl get namespace "$REDIS_NAMESPACE" &> /dev/null; then
        redis_ns_exists=true
        redis_pods=$(kubectl get pods -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        redis_svcs=$(kubectl get svc -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        redis_pvcs=$(kubectl get pvc -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        redis_ingress=$(kubectl get ingress -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        
        echo "   🔵 Redis Namespace ($REDIS_NAMESPACE):"
        echo "      • Pods: $redis_pods"
        echo "      • Services: $redis_svcs"  
        echo "      • PVCs: $redis_pvcs"
        echo "      • Ingress: $redis_ingress"
        
        # Show specific resources
        echo ""
        log_info "   📋 Detailed resources in $REDIS_NAMESPACE:"
        kubectl get pods -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • Pod: " $1 " (" $3 ")"}' || true
        kubectl get svc -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • Service: " $1 " (" $2 ")"}' || true
        kubectl get pvc -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • PVC: " $1 " (" $2 ")"}' || true
        kubectl get ingress -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • Ingress: " $1}' || true
    else
        echo "   ⚪ Redis Namespace ($REDIS_NAMESPACE): Not found"
    fi
    
    echo ""
    if kubectl get namespace "$OPERATOR_NAMESPACE" &> /dev/null; then
        operator_ns_exists=true
        operator_pods=$(kubectl get pods -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        
        echo "   🟡 Operator Namespace ($OPERATOR_NAMESPACE):"
        echo "      • Pods: $operator_pods"
        
        # Show operator resources
        echo ""
        log_info "   📋 Detailed resources in $OPERATOR_NAMESPACE:"
        kubectl get pods -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • Pod: " $1 " (" $3 ")"}' || true
        kubectl get svc -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | awk '{print "      • Service: " $1 " (" $2 ")"}' || true
    else
        echo "   ⚪ Operator Namespace ($OPERATOR_NAMESPACE): Not found"
    fi
    
    # Check for any Redis-related resources in other namespaces
    echo ""
    log_info "🔍 Checking for Redis resources in other namespaces..."
    
    # Check for ServiceMonitors
    redis_sm=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_sm" -gt "0" ]; then
        echo "   • ServiceMonitors with 'redis': $redis_sm"
        kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | grep -i redis | awk '{print "      • " $2 " in " $1}' || true
    fi
    
    # Check for PrometheusRules
    redis_pr=$(kubectl get prometheusrule --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_pr" -gt "0" ]; then
        echo "   • PrometheusRules with 'redis': $redis_pr"
        kubectl get prometheusrule --all-namespaces --no-headers 2>/dev/null | grep -i redis | awk '{print "      • " $2 " in " $1}' || true
    fi
    
    # Check Helm releases
    echo ""
    log_info "🔍 Checking Helm releases..."
    if [ -n "$HELM_BIN" ]; then
        redis_releases=$($HELM_BIN list --all-namespaces --no-headers 2>/dev/null | grep -E "(redis|ot-)" | wc -l || echo "0")
        if [ "$redis_releases" -gt "0" ]; then
            echo "   • Redis-related Helm releases: $redis_releases"
            $HELM_BIN list --all-namespaces --no-headers 2>/dev/null | grep -E "(redis|ot-)" | awk '{print "      • " $1 " in " $2}' || true
        else
            echo "   • No Redis-related Helm releases found"
        fi
    else
        log_warning "Helm binary not found - skipping Helm release check"
    fi
    
    echo ""
    if [ "$redis_ns_exists" = false ] && [ "$operator_ns_exists" = false ] && [ "$redis_sm" -eq "0" ] && [ "$redis_pr" -eq "0" ]; then
        log_warning "⚪ No Redis resources found to remove"
        return 1
    else
        log_warning "🗑️  Resources listed above will be PERMANENTLY DELETED"
        return 0
    fi
}

# Confirm deletion
confirm_deletion() {
    log_header "DELETION CONFIRMATION"
    
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete:"
    echo "   • All Redis data and configurations"
    echo "   • Redis Standalone and Cluster instances"
    echo "   • Client pods and tools"
    echo "   • RedisInsight web interface"
    echo "   • All persistent volumes and data"
    echo "   • Monitoring configurations"
    echo "   • Helm releases"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Are you sure you want to continue? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled by user"
        exit 0
    fi
    
    echo ""
    log_warning "🔥 FINAL WARNING: Starting deletion in 5 seconds..."
    log_warning "Press Ctrl+C now to cancel"
    sleep 5
    echo ""
}

# Remove Helm releases
remove_helm_releases() {
    log_header "REMOVING HELM RELEASES"
    
    if [ -z "$HELM_BIN" ]; then
        log_warning "Helm binary not found - skipping Helm release removal"
        return 0
    fi
    
    log_step "1/4" "Checking for Redis Helm releases"
    redis_releases=$($HELM_BIN list --all-namespaces --no-headers 2>/dev/null | grep -E "redis" || echo "")
    
    if [ -n "$redis_releases" ]; then
        echo "$redis_releases" | while read -r release_line; do
            release_name=$(echo "$release_line" | awk '{print $1}')
            release_namespace=$(echo "$release_line" | awk '{print $2}')
            
            log_step "•" "Removing Helm release: $release_name (namespace: $release_namespace)"
            $HELM_BIN uninstall "$release_name" --namespace "$release_namespace" || log_warning "Failed to remove $release_name"
        done
        log_success "Redis Helm releases removed"
    else
        log_info "No Redis Helm releases found"
    fi
    
    log_step "2/4" "Checking for operator Helm releases"
    operator_releases=$($HELM_BIN list --all-namespaces --no-headers 2>/dev/null | grep -E "(redis-operator|ot-)" || echo "")
    
    if [ -n "$operator_releases" ]; then
        echo "$operator_releases" | while read -r release_line; do
            release_name=$(echo "$release_line" | awk '{print $1}')
            release_namespace=$(echo "$release_line" | awk '{print $2}')
            
            log_step "•" "Removing operator release: $release_name (namespace: $release_namespace)"
            $HELM_BIN uninstall "$release_name" --namespace "$release_namespace" || log_warning "Failed to remove $release_name"
        done
        log_success "Operator Helm releases removed"
    else
        log_info "No operator Helm releases found"
    fi
    
    log_step "3/4" "Waiting for Helm resources cleanup"
    sleep 5
    log_success "Helm cleanup wait completed"
    
    log_step "4/4" "Removing Helm repository"
    $HELM_BIN repo remove ot-helm 2>/dev/null || log_warning "ot-helm repository not found or already removed"
    log_success "Helm repository cleanup completed"
}

# Remove Redis namespace and resources
remove_redis_namespace() {
    log_header "REMOVING REDIS NAMESPACE"
    
    if ! kubectl get namespace "$REDIS_NAMESPACE" &> /dev/null; then
        log_info "Redis namespace not found - skipping"
        return 0
    fi
    
    log_step "1/1" "Deleting Redis namespace"
    kubectl delete namespace "$REDIS_NAMESPACE" --timeout=180s
    log_success "Redis namespace removed"
}

# Remove operator namespace and resources  
remove_operator_namespace() {
    log_header "REMOVING OPERATOR NAMESPACE"
    
    if ! kubectl get namespace "$OPERATOR_NAMESPACE" &> /dev/null; then
        log_info "Operator namespace not found - skipping"
        return 0
    fi
    
    log_step "1/1" "Deleting operator namespace"
    kubectl delete namespace "$OPERATOR_NAMESPACE" --timeout=180s
    log_success "Operator namespace removed"
}

# Clean up persistent volumes
cleanup_persistent_volumes() {
    log_header "CLEANING UP PERSISTENT VOLUMES"
    
    log_step "1/3" "Finding Redis-related PVs"
    redis_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -E "(redis|ot-)" | awk '{print $1}' || echo "")
    
    if [ -n "$redis_pvs" ]; then
        log_warning "Found Redis-related PVs (these should auto-delete with PVCs):"
        echo "$redis_pvs" | while read -r pv_name; do
            pv_status=$(kubectl get pv "$pv_name" --no-headers 2>/dev/null | awk '{print $5}' || echo "Unknown")
            echo "   • PV: $pv_name (Status: $pv_status)"
        done
    else
        log_info "No Redis-related PVs found"
    fi
    
    log_step "2/3" "Checking for Released PVs"
    released_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep "Released" | awk '{print $1}' || echo "")
    
    if [ -n "$released_pvs" ]; then
        log_warning "Found Released PVs (may be from Redis):"
        echo "$released_pvs" | while read -r pv_name; do
            echo "   • Released PV: $pv_name"
        done
        
        read -p "$(echo -e ${YELLOW}Do you want to delete Released PVs? [y/N]: ${NC})" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$released_pvs" | while read -r pv_name; do
                log_step "•" "Deleting Released PV: $pv_name"
                kubectl delete pv "$pv_name" || log_warning "Failed to delete PV $pv_name"
            done
            log_success "Released PVs removed"
        else
            log_info "Released PVs kept (may require manual cleanup)"
        fi
    else
        log_info "No Released PVs found"
    fi
    
    log_step "3/3" "PV cleanup completed"
    log_success "Persistent volume cleanup completed"
}

# Remove monitoring resources
cleanup_monitoring() {
    log_header "CLEANING UP MONITORING RESOURCES"
    
    log_step "1/3" "Removing Redis ServiceMonitors"
    redis_servicemonitors=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | grep -i redis || echo "")
    
    if [ -n "$redis_servicemonitors" ]; then
        echo "$redis_servicemonitors" | while read -r sm_line; do
            sm_namespace=$(echo "$sm_line" | awk '{print $1}')
            sm_name=$(echo "$sm_line" | awk '{print $2}')
            log_step "•" "Removing ServiceMonitor: $sm_name (namespace: $sm_namespace)"
            kubectl delete servicemonitor "$sm_name" -n "$sm_namespace" || log_warning "Failed to remove ServiceMonitor $sm_name"
        done
        log_success "Redis ServiceMonitors removed"
    else
        log_info "No Redis ServiceMonitors found"
    fi
    
    log_step "2/3" "Removing Redis PrometheusRules"
    redis_prometheusrules=$(kubectl get prometheusrule --all-namespaces --no-headers 2>/dev/null | grep -i redis || echo "")
    
    if [ -n "$redis_prometheusrules" ]; then
        echo "$redis_prometheusrules" | while read -r pr_line; do
            pr_namespace=$(echo "$pr_line" | awk '{print $1}')
            pr_name=$(echo "$pr_line" | awk '{print $2}')
            log_step "•" "Removing PrometheusRule: $pr_name (namespace: $pr_namespace)"
            kubectl delete prometheusrule "$pr_name" -n "$pr_namespace" || log_warning "Failed to remove PrometheusRule $pr_name"
        done
        log_success "Redis PrometheusRules removed"
    else
        log_info "No Redis PrometheusRules found"
    fi
    
    log_step "3/3" "Monitoring cleanup completed"
    log_success "Monitoring resources cleanup completed"
}

# Remove CRDs (Custom Resource Definitions)
cleanup_crds() {
    log_header "CLEANING UP CUSTOM RESOURCE DEFINITIONS"
    
    log_step "1/2" "Checking for Redis CRDs"
    redis_crds=$(kubectl get crd --no-headers 2>/dev/null | grep -E "(redis|opstreelabs)" | awk '{print $1}' || echo "")
    
    if [ -n "$redis_crds" ]; then
        log_warning "Found Redis-related CRDs:"
        echo "$redis_crds" | while read -r crd_name; do
            echo "   • CRD: $crd_name"
        done
        
        echo ""
        read -p "$(echo -e ${YELLOW}Do you want to delete Redis CRDs? This will remove custom resource definitions. [y/N]: ${NC})" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$redis_crds" | while read -r crd_name; do
                log_step "•" "Removing CRD: $crd_name"
                kubectl delete crd "$crd_name" || log_warning "Failed to remove CRD $crd_name"
            done
            log_success "Redis CRDs removed"
        else
            log_info "Redis CRDs kept (may cause issues with reinstallation)"
        fi
    else
        log_info "No Redis-related CRDs found"
    fi
    
    log_step "2/2" "CRD cleanup completed"
    log_success "CRD cleanup completed"
}

# Final verification
final_verification() {
    log_header "FINAL VERIFICATION"
    
    local cleanup_score=0
    local max_score=8
    
    log_step "1/8" "Checking Redis namespace"
    if ! kubectl get namespace "$REDIS_NAMESPACE" &> /dev/null; then
        log_success "✓ Redis namespace removed"
        ((cleanup_score++))
    else
        log_warning "✗ Redis namespace still exists"
    fi
    
    log_step "2/8" "Checking operator namespace"
    if ! kubectl get namespace "$OPERATOR_NAMESPACE" &> /dev/null; then
        log_success "✓ Operator namespace removed"
        ((cleanup_score++))
    else
        log_warning "✗ Operator namespace still exists"
    fi
    
    log_step "3/8" "Checking Redis pods"
    redis_pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_pods" -eq "0" ]; then
        log_success "✓ No Redis pods found"
        ((cleanup_score++))
    else
        log_warning "✗ $redis_pods Redis pods still exist"
    fi
    
    log_step "4/8" "Checking Redis services"
    redis_svcs=$(kubectl get svc --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_svcs" -eq "0" ]; then
        log_success "✓ No Redis services found"
        ((cleanup_score++))
    else
        log_warning "✗ $redis_svcs Redis services still exist"
    fi
    
    log_step "5/8" "Checking Redis PVCs"
    redis_pvcs=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_pvcs" -eq "0" ]; then
        log_success "✓ No Redis PVCs found"
        ((cleanup_score++))
    else
        log_warning "✗ $redis_pvcs Redis PVCs still exist"
    fi
    
    log_step "6/8" "Checking Helm releases"
    if [ -f "$SCRIPT_DIR/helm" ]; then
        redis_releases=$($SCRIPT_DIR/helm list --all-namespaces --no-headers 2>/dev/null | grep -E "(redis|ot-)" | wc -l || echo "0")
        if [ "$redis_releases" -eq "0" ]; then
            log_success "✓ No Redis Helm releases found"
            ((cleanup_score++))
        else
            log_warning "✗ $redis_releases Redis Helm releases still exist"
        fi
    else
        log_warning "✗ Cannot check Helm releases (helm binary missing)"
    fi
    
    log_step "7/8" "Checking ServiceMonitors"
    redis_sm=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_sm" -eq "0" ]; then
        log_success "✓ No Redis ServiceMonitors found"
        ((cleanup_score++))
    else
        log_warning "✗ $redis_sm Redis ServiceMonitors still exist"
    fi
    
    log_step "8/8" "Checking PrometheusRules"  
    redis_pr=$(kubectl get prometheusrule --all-namespaces --no-headers 2>/dev/null | grep -i redis | wc -l || echo "0")
    if [ "$redis_pr" -eq "0" ]; then
        log_success "✓ No Redis PrometheusRules found"
        ((cleanup_score++))
    else
        log_warning "✗ $redis_pr Redis PrometheusRules still exist"
    fi
    
    # Final cleanup score
    echo ""
    if [ "$cleanup_score" -eq "$max_score" ]; then
        log_success "🎉 REDIS UNINSTALLATION: 100% COMPLETE ($cleanup_score/$max_score)"
        echo -e "${GREEN}All Redis components successfully removed!${NC}"
    elif [ "$cleanup_score" -ge "6" ]; then
        log_success "✅ REDIS UNINSTALLATION: MOSTLY COMPLETE ($cleanup_score/$max_score)"
        echo -e "${YELLOW}Minor cleanup items may remain but core removal successful.${NC}"
    elif [ "$cleanup_score" -ge "4" ]; then
        log_warning "⚠️  REDIS UNINSTALLATION: PARTIALLY COMPLETE ($cleanup_score/$max_score)"
        echo -e "${YELLOW}Some components still exist. Manual cleanup may be required.${NC}"
    else
        log_error "❌ REDIS UNINSTALLATION: INCOMPLETE ($cleanup_score/$max_score)"
        echo -e "${RED}Multiple components still exist. Review the cleanup process.${NC}"
        return 1
    fi
}

# Display post-uninstall information
display_cleanup_info() {
    log_header "CLEANUP COMPLETED"
    
    echo ""
    log_info "🧹 Redis Uninstallation Summary:"
    echo "   • Redis Standalone: Removed"
    echo "   • Redis Cluster: Removed"
    echo "   • Redis Operator: Removed"
    echo "   • Client Tools: Removed"
    echo "   • Web Interface: Removed"
    echo "   • Monitoring: Removed"
    echo "   • Storage: Removed/Released"
    echo ""
    
    log_info "🔄 Next Steps:"
    echo "   • Cluster is ready for fresh Redis installation"
    echo "   • Run './redis-automated-install.sh' to reinstall"
    echo "   • All previous data and configurations are gone"
    echo "   • Storage volumes have been cleaned up"
    echo ""
    
    log_info "⚠️  Manual Checks (if needed):"
    echo "   • Check for any remaining PVs: kubectl get pv"
    echo "   • Check for any remaining CRDs: kubectl get crd | grep redis"
    echo "   • Check all namespaces: kubectl get all --all-namespaces | grep redis"
    echo ""
}

# Cleanup function for script errors
cleanup_on_error() {
    log_error "Uninstallation encountered an error"
    log_warning "Some resources may not have been completely removed"
    log_info "You may need to run the script again or perform manual cleanup"
    exit 1
}

# Main execution
main() {
    log_header "REDIS COMPLETE UNINSTALLATION"
    echo -e "${CYAN}This script will completely remove Redis from your Kubernetes cluster${NC}"
    echo -e "${CYAN}All data will be permanently lost!${NC}"
    echo ""
    
    # Trap errors
    trap cleanup_on_error ERR
    
    # Start timer
    start_time=$(date +%s)
    
    # Execute uninstallation steps
    check_prerequisites
    
    # Show what will be removed and get confirmation
    if ! show_current_resources; then
        log_info "Nothing to remove - cluster is already clean"
        exit 0
    fi
    
    confirm_deletion
    remove_helm_releases
    remove_redis_namespace
    remove_operator_namespace
    cleanup_persistent_volumes
    cleanup_monitoring
    cleanup_crds
    final_verification
    display_cleanup_info
    
    # Calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    
    echo ""
    log_success "🧹 REDIS UNINSTALLATION COMPLETED SUCCESSFULLY!"
    echo -e "${GREEN}Total time: ${minutes}m ${seconds}s${NC}"
    echo ""
    echo -e "${PURPLE}=== READY FOR FRESH INSTALLATION ===${NC}"
    echo -e "${CYAN}You can now run: ./redis-automated-install.sh${NC}"
    echo ""
}

# Execute main function
main "$@"
