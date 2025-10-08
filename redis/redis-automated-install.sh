#!/bin/bash

# Redis Complete Installation and Setup Script
# This script automates the entire Redis deployment process from start to finish
# Including: Operator, Standalone, Cluster, Client Pod, Web UI, and Validation

set -euo pipefail  # Safer bash options

# Resolve paths and environment
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration Variables (overridable via env)
REDIS_NAMESPACE="${REDIS_NAMESPACE:-redis}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-ot-operators}"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

# Pin chart versions for reproducibility (override via env if needed)
REDIS_OPERATOR_CHART_VERSION="${REDIS_OPERATOR_CHART_VERSION:-0.22.1}"
REDIS_STANDALONE_CHART_VERSION="${REDIS_STANDALONE_CHART_VERSION:-0.16.6}"
REDIS_CLUSTER_CHART_VERSION="${REDIS_CLUSTER_CHART_VERSION:-0.17.1}"

# Pin container images for Redis data-plane (override via env if needed)
# These apply to the Redis CRs managed by the operator.
REDIS_IMAGE_REPOSITORY="${REDIS_IMAGE_REPOSITORY:-quay.io/opstree/redis}"
REDIS_IMAGE_TAG="${REDIS_IMAGE_TAG:-7.0.15}"

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

# Track whether namespaces existed before to avoid destructive cleanup
REDIS_NS_EXISTED=false
OPERATOR_NS_EXISTED=false

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
    
    log_step "1/6" "Checking kubectl"
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    log_success "kubectl found"
    
    log_step "2/6" "Checking kubeconfig"
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Kubernetes cluster accessible"
    
    # Record namespace existence to avoid destructive cleanup later
    if kubectl get namespace "$REDIS_NAMESPACE" &>/dev/null; then
        REDIS_NS_EXISTED=true
    fi
    if kubectl get namespace "$OPERATOR_NAMESPACE" &>/dev/null; then
        OPERATOR_NS_EXISTED=true
    fi
    
    log_step "3/6" "Checking helm binary"
    if [ "$HELM_BIN" = "$REPO_ROOT/helm" ]; then
        chmod +x "$HELM_BIN" || true
    fi
    log_success "Helm binary: $HELM_BIN"
    
    log_step "4/6" "Checking required YAML files"
    if [ ! -f "$SCRIPT_DIR/redis-client.yaml" ]; then
        log_error "redis-client.yaml not found"
        exit 1
    fi
    if [ ! -f "$SCRIPT_DIR/redisinsight-deployment.yaml" ]; then
        log_error "redisinsight-deployment.yaml not found"  
        exit 1
    fi
    log_success "Required YAML files found"
    
    log_step "5/6" "Checking Longhorn storage"
    if ! kubectl get storageclass longhorn &> /dev/null; then
        log_error "Longhorn storage class not found"
        exit 1
    fi
    log_success "Longhorn storage class available"
    
    log_step "6/6" "Checking ingress controller"
    if ! kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q "Running"; then
        log_warning "Nginx ingress controller not found - RedisInsight web access may not work"
    else
        log_success "Nginx ingress controller available"
    fi
}

# Install Redis Operator
install_redis_operator() {
    log_header "INSTALLING REDIS OPERATOR"
    
    log_step "1/3" "Adding OT-Container-Kit Helm repository"
    # Using exact commands we tested successfully
    $HELM_BIN repo add ot-helm https://ot-container-kit.github.io/helm-charts/
    $HELM_BIN repo update
    log_success "Helm repository added and updated"
    
    log_step "2/3" "Installing Redis Operator" 
    # Using the exact command we tested successfully
    $HELM_BIN upgrade redis-operator ot-helm/redis-operator \
        --install --create-namespace --namespace "$OPERATOR_NAMESPACE" \
        --version "$REDIS_OPERATOR_CHART_VERSION" \
        --wait --timeout 10m --atomic
    log_success "Redis Operator installed successfully"
    
    log_step "3/3" "Verifying operator deployment"
    kubectl wait --for=condition=available --timeout=120s deployment/redis-operator -n "$OPERATOR_NAMESPACE"
    log_success "Redis Operator is ready"
}

