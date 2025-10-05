# Upgrade Cilium with Tetragon enabled
helm upgrade cilium cilium/cilium --version 1.14.0 --namespace kube-system --reuse-values --set tetragon.enabled=true