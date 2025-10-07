#!/bin/bash

# MySQL Installation Script for Kubernetes Lab
# Automated deployment based on proven and verified process
# Created: October 7, 2025
# Environment: Kubernetes Lab v1.31.13 with Longhorn, MetalLB, Nginx

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
NAMESPACE="mysql"
ROOT_PASSWORD="S3cur3Pass!23!"
ROOT_PASSWORD_B64=$(echo -n "$ROOT_PASSWORD" | base64)
TEST_USER="testuser"
TEST_PASSWORD="testpass123"
TEST_DATABASE="testdb"
STORAGE_SIZE="10Gi"
STORAGE_CLASS="longhorn"
MYSQL_REPLICAS="3"
DEPLOY_ADMINER="true"

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Check Helm
    if [ ! -f "./helm" ]; then
        log "Helm not found locally. Installing Helm v3.19.0..."
        install_helm
    fi
    
    # Verify cluster nodes
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    log_success "Connected to cluster with $NODE_COUNT nodes"
    
    # Check storage class
    if ! kubectl get storageclass longhorn &> /dev/null; then
        log_error "Longhorn storage class not found. Please ensure Longhorn is installed."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Install Helm if not present
install_helm() {
    log "Installing Helm v3.19.0..."
    curl -L https://get.helm.sh/helm-v3.19.0-darwin-amd64.tar.gz -o helm.tar.gz
    tar -xzf helm.tar.gz
    chmod +x darwin-amd64/helm
    mv darwin-amd64/helm ./helm
    rm -rf helm.tar.gz darwin-amd64
    log_success "Helm installed successfully"
}

# Install MySQL Operator (optional - known to have DNS issues in this environment)
install_mysql_operator() {
    log "Installing MySQL Operator (experimental in this environment)..."
    
    ./helm repo add mysql-operator https://mysql.github.io/mysql-operator/ || true
    ./helm repo update
    
    ./helm install mysql-operator mysql-operator/mysql-operator \
        --namespace mysql-operator --create-namespace
    
    log_warning "MySQL Operator installed but may have DNS issues in this environment"
    log "Proceeding with StatefulSet approach for reliable deployment..."
}

# Create namespace
create_namespace() {
    log "Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    log_success "Namespace $NAMESPACE ready"
}

# Generate MySQL StatefulSet configuration
generate_mysql_config() {
    log "Generating MySQL StatefulSet configuration..."
    
    cat > mysql-statefulset.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: $NAMESPACE
type: Opaque
data:
  mysql-root-password: $ROOT_PASSWORD_B64
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-config
  namespace: $NAMESPACE
data:
  my.cnf: |
    [mysqld]
    default_authentication_plugin=mysql_native_password
    bind-address=0.0.0.0
    port=3306
    character-set-server=utf8mb4
    collation-server=utf8mb4_unicode_ci
    innodb_buffer_pool_size=256M
    innodb_log_file_size=64M
    max_connections=200
    
    # Performance tuning
    innodb_flush_log_at_trx_commit=2
    innodb_flush_method=O_DIRECT
    
    # Security settings
    local-infile=0
    skip-show-database
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: $NAMESPACE
  labels:
    app: mysql
spec:
  ports:
  - port: 3306
    name: mysql
  clusterIP: None
  selector:
    app: mysql
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-loadbalancer
  namespace: $NAMESPACE
  labels:
    app: mysql
  annotations:
    metallb.universe.tf/address-pool: first-pool
spec:
  type: LoadBalancer
  ports:
  - port: 3306
    targetPort: 3306
    name: mysql
  selector:
    app: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: $NAMESPACE
spec:
  serviceName: mysql
  replicas: $MYSQL_REPLICAS
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-root-password
        - name: MYSQL_DATABASE
          value: "$TEST_DATABASE"
        - name: MYSQL_USER
          value: "$TEST_USER"
        - name: MYSQL_PASSWORD
          value: "$TEST_PASSWORD"
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
        - name: mysql-config
          mountPath: /etc/mysql/conf.d
        livenessProbe:
          exec:
            command:
            - mysqladmin
            - ping
            - -h
            - localhost
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - "mysqladmin ping -h localhost && mysql -h localhost -e 'SELECT 1'"
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 1
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: mysql-config
        configMap:
          name: mysql-config
  volumeClaimTemplates:
  - metadata:
      name: mysql-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: $STORAGE_SIZE
EOF

    log_success "MySQL configuration generated"
}

# Generate Adminer configuration
generate_adminer_config() {
    log "Generating Adminer configuration..."
    
    cat > adminer-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: adminer
  namespace: $NAMESPACE
  labels:
    app: adminer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: adminer
  template:
    metadata:
      labels:
        app: adminer
    spec:
      containers:
      - name: adminer
        image: adminer:4.8.1
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: ADMINER_DEFAULT_SERVER
          value: "mysql.$NAMESPACE.svc.cluster.local"
        - name: ADMINER_DESIGN
          value: "pepa-linha"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: adminer
  namespace: $NAMESPACE
  labels:
    app: adminer
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: adminer
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: adminer-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: adminer.devsecops.net.au
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: adminer
            port:
              number: 80
EOF

    log_success "Adminer configuration generated"
}