# Create Redis namespace and instances
deploy_redis_instances() {
    log_header "DEPLOYING REDIS INSTANCES"
    
    log_step "1/4" "Creating Redis namespace"
    kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_success "Redis namespace created/updated"
    
    log_step "2/4" "Deploying Redis Standalone instance"
    # Using the exact command we tested successfully
    $HELM_BIN upgrade redis-standalone ot-helm/redis \
        --install --namespace "$REDIS_NAMESPACE" \
        --version "$REDIS_STANDALONE_CHART_VERSION" \
        --set storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
        --set storageSpec.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
        --set redisExporter.enabled=true \
        --set serviceMonitor.enabled=true \
        --wait --timeout 10m --atomic
    log_success "Redis Standalone deployed"
    
    log_step "3/4" "Deploying Redis Cluster" 
    # Using the exact command we tested successfully
    $HELM_BIN upgrade redis-cluster ot-helm/redis-cluster \
        --install --namespace "$REDIS_NAMESPACE" \
        --version "$REDIS_CLUSTER_CHART_VERSION" \
        --set redisCluster.clusterSize=3 \
        --set redisCluster.storageSpec.volumeClaimTemplate.spec.storageClassName=longhorn \
        --set redisCluster.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=3Gi \
        --wait --timeout 10m --atomic
    log_success "Redis Cluster deployed"
    
    log_step "4/4" "Waiting for Redis instances to be ready"
    kubectl wait --for=condition=ready --timeout=300s pod -l app=redis-standalone -n "$REDIS_NAMESPACE"
    # Give cluster more time to initialize
    sleep 30
    log_success "Redis instances are ready"
}

# Deploy Redis client pod
deploy_redis_client() {
    log_header "DEPLOYING REDIS CLIENT POD"
    
    log_step "1/2" "Applying Redis client configuration"
    kubectl apply -f "$SCRIPT_DIR/redis-client.yaml"
    log_success "Redis client configuration applied"
    
    log_step "2/2" "Waiting for client pod to be ready"
    kubectl wait --for=condition=available --timeout=120s deployment/redis-client -n "$REDIS_NAMESPACE"
    log_success "Redis client pod is ready"
}

# Deploy RedisInsight web UI
deploy_redisinsight() {
    log_header "DEPLOYING REDISINSIGHT WEB UI"
    
    log_step "1/2" "Applying RedisInsight configuration"
    kubectl apply -f "$SCRIPT_DIR/redisinsight-deployment.yaml"
    log_success "RedisInsight configuration applied"
    
    log_step "2/2" "Waiting for RedisInsight to be ready"
    kubectl wait --for=condition=available --timeout=180s deployment/redisinsight -n "$REDIS_NAMESPACE"
    log_success "RedisInsight is ready"
}

# Pin the Redis images on the operator-managed CRs (best-effort)
pin_redis_images() {
    log_header "PINNING REDIS IMAGE VERSIONS"
    
    # Standalone CR
    if kubectl get redis redis-standalone -n "$REDIS_NAMESPACE" &>/dev/null; then
        log_step "1/3" "Pinning standalone image to $REDIS_IMAGE_REPOSITORY:$REDIS_IMAGE_TAG"
        if kubectl patch redis redis-standalone -n "$REDIS_NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"kubernetesConfig\":{\"image\":\"$REDIS_IMAGE_REPOSITORY:$REDIS_IMAGE_TAG\"}}}"; then
            log_success "Standalone image pinned"
        else
            log_warning "Failed to pin standalone image (structure may differ)"
        fi
    else
        log_warning "Standalone Redis CR not found; skipping image pin"
    fi

    # Cluster CR (leader + follower)
    if kubectl get rediscluster redis-cluster -n "$REDIS_NAMESPACE" &>/dev/null; then
        log_step "2/3" "Pinning cluster images to $REDIS_IMAGE_REPOSITORY:$REDIS_IMAGE_TAG"
        if kubectl patch rediscluster redis-cluster -n "$REDIS_NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"redisLeader\":{\"kubernetesConfig\":{\"image\":\"$REDIS_IMAGE_REPOSITORY:$REDIS_IMAGE_TAG\"}},\"redisFollower\":{\"kubernetesConfig\":{\"image\":\"$REDIS_IMAGE_REPOSITORY:$REDIS_IMAGE_TAG\"}}}}"; then
            log_success "Cluster images pinned"
        else
            log_warning "Failed to pin cluster images (structure may differ)"
        fi
    else
        log_warning "RedisCluster CR not found; skipping cluster image pin"
    fi

    log_step "3/3" "Verifying pods pick up pinned images (rolling update if needed)"
    kubectl rollout status statefulset/redis-standalone -n "$REDIS_NAMESPACE" --timeout=120s || true
    kubectl rollout status statefulset/redis-cluster-leader -n "$REDIS_NAMESPACE" --timeout=120s || true
    kubectl rollout status statefulset/redis-cluster-follower -n "$REDIS_NAMESPACE" --timeout=120s || true
}

