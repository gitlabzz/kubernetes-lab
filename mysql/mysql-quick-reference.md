# MySQL Kubernetes Quick Reference

## Installation Commands

### Quick Install
```bash
./mysql-automated-install.sh install
```

### Verify Installation
```bash
./mysql-automated-install.sh verify
```

### Connection Info
```bash
./mysql-automated-install.sh info
```

## Manual Commands

### Connect to MySQL
```bash
# Inside cluster
kubectl exec -it mysql-0 -n mysql -- mysql -u root -pS3cur3Pass!23!

# Test user connection
kubectl exec -it mysql-0 -n mysql -- mysql -u testuser -ptestpass123 testdb
```

### Check Status
```bash
kubectl get pods,svc,pvc,ingress -n mysql
kubectl logs mysql-0 -n mysql
```

### Scale MySQL
```bash
kubectl scale statefulset mysql --replicas=3 -n mysql
```

## Connection Details

- **Adminer Web UI**: `http://adminer.devsecops.net.au` (via Ingress)
- **Nginx Ingress IP**: `172.16.176.201`
- **Internal MySQL**: `mysql-direct.mysql.svc.cluster.local:3306`
- **Root Password**: `S3cur3Pass!23!`
- **Test User**: `testuser` / `testpass123`
- **Test Database**: `testdb`

## Troubleshooting

### Pod Not Ready
```bash
kubectl describe pod mysql-0 -n mysql
kubectl logs mysql-0 -n mysql
```

### Storage Issues
```bash
kubectl get pvc -n mysql
kubectl describe pvc mysql-storage-mysql-0 -n mysql
```

### Network Issues
```bash
kubectl get svc,ingress -n mysql
kubectl describe ingress adminer-ingress -n mysql
```

## Sample Queries

### Create Sample Data
```sql
USE testdb;

CREATE TABLE employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(50),
    salary DECIMAL(10,2),
    hire_date DATE
);

INSERT INTO employees VALUES
(1, 'John Doe', 'Engineering', 75000.00, '2023-01-15'),
(2, 'Jane Smith', 'Marketing', 65000.00, '2023-02-20'),
(3, 'Bob Wilson', 'HR', 55000.00, '2023-03-10');

SELECT * FROM employees;
```

### Performance Test
```sql
CREATE TABLE large_test AS 
SELECT 
    ROW_NUMBER() OVER() as id,
    CONCAT('User_', ROW_NUMBER() OVER()) as username,
    RAND() * 100000 as score
FROM information_schema.columns a, information_schema.columns b 
LIMIT 10000;

SELECT COUNT(*) FROM large_test;
```