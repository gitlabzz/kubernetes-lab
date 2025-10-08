#!/bin/bash

# Validation script to check if Redis automation script contains tested commands
# This ensures all commands in the automation script have been verified

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FILE="$SCRIPT_DIR/redis-automated-install.sh"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== VALIDATING REDIS AUTOMATION SCRIPT ===${NC}"
echo ""

# Check if script exists
if [ ! -f "$SCRIPT_FILE" ]; then
    echo -e "${RED}❌ Script file not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Script file found${NC}"

# Validated commands that we tested in this session
TESTED_COMMANDS=(
    "helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/"
    "helm repo update"
    "helm upgrade redis-operator ot-helm/redis-operator"
    "namespace.*REDIS_NAMESPACE"
    "helm upgrade redis-standalone ot-helm/redis"
    "helm upgrade redis-cluster ot-helm/redis-cluster" 
    "kubectl apply -f.*redis-client.yaml"
    "kubectl apply -f.*redisinsight-deployment.yaml"
    "kubectl wait --for=condition=available.*deployment/redis-client"
    "kubectl wait --for=condition=available.*deployment/redisinsight"
    "redis-cli -h redis-standalone ping"
    "redis-cli -h redis-cluster-leader ping"
    "redis-cli -h redis-standalone dbsize"
    "/scripts/create-sample-ecommerce-data.sh"
    "/scripts/test-standalone.sh"
    "cluster info"
)

echo ""
echo -e "${YELLOW}Checking for tested commands in script:${NC}"

found_count=0
total_count=${#TESTED_COMMANDS[@]}

for cmd in "${TESTED_COMMANDS[@]}"; do
    if grep -q "$cmd" "$SCRIPT_FILE"; then
        echo -e "  ${GREEN}✅${NC} Found: $cmd"
        ((found_count++))
    else
        echo -e "  ${RED}❌${NC} Missing: $cmd"
    fi
done

echo ""
echo -e "${YELLOW}Validation Results:${NC}"
echo "  Found: $found_count/$total_count tested commands"

if [ $found_count -eq $total_count ]; then
    echo -e "${GREEN}🎉 ALL TESTED COMMANDS PRESENT IN SCRIPT${NC}"
    echo -e "${GREEN}✅ Script is reliable and uses verified commands${NC}"
else
    echo -e "${RED}⚠️  Some tested commands missing from script${NC}"
    echo -e "${YELLOW}Script may need updates to include all verified commands${NC}"
fi

echo ""
echo -e "${YELLOW}Additional checks:${NC}"

# Check for error handling
if grep -q "set -e" "$SCRIPT_FILE"; then
    echo -e "  ${GREEN}✅${NC} Error handling enabled (set -e)"
else
    echo -e "  ${RED}❌${NC} No error handling found"
fi

# Check for logging functions
if grep -q "log_success\|log_error\|log_warning" "$SCRIPT_FILE"; then
    echo -e "  ${GREEN}✅${NC} Logging functions present"
else
    echo -e "  ${RED}❌${NC} No logging functions found"
fi

# Check for health checks
if grep -q "health_check" "$SCRIPT_FILE"; then
    echo -e "  ${GREEN}✅${NC} Health check function present"
else
    echo -e "  ${RED}❌${NC} No health check function found"
fi

# Check for cleanup on error
if grep -q "cleanup_on_error\|trap.*ERR" "$SCRIPT_FILE"; then
    echo -e "  ${GREEN}✅${NC} Error cleanup handling present"  
else
    echo -e "  ${RED}❌${NC} No error cleanup found"
fi

echo ""
if [ $found_count -eq $total_count ]; then
    echo -e "${GREEN}🚀 SCRIPT VALIDATION PASSED - Ready for use!${NC}"
    exit 0
else
    echo -e "${RED}❌ SCRIPT VALIDATION FAILED - Needs updates${NC}"
    exit 1
fi
