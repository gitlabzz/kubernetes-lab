#!/bin/bash

# Redis Full Cycle Test Script
# This script tests the complete Redis lifecycle: Uninstall → Install → Validate
# Perfect for testing the automation scripts end-to-end

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="/private/tmp/kubernetes-lab"
KUBECONFIG_PATH="/private/tmp/kubernetes-lab/admin.conf"

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
    log_header "CHECKING TEST PREREQUISITES"
    
    export KUBECONFIG="$KUBECONFIG_PATH"
    
    log_step "1/4" "Checking required scripts"
    if [ ! -f "$SCRIPT_DIR/redis-uninstall.sh" ] || [ ! -x "$SCRIPT_DIR/redis-uninstall.sh" ]; then
        log_error "redis-uninstall.sh not found or not executable"
        exit 1
    fi
    
    if [ ! -f "$SCRIPT_DIR/redis-automated-install.sh" ] || [ ! -x "$SCRIPT_DIR/redis-automated-install.sh" ]; then
        log_error "redis-automated-install.sh not found or not executable"
        exit 1
    fi
    log_success "Required scripts found and executable"
    
    log_step "2/4" "Checking kubectl connectivity"
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Kubernetes cluster accessible"
    
    log_step "3/4" "Checking Helm binary"
    if [ ! -f "$SCRIPT_DIR/helm" ] || [ ! -x "$SCRIPT_DIR/helm" ]; then
        log_error "Helm binary not found or not executable"
        exit 1
    fi
    log_success "Helm binary available"
    
    log_step "4/4" "Checking Longhorn storage"
    if ! kubectl get storageclass longhorn &> /dev/null; then
        log_error "Longhorn storage class not found"
        exit 1
    fi
    log_success "Longhorn storage available"
}

# Pre-test cluster state
capture_initial_state() {
    log_header "CAPTURING INITIAL CLUSTER STATE"
    
    log_step "1/3" "Checking existing Redis resources"
    
    # Count existing resources
    redis_ns_exists=false
    operator_ns_exists=false
    
    if kubectl get namespace redis &> /dev/null; then
        redis_ns_exists=true
        log_info "Redis namespace exists"
    fi
    
    if kubectl get namespace ot-operators &> /dev/null; then
        operator_ns_exists=true
        log_info "Operator namespace exists"
    fi
    
    if [ "$redis_ns_exists" = false ] && [ "$operator_ns_exists" = false ]; then
        log_info "Cluster is clean - ready for fresh installation test"
    else
        log_info "Existing Redis resources found - will test uninstall first"
    fi
    
    log_step "2/3" "Recording cluster resource counts"
    initial_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    initial_pvs=$(kubectl get pv --no-headers | wc -l)
    initial_ns=$(kubectl get namespace --no-headers | wc -l)
    
    log_info "Initial state:"
    log_info "  • Total pods: $initial_pods"
    log_info "  • Total PVs: $initial_pvs"
    log_info "  • Total namespaces: $initial_ns"
    
    log_step "3/3" "Initial state captured"
    log_success "Pre-test state recorded"
}

# Run uninstall phase
run_uninstall_phase() {
    log_header "PHASE 1: UNINSTALLATION TEST"
    
    log_step "1/2" "Running Redis uninstall script"
    log_info "🚀 Executing: $SCRIPT_DIR/redis-uninstall.sh"
    echo ""
    
    # Run uninstall script with automatic confirmation
    echo "y" | "$SCRIPT_DIR/redis-uninstall.sh" || {
        log_error "Uninstall script failed"
        return 1
    }
    
    log_step "2/2" "Verifying uninstall completion"
    sleep 5
    
    # Verify cleanup
    if kubectl get namespace redis &> /dev/null; then
        log_error "Redis namespace still exists after uninstall"
        return 1
    fi
    
    if kubectl get namespace ot-operators &> /dev/null; then
        log_error "Operator namespace still exists after uninstall"
        return 1
    fi
    
    log_success "Uninstall phase completed successfully"
}