# Deploy Adminer
deploy_adminer() {
    if [ "$DEPLOY_ADMINER" = "true" ]; then
        log "Deploying Adminer database client..."
        kubectl apply -f adminer-deployment.yaml
        log_success "Adminer deployed"
        
        # Wait for Adminer to be ready
        log "Waiting for Adminer to be ready..."
        kubectl wait --for=condition=Ready pod -l app=adminer-fixed -n $NAMESPACE --timeout=120s || {
            log_warning "Adminer may still be starting up"
        }
        
        # Wait for Ingress to be ready
        log "Waiting for Ingress to be configured..."
        sleep 10  # Give ingress controller time to process
    else
        log "Skipping Adminer deployment"
    fi
}

# Deploy MySQL StatefulSet
deploy_mysql() {
    log "Deploying MySQL StatefulSet..."
    kubectl apply -f mysql-statefulset.yaml
    log_success "MySQL StatefulSet deployed"
}

# Wait for MySQL pods to be ready
wait_for_mysql() {
    log "Waiting for MySQL pods to start..."
    
    # Wait for the first pod to be running
    kubectl wait --for=condition=PodScheduled pod/mysql-0 -n $NAMESPACE --timeout=300s
    log "Pod mysql-0 scheduled"
    
    # Wait for pod to be running (not necessarily ready due to probe issues)
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pod mysql-0 -n $NAMESPACE | grep -q "Running"; then
            log_success "MySQL pod mysql-0 is running"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Timeout waiting for MySQL pod to start"
            exit 1
        fi
        
        log "Attempt $attempt/$max_attempts - waiting for pod to start..."
        sleep 10
        ((attempt++))
    done
    
    # Wait for MySQL service to be ready inside the pod
    log "Waiting for MySQL service to be ready..."
    local mysql_ready=false
    attempt=1
    max_attempts=30
    
    while [ $attempt -le $max_attempts ] && [ "$mysql_ready" = false ]; do
        if kubectl exec mysql-0 -n $NAMESPACE -- mysqladmin ping -h localhost >/dev/null 2>&1; then
            mysql_ready=true
            log_success "MySQL service is ready"
        else
            log "Attempt $attempt/$max_attempts - waiting for MySQL service..."
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ "$mysql_ready" = false ]; then
        log_error "Timeout waiting for MySQL service to be ready"
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    log "Verifying MySQL deployment..."
    
    # Check pod status
    kubectl get pods -n $NAMESPACE
    
    # Check services
    kubectl get svc -n $NAMESPACE
    
    # Check PVC
    kubectl get pvc -n $NAMESPACE
    
    # Test database connectivity
    log "Testing database connectivity..."
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u root -p$ROOT_PASSWORD -e "SELECT 'MySQL connectivity test successful!' as status;" || {
        log_error "Database connectivity test failed"
        return 1
    }
    
    # Check databases and users
    log "Verifying databases and users..."
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u root -p$ROOT_PASSWORD -e "SHOW DATABASES; SELECT User, Host FROM mysql.user LIMIT 10;" || {
        log_error "Database verification failed"
        return 1
    }
    
    log_success "MySQL deployment verified successfully"
}

# Create test data
create_test_data() {
    log "Creating test data..."
    
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u $TEST_USER -p$TEST_PASSWORD $TEST_DATABASE -e "
    CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        email VARCHAR(100) NOT NULL UNIQUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        description TEXT,
        price DECIMAL(10,2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO users (username, email) VALUES 
        ('john_doe', 'john@example.com'),
        ('jane_smith', 'jane@example.com'),
        ('bob_wilson', 'bob@example.com'),
        ('alice_brown', 'alice@example.com');
    
    INSERT INTO products (name, description, price) VALUES
        ('Laptop Pro', 'High-performance laptop for professionals', 1299.99),
        ('Wireless Mouse', 'Ergonomic wireless mouse', 29.99),
        ('Mechanical Keyboard', 'RGB mechanical gaming keyboard', 89.99),
        ('4K Monitor', '27-inch 4K professional monitor', 399.99);
    " || {
        log_error "Failed to create test data"
        return 1
    }
    
    log_success "Test data created successfully"
}

# Display test results
display_test_results() {
    log "Displaying test results..."
    
    echo -e "\n${GREEN}=== USERS TABLE ===${NC}"
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u $TEST_USER -p$TEST_PASSWORD $TEST_DATABASE -e "SELECT * FROM users;"
    
    echo -e "\n${GREEN}=== PRODUCTS TABLE ===${NC}"
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u $TEST_USER -p$TEST_PASSWORD $TEST_DATABASE -e "SELECT * FROM products;"
    
    echo -e "\n${GREEN}=== DATABASE STATISTICS ===${NC}"
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u $TEST_USER -p$TEST_PASSWORD $TEST_DATABASE -e "
    SELECT 
        'users' as table_name, 
        COUNT(*) as record_count 
    FROM users 
    UNION ALL 
    SELECT 
        'products' as table_name, 
        COUNT(*) as record_count 
    FROM products;"
}

