# Create the kubemaster VM

multipass launch --disk 5G --memory 3G --cpus 2 --name kubemaster --network name=en0,mode=manual,mac="52:54:00:4b:ab:cd" jammy

multipass exec -n kubemaster -- sudo bash -c 'cat << EOF > /etc/netplan/10-custom.yaml
network:
version: 2
ethernets:
extra0:
dhcp4: no
match:
macaddress: "52:54:00:4b:ab:cd"
addresses: [192.168.68.101/24]
EOF'

multipass exec -n kubemaster -- sudo netplan apply


# Create the kubeworker01 VM

multipass launch --disk 5G --memory 3G --cpus 2 --name kubeworker01 --network name=en0,mode=manual,mac="52:54:00:4b:ba:dc" jammy

multipass exec -n kubeworker01 -- sudo bash -c 'cat << EOF > /etc/netplan/10-custom.yaml
network:
version: 2
ethernets:
extra0:
dhcp4: no
match:
macaddress: "52:54:00:4b:ba:dc"
addresses: [192.168.68.102/24]
EOF'

multipass exec -n kubeworker01 -- sudo netplan apply

# Create the kubeworker02 VM

multipass launch --disk 5G --memory 3G --cpus 2 --name kubeworker02 --network name=en0,mode=manual,mac="52:54:00:4b:cd:ab" jammy

multipass exec -n kubeworker02 -- sudo bash -c 'cat << EOF > /etc/netplan/10-custom.yaml
network:
version: 2
ethernets:
extra0:
dhcp4: no
match:
macaddress: "52:54:00:4b:cd:ab"
addresses: [192.168.68.103/24]
EOF'

multipass exec -n kubeworker02 -- sudo netplan apply

# Entry in hosts file of all VMs
192.168.68.101 kubemaster
192.168.68.102 kubeworker01
192.168.68.103 kubeworker02

# Forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

lsmod | grep br_netfilter
lsmod | grep overlay

Verify that the net.bridge.bridge-nf-call-iptables, net.bridge.bridge-nf-call-ip6tables, and net.ipv4.ip_forward system variables are set to 1 in your sysctl config by running the following command:

sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Install containerd, runc, CNI plugins on all 3 VMs
curl -LO https://github.com/containerd/containerd/releases/download/v1.7.9/containerd-1.7.9-linux-arm64.tar.gz

sudo tar Cxzvf /usr/local containerd-1.7.9-linux-arm64.tar.gz

curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

sudo mkdir -p /usr/local/lib/systemd/system/
sudo mv containerd.service /usr/local/lib/systemd/system/

#systemctl daemon-reload
#systemctl enable --now containerd

sudo mkdir -p /etc/containerd/
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

#Check that containerd service is up and running
systemctl status containerd

curl -LO https://github.com/opencontainers/runc/releases/download/v1.1.10/runc.arm64

sudo install -m 755 runc.arm64 /usr/local/sbin/runc

#cni plugin
curl -LO https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-arm64-v1.3.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-arm64-v1.3.0.tgz

# Install kubeadm, kubelet and kubectl on all VMs
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

#Configure crictl to work with containerd
sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock

# Initializing your control-plane node
On the controlplane node
dig +short kubemaster | grep -v 127
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.68.101

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#Verify the cluster is contactable
kubectl get pods -n kube-system

#Save the join command
kubeadm join 192.168.68.101:6443 --token zkxg31.x8kju0a5zlk55cph \
--discovery-token-ca-cert-hash sha256:43c947a4e908e44e7f760dbd182d32aab553d473631102be79acb06c09921a03

# Install a Pod network add-on (Weave)
kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml"

Check that all pods are up and running after few minutes
kubectl get pod -n kube-system

# Join the worker nodes
Paste the join command on every worker node

After few seconds check that all nodes have joined the cluster and are in a Ready state.
kubectl get node -o wide