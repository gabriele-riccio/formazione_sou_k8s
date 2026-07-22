# Esercizio Cluster API (CAPD)

Creazione di un cluster Kubernetes tramite **Cluster API**, usando il provider infrastrutturale **Docker (CAPD)** per il provisioning locale, con successivo deploy di un'applicazione tramite Helm.

## Obiettivo

- Creare un management cluster (kind) su cui installare Cluster API
- Generare e provisionare un workload cluster con CAPD (1 control plane + 2 worker)
- Installare una CNI (Calico) e verificare che il cluster sia operativo
- Deployare l'applicazione `flask-app-example` (già containerizzata e con chart Helm da uno step precedente) sul nuovo cluster

## Prerequisiti

- Docker Desktop
- [`kind`](https://kind.sigs.k8s.io/) v0.23.0
- [`clusterctl`](https://cluster-api.sigs.k8s.io/) v1.13.4
- `kubectl`
- `helm` v3.15.4

## Struttura dei file

| File | Descrizione |
|---|---|
| `kind-capi-config.yaml` | Config kind con mount di `/var/run/docker.sock`, necessaria per far funzionare CAPD |
| `cluster-api.yaml` | Manifest generato con `clusterctl generate cluster` (flavor `development`, ClusterClass) |
| `clusterapi.kubeconfig` | Kubeconfig del workload cluster (IP corretto per macOS, vedi sotto) |
| `Cluster_API_guida_completa.pdf` | Guida teorica + pratica + troubleshooting completo dell'esercizio |

## Procedura

### 1. Management cluster

```bash
kind create cluster --name capi-management --config kind-capi-config.yaml
```

> Il mount del socket Docker va impostato alla creazione: non è modificabile su un cluster kind già esistente.

### 2. Inizializzazione Cluster API

```bash
export CLUSTER_TOPOLOGY=true
clusterctl init --infrastructure docker
```

### 3. Generazione e applicazione del workload cluster

```bash
clusterctl generate cluster clusterapi \
  --kubernetes-version v1.30.0 \
  --control-plane-machine-count=1 \
  --worker-machine-count=2 \
  --flavor development \
  > cluster-api.yaml

kubectl apply -f cluster-api.yaml
```

### 4. Monitoraggio

```bash
clusterctl describe cluster clusterapi
```

### 5. CNI (obbligatoria con CAPD)

```bash
clusterctl get kubeconfig clusterapi > clusterapi.kubeconfig

kubectl --kubeconfig clusterapi.kubeconfig apply \
  -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

### 6. Fix kubeconfig su macOS (Docker Desktop)

Il kubeconfig generato punta all'IP interno della rete Docker, non raggiungibile dall'host su macOS:

```bash
grep server clusterapi.kubeconfig
sed -i.bak 's|https://<IP_INTERNO>:6443|https://127.0.0.1:<PORTA_PUBBLICATA>|' clusterapi.kubeconfig
```

*(la porta pubblicata si trova con `docker ps`, colonna PORTS del container `<cluster>-lb`)*

### 7. Verifica nodi

```bash
kubectl --kubeconfig clusterapi.kubeconfig get nodes
```

### 8. Deploy applicazione

```bash
helm upgrade --install flask-app <path-al-chart> \
  --kubeconfig clusterapi.kubeconfig \
  --namespace flask-app --create-namespace \
  --set image.tag=latest
```

## Problemi incontrati (riassunto)

| Errore | Causa | Soluzione |
|---|---|---|
| `failed to get file "cluster-template.yaml"` | Manca il flavor nel comando `generate cluster` | Aggiungere `--flavor development` |
| `Cannot connect to the Docker daemon` | Management cluster kind creato senza mount del socket Docker | Ricreare kind con `extraMounts` sul socket |
| `cni plugin not initialized` | CAPD non installa una CNI di default | Applicare Calico sul workload cluster |
| `dial tcp <IP>:6443: i/o timeout` | Kubeconfig punta all'IP interno Docker, non raggiungibile su macOS | Sostituire con `127.0.0.1:<porta pubblicata>` |
| `ImagePullBackOff` | Tag immagine di fallback (`appVersion`) non pubblicato su Docker Hub | `--set image.tag=latest` |

Dettagli completi (teoria, cause, comandi) in `Cluster_API_guida_completa.pdf`.

## Pulizia

```bash
helm uninstall flask-app --kubeconfig clusterapi.kubeconfig -n flask-app
kind delete cluster --name capi-management
```

> Eliminando il management cluster kind vengono eliminati anche tutti i container del workload cluster che gestiva.