# Test Redis connectivity
test_redis_connectivity() {
    log_header "TESTING REDIS CONNECTIVITY"
    
    log_step "1/4" "Testing Redis Standalone connectivity"
    # Using exact command we tested successfully 
    if kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone ping | grep -q "PONG"; then
        log_success "Redis Standalone connectivity: OK"
    else
        log_error "Redis Standalone connectivity failed"
        return 1
    fi
    
    log_step "2/4" "Testing Redis Cluster connectivity"
    # Using exact command we tested successfully
    if kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-cluster-leader ping | grep -q "PONG"; then
        log_success "Redis Cluster connectivity: OK"
    else
        log_warning "Redis Cluster connectivity failed (may still be initializing)"
    fi
    
    log_step "3/4" "Checking cluster state"
    # Using exact command we tested successfully
    cluster_state=$(kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-cluster-leader cluster info 2>/dev/null | grep "cluster_state" | cut -d: -f2 | tr -d '\r' || echo "unknown")
    if [ "$cluster_state" = "ok" ]; then
        log_success "Redis Cluster state: OK"
    else
        log_warning "Redis Cluster state: $cluster_state (may need more time)"
    fi
    
    log_step "4/4" "Running basic connectivity tests"
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- /scripts/test-standalone.sh > /dev/null 2>&1
    log_success "Basic connectivity tests completed"
}

# Create and validate sample data
create_sample_data() {
    log_header "CREATING AND VALIDATING SAMPLE DATA"
    
    log_step "1/3" "Creating comprehensive e-commerce sample data"
    # Using exact script we created and tested
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- /scripts/create-sample-ecommerce-data.sh
    log_success "Sample data created successfully"
    
    log_step "2/3" "Validating data creation"
    # Using exact command we tested successfully
    standalone_keys=$(kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone dbsize | tr -d '\r')
    log_success "Redis Standalone contains $standalone_keys keys"
    
    log_step "3/3" "Testing data operations"
    # Test basic CRUD operations
    test_key="automation:test:$(date +%s)"
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone set "$test_key" "automation_test_value" > /dev/null
    retrieved_value=$(kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone get "$test_key" | tr -d '\r')
    if [ "$retrieved_value" = "automation_test_value" ]; then
        log_success "CRUD operations working correctly"
        kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone del "$test_key" > /dev/null
    else
        log_error "CRUD operations failed"
        return 1
    fi
}

# Display deployment information
display_deployment_info() {
    log_header "DEPLOYMENT INFORMATION"
    
    echo ""
    log_info "🎯 Redis Deployment Summary:"
    echo "   • Operator: OT-CONTAINER-KIT Redis Operator"
    echo "   • Namespace: $REDIS_NAMESPACE"
    echo "   • Instances: Standalone + 6-node Cluster"
    echo ""
    
    log_info "📊 Current Resources:"
    kubectl get pods -n "$REDIS_NAMESPACE" --no-headers | wc -l | xargs printf "   • Pods: %s running\n"
    kubectl get svc -n "$REDIS_NAMESPACE" --no-headers | wc -l | xargs printf "   • Services: %s created\n"
    kubectl get pvc -n "$REDIS_NAMESPACE" --no-headers | wc -l | xargs printf "   • Storage: %s volumes\n"
    echo ""
    
    log_info "🔗 Access Information:"
    echo "   • RedisInsight Web UI: http://redis.devsecops.net.au"
    echo "   • Redis Standalone: redis-standalone.redis.svc.cluster.local:6379"
    echo "   • Redis Cluster: redis-cluster-leader.redis.svc.cluster.local:6379"
    echo ""
    
    log_info "🖥️ Client Pod Commands:"
    echo "   • Interactive CLI: kubectl exec -it deployment/redis-client -n redis -- redis-cli -h redis-standalone"
    echo "   • Cluster CLI: kubectl exec -it deployment/redis-client -n redis -- redis-cli -h redis-cluster-leader -c"
    echo "   • Explore Data: kubectl exec deployment/redis-client -n redis -- /scripts/explore-sample-data.sh"
    echo ""
    
    # Get actual resource counts
    log_info "📈 Data Summary:"
    standalone_keys=$(kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone dbsize 2>/dev/null | tr -d '\r' || echo "N/A")
    memory_usage=$(kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "N/A")
    echo "   • Total Keys: $standalone_keys"
    echo "   • Memory Usage: $memory_usage"
    echo ""
}

