gabriele-riccio@gabriele-riccio-VirtualBox:~$ curl -sfL https://get.k3s.io | sh -
[sudo]: authenticate] Password:
[INFO]  Finding release for channel stable
[INFO]  Using v1.35.5+k3s1 as release
[INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.35.5%2Bk3s1/sha256sum-amd64.txt
[INFO]  Skipping binary downloaded, installed k3s matches hash
[INFO]  Skipping installation of SELinux RPM
[INFO]  Skipping /usr/local/bin/kubectl symlink to k3s, already exists
[INFO]  Skipping /usr/local/bin/crictl symlink to k3s, already exists
[INFO]  Skipping /usr/local/bin/ctr symlink to k3s, already exists
[INFO]  Creating killall script /usr/local/bin/k3s-killall.sh
[INFO]  Creating uninstall script /usr/local/bin/k3s-uninstall.sh
[INFO]  env: Creating environment file /etc/systemd/system/k3s.service.env
[INFO]  systemd: Creating service file /etc/systemd/system/k3s.service
[INFO]  systemd: Enabling k3s unit
Created symlink '/etc/systemd/system/multi-user.target.wants/k3s.service' → '/etc/systemd/system/k3s.service'.
No change detected so skipping service start
gabriele-riccio@gabriele-riccio-VirtualBox:~$ sudo systemctl status k3s
● k3s.service - Lightweight Kubernetes
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-06-15 14:14:01 CEST; 4min 8s ago
 Invocation: fa318c158b8b471f929b596fe7e6b981
       Docs: https://k3s.io
   Main PID: 1905 (k3s-server)
      Tasks: 87
     Memory: 775.7M (peak: 815.7M)
        CPU: 1min 3.443s
     CGroup: /system.slice/k3s.service
             ├─1905 "/usr/local/bin/k3s server"
             ├─2083 "containerd "
             ├─3171 /var/lib/rancher/k3s/data/921c0d40b0b3f73f2beae03ec1b23ec9aed3aa19fd651db6353e38f9636ddfe0/bin/containerd-shim-runc-v2 -namespace...
             ├─3201 /var/lib/rancher/k3s/data/921c0d40b0b3f73f2beae03ec1b23ec9aed3aa19fd651db6353e38f9636ddfe0/bin/containerd-shim-runc-v2 -namespace...
             ├─3250 /var/lib/rancher/k3s/data/921c0d40b0b3f73f2beae03ec1b23ec9aed3aa19fd651db6353e38f9636ddfe0/bin/containerd-shim-runc-v2 -namespace...
             ├─3297 /var/lib/rancher/k3s/data/921c0d40b0b3f73f2beae03ec1b23ec9aed3aa19fd651db6353e38f9636ddfe0/bin/containerd-shim-runc-v2 -namespace...
             └─3398 /var/lib/rancher/k3s/data/921c0d40b0b3f73f2beae03ec1b23ec9aed3aa19fd651db6353e38f9636ddfe0/bin/containerd-shim-runc-v2 -namespace...
gabriele-riccio@gabriele-riccio-VirtualBox:~$ sudo k3s kubectl get nodes
NAME                          STATUS   ROLES           AGE    VERSION
gabriele-riccio-virtualbox    Ready    control-plane   109m   v1.35.5+k3s1
gabriele-riccio@gabriele-riccio-VirtualBox:~$ mkdir -p ~/.kube
gabriele-riccio@gabriele-riccio-VirtualBox:~$ sudo cp etc/rancher/k3s/k3s.yaml ~/.kube/config
cp: impossibile eseguire stat di 'etc/rancher/k3s/k3s.yaml': File o directory non esistente
gabriele-riccio@gabriele-riccio-VirtualBox:~$ sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
gabriele-riccio@gabriele-riccio-VirtualBox:~$ sudo chown $USER:$USER ~/.kube/config
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get nodes
WARN[0000] Unable to read /etc/rancher/k3s/k3s.yaml, please start server with --write-kubeconfig-mode or --write-kubeconfig-group to modify kube config permissions
error: error loading config file "/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied
gabriele-riccio@gabriele-riccio-VirtualBox:~$ echo $KUBECONFIG

gabriele-riccio@gabriele-riccio-VirtualBox:~$ export KUBECONFIG=~/.kube/config
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get nodes
NAME                          STATUS   ROLES           AGE    VERSION
gabriele-riccio-virtualbox    Ready    control-plane   115m   v1.35.5+k3s1
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS      AGE
kube-system   coredns-8db54c48d-6llvx                  1/1     Running     1 (12m ago)   116m
kube-system   helm-install-traefik-crd-2gmdc            0/1     Completed   0             116m
kube-system   helm-install-traefik-x6ddq                0/1     Completed   2             116m
kube-system   local-path-provisioner-5d9d9885bc-ptd8g   1/1     Running     1 (12m ago)   116m
kube-system   metrics-server-786d997795-rs6zr           1/1     Running     1 (12m ago)   116m
kube-system   svclb-traefik-d8974e59-h26nr              2/2     Running     2 (12m ago)   115m
kube-system   traefik-9bcdbbd9-8zztj                    1/1     Running     1 (12m ago)   115m
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   116m
kube-node-lease   Active   116m
kube-public       Active   116m
kube-system       Active   116m
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl create namespace formazione-sou
namespace/formazione-sou created
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   117m
formazione-sou    Active   4s
kube-node-lease   Active   117m
kube-public       Active   117m
kube-system       Active   117m
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl get nodes
NAME                          STATUS   ROLES           AGE    VERSION
gabriele-riccio-virtualbox    Ready    control-plane   117m   v1.35.5+k3s1
gabriele-riccio@gabriele-riccio-VirtualBox:~$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
gabriele-riccio@gabriele-riccio-VirtualBox:~$
