# RedisInsight Web Client Access Guide

## ✅ **RedisInsight Deployed Successfully!**

RedisInsight is Redis's official web-based GUI client that provides a comprehensive interface for Redis management, similar to Adminer for databases.

---

## 🔗 **Access RedisInsight**

### **Web Interface URLs:**
- **Primary URL**: `http://redis.devsecops.net.au`
- **Service IP**: `10.109.246.62:80` (internal)
- **Container Port**: `5540`

### **Access Methods:**

#### **1. Via Ingress (Recommended):**
```bash
# Open in browser
open http://redis.devsecops.net.au
```

#### **2. Via Port Forward:**
```bash
# Forward port to local machine
kubectl port-forward deployment/redisinsight -n redis 8080:5540

# Then access via browser
open http://localhost:8080
```

#### **3. Via NodePort (if needed):**
```bash
# Create NodePort service for external access
kubectl expose deployment redisinsight --type=NodePort --port=5540 -n redis --name=redisinsight-nodeport
```

---

## 🔧 **Redis Connection Configuration**

Once RedisInsight loads, you'll need to add your Redis instances:

### **Redis Standalone Connection:**
```
Host: redis-standalone.redis.svc.cluster.local
Port: 6379
Name: Redis Standalone Lab
Alias: standalone
Username: (leave empty)
Password: (leave empty)
```

### **Redis Cluster Connection:**
```
Host: redis-cluster-leader.redis.svc.cluster.local
Port: 6379
Name: Redis Cluster Lab
Alias: cluster
Username: (leave empty)  
Password: (leave empty)
Cluster: ✅ Enable cluster mode
```

### **Alternative Internal IPs:**
If DNS resolution fails, use direct IPs:
- **Standalone**: `10.110.141.214:6379`
- **Cluster**: `10.97.207.200:6379`

---

## 🚀 **Using RedisInsight Features**

### **Key Features Available:**
1. **Browser** - Visual data browser with rich formatters
2. **Workbench** - Advanced CLI with command history
3. **Analysis** - Memory usage analysis and optimization tips
4. **Profiler** - Real-time command monitoring
5. **SlowLog** - Slow query analysis
6. **Pub/Sub** - Real-time message monitoring
7. **Streams** - Redis Streams visualization
8. **Cluster Management** - Cluster node status and slot distribution

### **Getting Started:**
1. **Add Database** - Click "Add Redis Database"
2. **Configure Connection** - Use the connection details above
3. **Test Connection** - RedisInsight will ping Redis to verify
4. **Explore Data** - Browse keys, view data structures
5. **Run Commands** - Use the integrated CLI

---

## 🧪 **Test Data Available**

Your Redis instances already have test data from our earlier testing:

### **In Redis Standalone:**
```bash
# Keys available for exploration:
test:key           # String: "Hello Redis Standalone!"
test:list          # List: ["item3", "item2", "item1"]
test:hash          # Hash: {field1: "value1", field2: "value2"}
test:counter       # String: "11" (counter)
perf:key:*         # Performance test keys (1000 items)
```

### **In Redis Cluster:**
```bash
# Keys available for exploration:
cluster:key        # String: "Hello Redis Cluster!"
cluster:perf:*     # Performance test keys (distributed across nodes)
```

---

## 🔧 **Troubleshooting**

### **If RedisInsight doesn't load:**

#### **1. Check Pod Status:**
```bash
kubectl get pods -n redis -l app=redisinsight
kubectl logs deployment/redisinsight -n redis
```

#### **2. Verify Service:**
```bash
kubectl get svc redisinsight-service -n redis
kubectl describe svc redisinsight-service -n redis
```

#### **3. Test Internal Connectivity:**
```bash
# From Redis client pod
kubectl exec deployment/redis-client -n redis -- wget -q --spider http://redisinsight-service:80/healthcheck
```

#### **4. Alternative Access:**
```bash
# Direct pod access
kubectl port-forward deployment/redisinsight -n redis 8080:5540

# Then access http://localhost:8080
```

### **If Redis Connection Fails:**

#### **1. Verify Redis is Running:**
```bash
kubectl get pods -n redis
kubectl exec deployment/redis-client -n redis -- redis-cli -h redis-standalone ping
```

