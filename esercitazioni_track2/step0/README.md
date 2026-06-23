# Esercizio — Step 0 - Installazione locale Kubernetes

Il seguente modulo richiede l'interazione con Kubernetes in una distribuzione minimale e locale. Esistono svariate soluzioni, viene proposto allo studente di provare uno dei seguenti tool e scegliere quello che più si adatta alla propria workstation di lavoro.
- **MiniKube** (consigliato)
- **K3s**
- **Kind**

> Homebrew l'ho scartato perché sulla macchina in uso compilava tutto da sorgente
> (visibile dal processo `./make.bash` nel terminale), rendendo l'installazione estremamente lenta.
> Ho scelto di scaricare i **binari precompilati direttamente**, che risultano molto più veloci.

---

## Prerequisiti

- **Docker Desktop** installato e in esecuzione (necessario per MiniKube e Kind).
- **VM Ubuntu** su VirtualBox già configurata (esercizi passati) per K3s.

---

## 1. MiniKube

MiniKube è la soluzione consigliata. Crea un cluster Kubernetes a nodo singolo usando Docker come driver, senza bisogno di una VM separata.

### Installazione kubectl (client CLI)

kubectl è il client standard per interagire con qualsiasi cluster Kubernetes.
Va installato indipendentemente dal tool scelto.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
kubectl version --client
```

### Installazione MiniKube

Scaricato il binario precompilato per macOS Intel (amd64) direttamente dai server ufficiali
di Google, senza passare da Homebrew.

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
sudo install minikube-darwin-amd64 /usr/local/bin/minikube
rm minikube-darwin-amd64
minikube version
```

### Avvio del cluster

Docker Desktop deve essere aperto prima di eseguire questo comando.

```bash
minikube start --driver=docker
```

### Verifica

```bash
minikube status
kubectl get nodes
kubectl get pods -A
kubectl get namespaces
```
### Creazione del namespace richiesto
kubectl create namespaces formazione-sou

**Verifica**
kubectl get namespaces --> comparirà anche formazione-sou

---
## TERMINALE
![prima parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.19.21.png)
![seconda parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.36.15.png)
![terza parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.38.42.png)


---
### Comandi utili

| Comando | Descrizione |
|---|---|
| `minikube start` | Avvia il cluster |
| `minikube stop` | Ferma il cluster (stato preservato) |
| `minikube pause` | Mette in pausa (libera CPU) |
| `minikube unpause` | Riprende dalla pausa |
| `minikube delete` | Elimina completamente il cluster |
| `minikube dashboard` | Apre la dashboard nel browser |
| `minikube status` | Stato del cluster |


---
## 2. Kind

Kind (Kubernetes IN Docker) crea un cluster Kubernetes usando container Docker come nodi.
Richiede Docker Desktop già installato e in esecuzione.

### Installazione

Anche qui, binario precompilato scaricato direttamente da GitHub (nessun Homebrew).

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-darwin-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind version
```

### Avvio del cluster

```bash
kind create cluster
```

### Verifica

```bash
kubectl cluster-info --context kind-kind
kubectl get nodes
kubectl get pods -A
kubectl get namespaces
```

### Creazione del namespace richiesto
kubectl create namespaces formazione-sou

**Verifica**
kubectl get namespaces --> comparirà anche formazione-sou

---
## TERMINALE
![quarta parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.27.48.png)
![quinta parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.51.00.png)
![sesta parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2012.51.13.png)

---
### Note su Kind

- Ogni nodo del cluster è un container Docker: visibili con `docker ps`
- Per eliminare il cluster: `kind delete cluster`
- Supporta multi-nodo tramite file di configurazione YAML

---

## 3. K3s su Ubuntu (VirtualBox)

K3s è una distribuzione Kubernetes ultra-leggera pensata per ambienti con risorse limitate
(edge, IoT, CI/CD). Non gira nativamente su macOS, quindi è stato installato nella VM Ubuntu
già configurata in precedenti esercizi.

### Installazione

Dalla VM Ubuntu, un singolo comando scarica e installa tutto (server K3s + kubectl integrato):

```bash
curl -sfL https://get.k3s.io | sh -
```

### Verifica del servizio

```bash
sudo systemctl status k3s
```

### Verifica con kubectl integrato di K3s

K3s include il proprio kubectl richiamabile tramite `k3s kubectl`:

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```
### Configurazione kubectl standard
E' possibile però configurlo con il metodo standard che ho usato anche per kind e Minikube:
Posso usare il comando `kubectl` senza il prefisso `k3s` e senza `sudo`:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
kubectl get nodes
```

### Creazione del namespace richiesto

```bash
kubectl create namespace formazione-sou
kubectl get namespaces
```
## TERMINALE
![settima parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.17.57.png)
![ottava parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.18.57.png)
![nona parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.19.16.png)
![decima parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.19.32.png)
![undicesima parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.20.10.png)
![dodicesima parte terminale](file_img_step0/Screenshot%202026-06-15%20alle%2014.28.27.png)

---

## Fermare e riavviare i cluster

Al termine della sessione di lavoro i container MiniKube e Kind risultano in stato `Exited (137)`
in Docker Desktop. Ecco come gestirli correttamente.

### MiniKube

```bash
# Ferma il cluster (stato preservato, riavviabile)
minikube stop

# Riavvia il cluster
minikube start

# Elimina completamente il cluster
minikube delete
```

### Kind

Kind non ha un comando `stop` nativo: i nodi sono container Docker, quindi si gestiscono
direttamente tramite Docker oppure tramite `kind delete`.

```bash
# Ferma il container senza eliminare il cluster
docker stop kind-control-plane

# Riavvia il container fermato
docker start kind-control-plane

# Elimina completamente il cluster
kind delete cluster

# Ricrea il cluster da zero
kind create cluster
```

> 💡 **Nota:** Usa `minikube stop` (non `delete`) e `docker stop` (non `kind delete`)
> per preservare lo stato del cluster tra una sessione e l'altra.

### K3s (Ubuntu VirtualBox)

K3s gira come servizio systemd, quindi si gestisce con `systemctl`:

```bash
# Ferma il servizio
sudo systemctl stop k3s

# Riavvia il servizio
sudo systemctl start k3s

# Verifica lo stato
sudo systemctl status k3s
```

---

## Confronto tra le soluzioni

| | MiniKube | Kind | K3s |
|---|---|---|---|
| Piattaforma | Mac, Linux, Win | Mac, Linux, Win | Linux nativo |
| Driver | Docker, VM, ecc. | Docker (obbligatorio) | Binario nativo |
| RAM minima | ~2 GB | ~2 GB | ~512 MB |
| Dashboard | Inclusa |  No | No |
| Installazione su Mac | Binario diretto | Binario diretto | Tramite VM |
| Consigliato per | Studio, lab | Test, CI/CD | Edge, prod leggera |
