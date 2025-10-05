#!/bin/bash
echo "from https://balaskas.gr/blog/2022/08/31/creating-a-kubernetes-cluster-with-kubeadm-on-ubuntu-2204-lts/"
echo "notes:"
echo "https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network"
echo "https://kubernetes.io/docs/concepts/cluster-administration/networking/#how-to-implement-the-kubernetes-networking-model"
echo "https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/"

echo "Tested to work with Ubuntu 22.04"

sudo apt update -y
sudo apt install iputils-ping -y
sudo apt install net-tools -y
sudo apt install vim -y
sudo apt install apt-transport-https curl -y
sudo apt install ufw -y

#sudo sh -c 'hostname=$(hostname) && ip=$(hostname -I | cut -d" " -f1) && echo "$ip $hostname" >> /etc/hosts'

echo "Disable firewall"
sudo ufw disable
echo "Disable swap"
sudo swapoff -a
sleep 1
echo "Removing swap entry from fstab"
sudo sed -i '/swapfile/d' /etc/fstab

sleep 1
echo "installing gnupg2, apt-transport-https, ca-certificates, curl, software-properties-common"
sudo apt-get update && sudo apt-get install -y gnupg gnupg2 apt-transport-https ca-certificates curl software-properties-common lsb-release
sleep 5

sudo tee /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF
sleep 1
sudo modprobe overlay
sudo modprobe br_netfilter
sleep 1
sudo lsmod | grep netfilter
sleep 1

sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sleep 1
sudo sysctl --system

sleep 1
echo "\$nrconf{restart} = 'a';" | sudo tee -a /etc/needrestart/needrestart.conf

sleep 1
curl -sL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-keyring.gpg

sleep 1
sudo apt-add-repository -y "deb https://download.docker.com/linux/ubuntu jammy stable"

sleep 5
sudo apt -y install containerd.io

sleep 1
containerd config default |
  sed 's/SystemdCgroup = false/SystemdCgroup = true/' |
  sudo tee /etc/containerd/config.toml

sleep 1
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd

# Install kubeadm, kubelet and kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


sleep 2
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl enable kubelet

sleep 2
kubeadm version
kubectl version --client

sleep 1
sudo kubeadm config images pull

sleep 5
#sudo kubeadm join 192.168.210.136:6443 --token iv8akm.5ontwiac6s1uuv30 --discovery-token-ca-cert-hash sha256:6f41fd6bc6b9b9c117ffdaae21a03680b5cb02d8c596371b15be2dea4333695b