#### **2. Use IP Addresses:**
If DNS resolution fails in RedisInsight, use the direct service IPs:
- Standalone: `10.110.141.214`
- Cluster: `10.97.207.200`

#### **3. Check Service Endpoints:**
```bash
kubectl get endpoints -n redis
```

---

## 🎯 **RedisInsight vs Command Line**

### **What RedisInsight Provides Over CLI:**

1. **Visual Data Browser**
   - Tree view of keys with namespaces
   - Syntax highlighting for JSON, XML, etc.
   - Hex, ASCII, and JSON formatters
   - Bulk operations on multiple keys

2. **Memory Analysis**
   - Memory usage by data type
   - Key size analysis
   - Memory optimization recommendations
   - Expiration analysis

3. **Real-time Monitoring**
   - Live command profiling
   - Slow query log visualization
   - Client connections monitoring
   - Cluster health dashboard

4. **Enhanced CLI (Workbench)**
   - Command auto-completion
   - Syntax highlighting
   - Command history
   - Multi-line command support

5. **Cluster Visualization**
   - Node topology view
   - Slot distribution visualization
   - Master-replica relationships
   - Failover status monitoring

---

## 📊 **Comparing with Other Tools**

### **RedisInsight vs Redis CLI:**
| Feature | Redis CLI | RedisInsight |
|---------|-----------|--------------|
| Data Browsing | Text only | Visual tree view |
| Memory Analysis | Manual commands | Built-in analyzer |
| Monitoring | Manual INFO | Real-time dashboard |
| Cluster Management | Command-based | Visual topology |
| User Experience | Terminal | Web GUI |

### **RedisInsight vs Other Redis GUIs:**
- **RedisInsight**: Official tool, most comprehensive
- **Redis Desktop Manager**: Desktop app, commercial
- **RedisCommander**: Simple web interface
- **FastoRedis**: Multi-DB tool, commercial features

---

## 🎓 **Quick Start Workflow**

### **Step 1: Access RedisInsight**
```bash
# Open browser to
http://redis.devsecops.net.au
```

### **Step 2: Add Databases**
1. Click **"Add Redis Database"**
2. For Standalone:
   - Host: `redis-standalone.redis.svc.cluster.local`
   - Port: `6379`
   - Name: `Redis Standalone`
3. For Cluster:
   - Host: `redis-cluster-leader.redis.svc.cluster.local` 
   - Port: `6379`
   - Name: `Redis Cluster`
   - ✅ **Enable cluster mode**

### **Step 3: Explore Features**
1. **Browser Tab**: View existing test data
2. **Workbench Tab**: Run Redis commands
3. **Analysis Tab**: Check memory usage
4. **Profiler Tab**: Monitor live commands

### **Step 4: Create New Data**
```bash
# In Workbench, try these commands:
SET myapp:user:1 '{"name":"John","age":30}'
LPUSH myapp:logs "Application started"
HSET myapp:config timeout 300 retries 3
INCR myapp:counters:visits
```

---

## 🔮 **Advanced Features**

### **Memory Analysis:**
1. Go to **Analysis** tab
2. Click **"New Analysis"**
3. View memory usage by:
   - Key patterns
   - Data types
   - Expiration status
   - Size distribution

### **Command Profiling:**
1. Go to **Profiler** tab  
2. Click **"Start Profiler"**
3. Run commands from your app
4. Analyze command patterns and performance

### **Cluster Monitoring:**
1. Connect to cluster database
2. Go to **Cluster** view
3. Monitor:
   - Node health status
   - Slot distribution
   - Replication lag
   - Failover events

---

## 📈 **Production Usage Tips**

### **Security Considerations:**
- RedisInsight stores connection info locally
- No authentication configured (development setup)
- For production: Enable Redis AUTH and TLS

### **Performance Monitoring:**
- Use built-in profiler to identify slow commands
- Monitor memory usage trends
- Set up alerts for key metrics
- Regular cluster health checks

### **Data Management:**
- Use TTL analysis to manage expired keys
- Implement proper key naming conventions
- Regular memory analysis for optimization
- Backup critical data patterns

---

**RedisInsight provides a powerful web interface for Redis management, equivalent to Adminer for databases!** 🚀

*Access URL: http://redis.devsecops.net.au*  
*Installation completed: October 7, 2025*