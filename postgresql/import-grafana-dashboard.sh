#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KUBECONFIG_PATH_DEFAULT="/private/tmp/kubernetes-lab/admin.conf"
export KUBECONFIG="${KUBECONFIG:-$KUBECONFIG_PATH_DEFAULT}"

NAMESPACE="${GRAFANA_NAMESPACE:-monitoring}"
CM_NAME="${GRAFANA_CM_NAME:-grafana-dashboard-cnpg}"
FILE_PATH="$SCRIPT_DIR/cloudnative-pg-dashboard.json"

if [ ! -f "$FILE_PATH" ]; then
  echo "Dashboard JSON not found at $FILE_PATH" >&2
  exit 1
fi

echo "Creating/updating ConfigMap $CM_NAME in namespace $NAMESPACE..."
kubectl create configmap "$CM_NAME" \
  -n "$NAMESPACE" \
  --from-file=cloudnative-pg-dashboard.json="$FILE_PATH" \
  -o yaml --dry-run=client | kubectl apply -f -

kubectl label configmap "$CM_NAME" -n "$NAMESPACE" grafana_dashboard=1 --overwrite

echo "Done. Grafana sidecar should auto-import the dashboard shortly."