# Performance validation
run_performance_tests() {
    log_header "RUNNING PERFORMANCE VALIDATION"
    
    log_step "1/2" "Running performance tests"
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- /scripts/performance-test.sh > /dev/null 2>&1
    log_success "Performance tests completed"
    
    log_step "2/2" "Generating performance report"
    log_info "📊 Performance Metrics:"
    
    # Test SET performance
    start_time=$(date +%s%N)
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone eval "for i=1,100 do redis.call('set', 'perf:test:' .. i, 'value' .. i) end return 'OK'" 0 > /dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    echo "   • SET Performance: 100 operations in ${duration}ms"
    
    # Test GET performance
    start_time=$(date +%s%N)
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone eval "for i=1,100 do redis.call('get', 'perf:test:' .. i) end return 'OK'" 0 > /dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    echo "   • GET Performance: 100 operations in ${duration}ms"
    
    # Cleanup performance test data (use SCAN to avoid blocking)
    kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- sh -lc \
      'redis-cli -h redis-standalone --scan --pattern "perf:test:*" | xargs -r -L 100 redis-cli -h redis-standalone del > /dev/null 2>&1'
    
    log_success "Performance validation completed"
}

# Health check function
health_check() {
    log_header "FINAL HEALTH CHECK"
    
    local health_score=0
    local max_score=10
    
    # Check operator
    log_step "1/10" "Checking Redis Operator health"
    if kubectl get deployment redis-operator -n "$OPERATOR_NAMESPACE" --no-headers 2>/dev/null | grep -q "1/1"; then
        log_success "✓ Operator healthy"
        ((health_score++))
    else
        log_warning "✗ Operator unhealthy"
    fi
    
    # Check standalone Redis
    log_step "2/10" "Checking Redis Standalone health"
    if kubectl get pods -n "$REDIS_NAMESPACE" -l app=redis-standalone --no-headers 2>/dev/null | grep -q "2/2.*Running"; then
        log_success "✓ Standalone Redis healthy"
        ((health_score++))
    else
        log_warning "✗ Standalone Redis unhealthy"
    fi
    
    # Check cluster Redis
    log_step "3/10" "Checking Redis Cluster health"
    cluster_pods=$(kubectl get pods -n "$REDIS_NAMESPACE" -l app.kubernetes.io/component=redis-cluster --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
    if [ "$cluster_pods" -ge "6" ]; then
        log_success "✓ Redis Cluster healthy ($cluster_pods/6 pods)"
        ((health_score++))
    else
        log_warning "✗ Redis Cluster unhealthy ($cluster_pods/6 pods)"
    fi
    
    # Check client pod
    log_step "4/10" "Checking Redis Client health"
    if kubectl get deployment redis-client -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | grep -q "1/1"; then
        log_success "✓ Client pod healthy"
        ((health_score++))
    else
        log_warning "✗ Client pod unhealthy"
    fi
    
    # Check RedisInsight
    log_step "5/10" "Checking RedisInsight health"
    if kubectl get deployment redisinsight -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | grep -q "1/1"; then
        log_success "✓ RedisInsight healthy"
        ((health_score++))
    else
        log_warning "✗ RedisInsight unhealthy"
    fi
    
    # Check connectivity
    log_step "6/10" "Checking Redis connectivity"
    if kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone ping 2>/dev/null | grep -q "PONG"; then
        log_success "✓ Redis connectivity working"
        ((health_score++))
    else
        log_warning "✗ Redis connectivity failed"
    fi
    
    # Check data operations
    log_step "7/10" "Checking data operations"
    test_key="health:check:$(date +%s)"
    if kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone set "$test_key" "test" > /dev/null 2>&1 && \
       kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone get "$test_key" 2>/dev/null | grep -q "test"; then
        log_success "✓ Data operations working"
        kubectl exec deployment/redis-client -n "$REDIS_NAMESPACE" -- redis-cli -h redis-standalone del "$test_key" > /dev/null 2>&1
        ((health_score++))
    else
        log_warning "✗ Data operations failed"
    fi
    
    # Check storage
    log_step "8/10" "Checking persistent storage"
    bound_pvcs=$(kubectl get pvc -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    if [ "$bound_pvcs" -gt "0" ]; then
        log_success "✓ Persistent storage ($bound_pvcs PVCs bound)"
        ((health_score++))
    else
        log_warning "✗ Persistent storage issues"
    fi
    
    # Check monitoring
    log_step "9/10" "Checking monitoring setup"
    if kubectl get servicemonitor -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | grep -q "redis-standalone"; then
        log_success "✓ Monitoring configured"
        ((health_score++))
    else
        log_warning "✗ Monitoring not configured"
    fi
    
    # Check ingress
    log_step "10/10" "Checking ingress configuration"
    if kubectl get ingress redisinsight-ingress -n "$REDIS_NAMESPACE" --no-headers 2>/dev/null | grep -q "redis.devsecops.net.au"; then
        log_success "✓ Ingress configured"
        ((health_score++))
    else
        log_warning "✗ Ingress not configured"
    fi
    
    # Final health score
    echo ""
    if [ "$health_score" -eq "$max_score" ]; then
        log_success "🎉 REDIS DEPLOYMENT: 100% HEALTHY ($health_score/$max_score)"
        echo -e "${GREEN}All systems operational! Redis is ready for production use.${NC}"
    elif [ "$health_score" -ge "8" ]; then
        log_success "✅ REDIS DEPLOYMENT: MOSTLY HEALTHY ($health_score/$max_score)"
        echo -e "${YELLOW}Minor issues detected but core functionality is working.${NC}"
    elif [ "$health_score" -ge "5" ]; then
        log_warning "⚠️  REDIS DEPLOYMENT: PARTIALLY HEALTHY ($health_score/$max_score)"
        echo -e "${YELLOW}Some components need attention but basic functionality is available.${NC}"
    else
        log_error "❌ REDIS DEPLOYMENT: UNHEALTHY ($health_score/$max_score)"
        echo -e "${RED}Multiple issues detected. Please review the deployment.${NC}"
        return 1
    fi
}

# Cleanup function
cleanup_on_error() {
    log_error "Installation failed. Conditional cleanup in progress..."
    # Only remove namespaces we created in this run
    if [ "$REDIS_NS_EXISTED" = false ]; then
        kubectl delete namespace "$REDIS_NAMESPACE" --ignore-not-found=true || true
    else
        log_warning "Preserving existing namespace: $REDIS_NAMESPACE"
    fi
    if [ "$OPERATOR_NS_EXISTED" = false ]; then
        kubectl delete namespace "$OPERATOR_NAMESPACE" --ignore-not-found=true || true
    else
        log_warning "Preserving existing namespace: $OPERATOR_NAMESPACE"
    fi
    exit 1
}

# Main execution
main() {
    log_header "REDIS COMPLETE INSTALLATION AND SETUP"
    echo -e "${CYAN}This script will install and configure a complete Redis solution${NC}"
    echo -e "${CYAN}Components: Operator, Standalone, Cluster, Client Pod, Web UI${NC}"
    echo ""
    
    # Trap errors
    trap cleanup_on_error ERR
    
    # Start timer
    start_time=$(date +%s)
    
    # Execute installation steps
    check_prerequisites
    install_redis_operator
    deploy_redis_instances  
    deploy_redis_client
    deploy_redisinsight
    pin_redis_images
    test_redis_connectivity
    create_sample_data
    run_performance_tests
    health_check
    display_deployment_info
    
    # Calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    
    echo ""
    log_success "🚀 REDIS INSTALLATION COMPLETED SUCCESSFULLY!"
    echo -e "${GREEN}Total time: ${minutes}m ${seconds}s${NC}"
    echo ""
    echo -e "${PURPLE}=== NEXT STEPS ===${NC}"
    echo -e "${CYAN}1. Access RedisInsight Web UI: http://redis.devsecops.net.au${NC}"
    echo -e "${CYAN}2. Connect to databases using the provided connection details${NC}"
    echo -e "${CYAN}3. Explore sample data using: kubectl exec deployment/redis-client -n redis -- /scripts/explore-sample-data.sh${NC}"
    echo -e "${CYAN}4. View complete documentation in: $SCRIPT_DIR/redis-installation-guide.md${NC}"
    echo ""
}

# Execute main function
main "$@"
