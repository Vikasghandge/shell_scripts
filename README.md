# kubedum master node setup steps

```
All commands are for the Linux Master server.

# Enable IPv4 packet forwarding
-----------------------------------------------------------------------------------------
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
---------------------------------------------------------------------------------------------------

# Verify that net.ipv4.ip_forward is set to 1 with:

sysctl net.ipv4.ip_forward

-----------------------------------------------------------------------------------------------------
# disable swap off
sudo swapoff -a

-------------------------------------------------------------------------------------------------------
------
# setup docker's apt repository 
# Add Docker's official GPG key:
sudo apt-get update    # update the local packages
sudo apt-get install ca-certificates curl    #  Ensures your system trusts SSL certificates.
sudo install -m 0755 -d /etc/apt/keyrings    # create the dir if not exists and Sets permissions to allow root write access and others to read and execute.
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc    #  Set read permissions for the GPG key

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

## This command builds a proper APT source line:

## arch=$(dpkg --print-architecture): Detects your system architecture (e.g., amd64).

## $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"): Dynamically fetches your Ubuntu release codename (e.g., jammy).

## signed-by=/etc/apt/keyrings/docker.asc: Tells APT to use the GPG key we just downloaded.

## It writes this repository entry to /etc/apt/sources.list.d/docker.list.
-----------------------------------------------------------------------------------------------------------------------------------------
sudo apt-get install containerd.io   # installing the the containerd.io it is lightweight container runtime used in docker and k8s.
-----------------------------------------------------------------------------------------------------------------------------------------
containerd config default > /etc/containerd/config.toml  ## Allows you to customize containerd for advanced setups, including Kubernetes.
------------------------------------------------------------------------------------------------------------------------------------------
vi /etc/containerd/config.toml  # first of all you need to search find line // systemdCgroup  = false  // it is by default false you have to make it true.
---------------------------------------------------------------------------------------------------------------------------------------------------------
sudo systemctl restart containerd   # make sure once restart the containerd
-----------------------------------------------------------------------------------------------------------------------------------------------------
sudo systemctl status  containerd  ## check the status of containerd after running this it should be active (Running state)
-------------------------------------------------------------------------------------------------------------------------------------------------------
sudo apt-get update   # updating the local packages.
sudo apt-get install -y apt-transport-https ca-certificates curl gpg   # # apt-transport-https may be a dummy package; if so, you can skip that package
----------------------------------------------------------------------------------------------------------------------------------------------------------
#Download the public signing key for the Kubernetes package repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
-----------------------------------------------------------------------------------------------------------------------------------------------
# Adding  the appropriate Kubernetes apt repository  Please note that this repository have packages only for Kubernetes 1.33
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
sudo apt-get update  # update the local packages.
sudo apt-get install -y kubelet kubeadm kubectl   ## install the kubelet, kubedum, kubectl.
sudo apt-mark hold kubelet kubeadm kubectl
---------------------------------------------------------------------------------------------------------------------------------------
# kubeadm init --apiserver-advertise-address <private_ip of the (master) server> --pod-network-cidr 10.244.0.0/16 --cri-socket unix:///var/run/containerd/containerd.sock

Try To Use This Command.
```
kubeadm init
```

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
# above give command will generate something like this
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# this is recommended this is command use only for  normal user not for root user that's why switch normal user.
------------------------------------------------------------------------------------------------------------------------------	
# again kubedum init command will generate the toke like this give below
## // kubeadm join 172.31.7.248:6443 --token vqdvzh.6r6b6ov6quzz4sav \
--discovery-token-ca-cert-hash sha256:38070c64cb916dd7f52af0252dbbce1188b4eb7a27a95afac6343fcaef6121a  // 
## copy that token and the paste the token on your worker nodes.
----------------------------------------------------------------------------------------------------------------------------------
## on the master node run the command 
kubectl get nodes ## this command will show the active nodes it should show master node and worker nodes.
kubectl get pods -A ## this will show active pods in the all namespaces.
---------------------------------------------------------------------------------------------------------------------------------
# at the end apply this command this will start the nodes and also as well pods 
```

```
kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.29/net.yaml  # at the end run this command and then make sure change version according to ur cluster version.

```





```
