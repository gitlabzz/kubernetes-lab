#!/bin/bash

# Quick phpMyAdmin deployment script
# Better alternative to Adminer for full MySQL features

set -e

NAMESPACE="mysql"

echo "🚀 Deploying phpMyAdmin as MySQL client..."

# Create phpMyAdmin deployment
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phpmyadmin
  namespace: $NAMESPACE
  labels:
    app: phpmyadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phpmyadmin
  template:
    metadata:
      labels:
        app: phpmyadmin
    spec:
      containers:
      - name: phpmyadmin
        image: phpmyadmin:5.2.1
        ports:
        - containerPort: 80
          name: http
        env:
        - name: PMA_HOST
          value: "mysql.mysql.svc.cluster.local"
        - name: PMA_PORT
          value: "3306"
        - name: PMA_ARBITRARY
          value: "1"
        - name: PMA_ABSOLUTE_URI
          value: "http://phpmyadmin.devsecops.net.au/"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "400m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: phpmyadmin
  namespace: $NAMESPACE
  labels:
    app: phpmyadmin
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: phpmyadmin
---
apiVersion: v1
kind: Service
metadata:
  name: phpmyadmin-loadbalancer
  namespace: $NAMESPACE
  labels:
    app: phpmyadmin
  annotations:
    metallb.universe.tf/address-pool: first-pool
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: phpmyadmin
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - host: phpmyadmin.devsecops.net.au
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
EOF

echo "⏳ Waiting for phpMyAdmin to be ready..."
kubectl wait --for=condition=Ready pod -l app=phpmyadmin -n $NAMESPACE --timeout=120s

# Get external IP
EXTERNAL_IP=$(kubectl get svc phpmyadmin-loadbalancer -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo ""
echo "✅ phpMyAdmin deployed successfully!"
echo ""
echo "🌐 Access URLs:"
echo "   LoadBalancer: http://$EXTERNAL_IP"
echo "   Ingress: http://phpmyadmin.devsecops.net.au"
echo ""
echo "🔐 Login Credentials:"
echo "   Server: mysql.mysql.svc.cluster.local (or just 'mysql')"
echo "   Username: root"
echo "   Password: S3cur3Pass!23!"
echo "   Database: testdb (optional)"
echo ""
echo "📊 Features available:"
echo "   ✅ Full MySQL administration"
echo "   ✅ Visual query builder"
echo "   ✅ Import/Export tools"
echo "   ✅ User management"
echo "   ✅ Database design tools"