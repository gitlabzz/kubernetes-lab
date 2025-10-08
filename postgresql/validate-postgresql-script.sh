#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/postgresql-automated-install.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}=== VALIDATING POSTGRES AUTOMATION SCRIPT ===${NC}\n"

if [ ! -f "$TARGET" ]; then echo -e "${RED}❌ Script file not found${NC}"; exit 1; fi
echo -e "${GREEN}✅ Script file found${NC}\n"

TESTED=(
  "repo add cloudnative-pg https://cloudnative-pg.github.io/charts"
  "repo update"
  "upgrade .* cloudnative-pg/cloudnative-pg"
  "namespace.*POSTGRES_NAMESPACE"
  "apply -f.*postgres-cluster.yaml"
  "apply -f.*postgres-client.yaml"
  "apply -f.*pgadmin-deployment.yaml"
  "apply -f.*adminer-postgres.yaml"
  "deployment/postgres-client"
  "psql -c \"SELECT current_database\(\)"
  "/scripts/create-test-data.sh"
  "/scripts/insert-test-data.sh"
  "/scripts/query-test-data.sh"
  "CONFIGURING TLS FOR WEB UIS"
  "FINAL HEALTH CHECK"
)

found=0; total=${#TESTED[@]}
echo -e "${YELLOW}Checking for tested commands in script:${NC}"
for p in "${TESTED[@]}"; do
  if grep -q "$p" "$TARGET"; then echo -e "  ${GREEN}✅${NC} Found: $p"; ((found++)); else echo -e "  ${RED}❌${NC} Missing: $p"; fi
done

echo -e "\n${YELLOW}Validation Results:${NC}\n  Found: $found/$total"
if [ $found -eq $total ]; then
  echo -e "${GREEN}🎉 ALL TESTED COMMANDS PRESENT${NC}"
  exit 0
else
  echo -e "${RED}⚠️  Some tested commands missing${NC}"
  exit 1
fi
