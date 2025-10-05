#!/bin/bash
set -e  # Exit on any error

echo "### Installing kube-bench ###"

# https://github.com/aquasecurity/kube-bench
# https://github.com/aquasecurity/kube-bench/blob/main/job-master.yaml
wget -O kube-bench-control-plane.yaml https://raw.githubusercontent.com/aquasecurity/kube-bench/refs/heads/main/job-master.yaml

wgrt -O kube-bench-node.yaml https://raw.githubusercontent.com/aquasecurity/kube-bench/refs/heads/main/job-node.yaml

kubectl apply -f kube-bench-control-plane.yaml

sleep 30

kubectl logs job/kube-bench-master > kube-bench-master-results.log