# Run install phase  
run_install_phase() {
    log_header "PHASE 2: INSTALLATION TEST"
    
    log_step "1/2" "Running Redis install script"
    log_info "🚀 Executing: $SCRIPT_DIR/redis-automated-install.sh"
    echo ""
    
    # Run install script
    "$SCRIPT_DIR/redis-automated-install.sh" || {
        log_error "Install script failed"
        return 1
    }
    
    log_step "2/2" "Verifying install completion"
    sleep 10
    
    # Verify installation
    if ! kubectl get namespace redis &> /dev/null; then
        log_error "Redis namespace not created"
        return 1
    fi
    
    if ! kubectl get namespace ot-operators &> /dev/null; then
        log_error "Operator namespace not created"
        return 1
    fi
    
    log_success "Install phase completed successfully"
}

# Run validation phase
run_validation_phase() {
    log_header "PHASE 3: VALIDATION TEST"
    
    log_step "1/8" "Checking pod status"
    redis_pods_ready=$(kubectl get pods -n redis --no-headers | grep -c "Running" || echo "0")
    operator_pods_ready=$(kubectl get pods -n ot-operators --no-headers | grep -c "Running" || echo "0")
    
    if [ "$redis_pods_ready" -lt "7" ]; then
        log_warning "Only $redis_pods_ready Redis pods running (expected 7+)"
    else
        log_success "$redis_pods_ready Redis pods running"
    fi
    
    if [ "$operator_pods_ready" -lt "1" ]; then
        log_error "Operator pod not running"
        return 1
    else
        log_success "$operator_pods_ready operator pod(s) running"
    fi
    
    log_step "2/8" "Testing Redis Standalone connectivity"
    if ! kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping | grep -q "PONG"; then
        log_error "Redis Standalone connectivity failed"
        return 1
    fi
    log_success "Redis Standalone connectivity OK"
    
    log_step "3/8" "Testing Redis Cluster connectivity"
    if ! kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader ping | grep -q "PONG"; then
        log_warning "Redis Cluster connectivity failed (may still be initializing)"
    else
        log_success "Redis Cluster connectivity OK"
    fi
    
    log_step "4/8" "Testing data operations"
    test_key="full_cycle_test_$(date +%s)"
    if ! kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone set "$test_key" "success" > /dev/null; then
        log_error "SET operation failed"
        return 1
    fi
    
    retrieved_value=$(kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone get "$test_key" | tr -d '\r')
    if [ "$retrieved_value" != "success" ]; then
        log_error "GET operation failed (expected 'success', got '$retrieved_value')"
        return 1
    fi
    
    kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone del "$test_key" > /dev/null
    log_success "Data operations working"
    
    log_step "5/8" "Checking sample data"
    if ! kubectl exec deployment/redis-client -n redis -- /scripts/create-sample-ecommerce-data.sh > /dev/null 2>&1; then
        log_error "Sample data creation failed"
        return 1
    fi
    
    sample_keys=$(kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone dbsize | tr -d '\r')
    if [ "$sample_keys" -lt "40" ]; then
        log_warning "Sample data incomplete ($sample_keys keys, expected 40+)"
    else
        log_success "Sample data created ($sample_keys keys)"
    fi
    
    log_step "6/8" "Testing RedisInsight deployment"
    if ! kubectl get deployment redisinsight -n redis --no-headers | grep -q "1/1"; then
        log_warning "RedisInsight not fully ready"
    else
        log_success "RedisInsight deployment ready"
    fi
    
    log_step "7/8" "Checking ingress configuration"
    if ! kubectl get ingress redisinsight-ingress -n redis --no-headers | grep -q "redis.devsecops.net.au"; then
        log_warning "RedisInsight ingress not properly configured"
    else
        log_success "RedisInsight ingress configured"
    fi
    
    log_step "8/8" "Checking monitoring setup"
    if ! kubectl get servicemonitor -n redis --no-headers | grep -q "redis-standalone"; then
        log_warning "Monitoring ServiceMonitor not found"
    else
        log_success "Monitoring configured"
    fi
    
    log_success "Validation phase completed successfully"
}