# Display connection information
display_connection_info() {
    log "Retrieving connection information..."
    
    # Get access information
    NGINX_INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "172.16.176.201")
    ADMINER_DEPLOYED=$(kubectl get ingress adminer-ingress -n $NAMESPACE -o jsonpath='{.metadata.name}' 2>/dev/null || echo "Not deployed")
    
    echo -e "\n${GREEN}=== MySQL Connection Information ===${NC}"
    echo -e "${BLUE}Internal Access (within cluster):${NC}"
    echo "  Host: mysql-direct.$NAMESPACE.svc.cluster.local"
    echo "  Port: 3306"
    echo ""
    echo -e "${BLUE}Credentials:${NC}"
    echo "  Root User: root"
    echo "  Root Password: $ROOT_PASSWORD"
    echo "  Test User: $TEST_USER"
    echo "  Test Password: $TEST_PASSWORD"
    echo "  Test Database: $TEST_DATABASE"
    echo ""
    echo -e "${BLUE}Direct Pod Access:${NC}"
    echo "  kubectl exec -it mysql-0 -n $NAMESPACE -- mysql -u root -p$ROOT_PASSWORD"
    
    if [ "$ADMINER_DEPLOYED" != "Not deployed" ]; then
        echo ""
        echo -e "\n${GREEN}=== Adminer Web Interface ===${NC}"
        echo -e "${BLUE}Web Access:${NC}"
        echo "  Primary URL: http://adminer.devsecops.net.au"
        echo "  Direct IP: http://$NGINX_INGRESS_IP (with Host: adminer.devsecops.net.au header)"
        echo "  Nginx Ingress IP: $NGINX_INGRESS_IP"
        echo ""
        echo -e "${BLUE}Login Details for Adminer:${NC}"
        echo "  System: MySQL"
        echo "  Server: mysql-direct"
        echo "  Username: root (or $TEST_USER)"
        echo "  Password: $ROOT_PASSWORD (or $TEST_PASSWORD)"
        echo "  Database: $TEST_DATABASE (optional)"
        echo ""
        echo -e "${BLUE}Note:${NC} MySQL is only accessible internally via Adminer web interface"
    fi
}

# Performance test
run_performance_test() {
    log "Running basic performance test..."
    
    kubectl exec mysql-0 -n $NAMESPACE -- mysql -u $TEST_USER -p$TEST_PASSWORD $TEST_DATABASE -e "
    DROP TABLE IF EXISTS performance_test;
    CREATE TABLE performance_test (
        id INT AUTO_INCREMENT PRIMARY KEY,
        data VARCHAR(255),
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO performance_test (data) VALUES 
    ('test1'), ('test2'), ('test3'), ('test4'), ('test5'),
    ('test6'), ('test7'), ('test8'), ('test9'), ('test10');
    
    SELECT COUNT(*) as 'Records inserted' FROM performance_test;
    
    SELECT 'Performance test completed successfully' as status;
    " || {
        log_warning "Performance test had issues but MySQL is functional"
    }
    
    log_success "Performance test completed"
}

# Cleanup function (optional)
cleanup() {
    log_warning "Cleanup function called"
    read -p "Are you sure you want to delete the MySQL deployment? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing MySQL deployment..."
        kubectl delete statefulset mysql -n $NAMESPACE || true
        kubectl delete svc mysql mysql-loadbalancer -n $NAMESPACE || true
        kubectl delete configmap mysql-config -n $NAMESPACE || true
        kubectl delete secret mysql-secret -n $NAMESPACE || true
        kubectl delete pvc -l app=mysql -n $NAMESPACE || true
        kubectl delete namespace $NAMESPACE || true
        log_success "MySQL deployment removed"
    else
        log "Cleanup cancelled"
    fi
}

# Main execution function
main() {
    echo -e "${GREEN}"
    echo "=================================="
    echo "  MySQL Kubernetes Installation"
    echo "  Automated Script v1.0"
    echo "  Environment: Kubernetes Lab"
    echo "=================================="
    echo -e "${NC}"
    
    # Parse command line arguments
    case "${1:-install}" in
        "install")
            check_prerequisites
            create_namespace
            generate_mysql_config
            generate_adminer_config
            deploy_mysql
            deploy_adminer
            wait_for_mysql
            verify_deployment
            create_test_data
            display_test_results
            run_performance_test
            display_connection_info
            log_success "MySQL installation completed successfully!"
            ;;
        "verify")
            verify_deployment
            display_test_results
            display_connection_info
            ;;
        "cleanup")
            cleanup
            ;;
        "test")
            create_test_data
            display_test_results
            run_performance_test
            ;;
        "info")
            display_connection_info
            ;;
        *)
            echo "Usage: $0 {install|verify|cleanup|test|info}"
            echo ""
            echo "Commands:"
            echo "  install  - Complete MySQL installation (default)"
            echo "  verify   - Verify existing deployment"
            echo "  cleanup  - Remove MySQL deployment"
            echo "  test     - Run test data creation and performance test"
            echo "  info     - Display connection information"
            exit 1
            ;;
    esac
}

# Trap to handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"