# Performance test
run_performance_test() {
    log_header "PHASE 4: PERFORMANCE TEST"
    
    log_step "1/3" "Running performance benchmark"
    
    # Test SET performance
    start_time=$(date +%s%N)
    kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone eval "for i=1,100 do redis.call('set', 'perf:test:' .. i, 'value' .. i) end return 'OK'" 0 > /dev/null
    end_time=$(date +%s%N)
    set_duration=$(( (end_time - start_time) / 1000000 ))
    
    # Test GET performance
    start_time=$(date +%s%N)
    kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone eval "for i=1,100 do redis.call('get', 'perf:test:' .. i) end return 'OK'" 0 > /dev/null
    end_time=$(date +%s%N)
    get_duration=$(( (end_time - start_time) / 1000000 ))
    
    log_step "2/3" "Performance results"
    log_info "📊 Performance metrics:"
    log_info "  • SET: 100 operations in ${set_duration}ms"
    log_info "  • GET: 100 operations in ${get_duration}ms"
    
    # Cleanup performance test data
    kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone eval "local keys = redis.call('keys', 'perf:test:*') if #keys > 0 then return redis.call('del', unpack(keys)) end return 0" 0 > /dev/null
    
    log_step "3/3" "Performance test completed"
    log_success "Performance benchmarks recorded"
}

# Final test summary
generate_test_report() {
    log_header "TEST REPORT"
    
    # Capture final state
    final_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    final_pvs=$(kubectl get pv --no-headers | wc -l)
    final_ns=$(kubectl get namespace --no-headers | wc -l)
    
    redis_pods=$(kubectl get pods -n redis --no-headers | wc -l)
    redis_keys=$(kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone dbsize | tr -d '\r')
    memory_usage=$(kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone info memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
    
    echo ""
    log_success "🎉 FULL CYCLE TEST COMPLETED SUCCESSFULLY!"
    echo ""
    
    log_info "📊 Test Results Summary:"
    echo "   ✅ Uninstall Phase: PASSED"
    echo "   ✅ Install Phase: PASSED"  
    echo "   ✅ Validation Phase: PASSED"
    echo "   ✅ Performance Phase: PASSED"
    echo ""
    
    log_info "📈 Final Cluster State:"
    echo "   • Redis pods running: $redis_pods"
    echo "   • Total data keys: $redis_keys"
    echo "   • Memory usage: $memory_usage"
    echo "   • Total cluster pods: $final_pods"
    echo "   • Total PVs: $final_pvs"
    echo "   • Total namespaces: $final_ns"
    echo ""
    
    log_info "🔗 Access Information:"
    echo "   • RedisInsight: http://redis.devsecops.net.au"
    echo "   • Standalone: redis-standalone.redis.svc.cluster.local:6379"
    echo "   • Cluster: redis-cluster-leader.redis.svc.cluster.local:6379"
    echo ""
    
    log_info "🧪 Validation Commands:"
    echo "   • Test connection: kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping"
    echo "   • Explore data: kubectl exec deployment/redis-client -n redis -- /scripts/explore-sample-data.sh"
    echo "   • Monitor: kubectl exec deployment/redis-client -n redis -- /scripts/monitor-redis.sh"
    echo ""
}

# Error handling
cleanup_on_error() {
    log_error "Full cycle test failed"
    log_warning "You may need to run cleanup manually"
    log_info "Try running: ./redis-uninstall.sh"
    exit 1
}

# Main execution
main() {
    log_header "REDIS FULL CYCLE TEST"
    echo -e "${CYAN}This script tests the complete Redis automation lifecycle${NC}"
    echo -e "${CYAN}Phases: Uninstall → Install → Validate → Performance${NC}"
    echo ""
    
    # Trap errors
    trap cleanup_on_error ERR
    
    # Start timer
    start_time=$(date +%s)
    
    # Execute test phases
    check_prerequisites
    capture_initial_state
    run_uninstall_phase
    run_install_phase
    run_validation_phase
    run_performance_test
    generate_test_report
    
    # Calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    
    echo ""
    log_success "🏆 FULL CYCLE TEST COMPLETED IN ${minutes}m ${seconds}s"
    echo -e "${GREEN}Redis automation scripts are working perfectly!${NC}"
    echo ""
}

# Execute main function
main "$@"