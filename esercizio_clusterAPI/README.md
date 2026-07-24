# Esercizio Cluster API e deploy applicazione

Creazione di un cluster Kubernetes tramite **Cluster API**, usando il provider infrastrutturale **Docker (CAPD)** per il provisioning locale, con successivo deploy di un'applicazione tramite Helm (quella fatta nello step3 della track2).

## Obiettivo

- Creare un management cluster (kind) su cui installare Cluster API.
- Generare e provisionare un workload cluster con CAPD.
- Installare una CNI (Calico) e verificare che il cluster sia operativo.
- Deployare l'applicazione `flask-app-example` (già containerizzata e con chart Helm da uno step precedente) sul nuovo cluster


## Procedura

### 1. Scarico clusterctl

Una volta che ho controllato se ho installato `kind` e la sua versione,scarico la CLI di ClusterApi `clusterctl` con Download diretto e poi lo rendo eseguibile:

```bash
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/latest/download/clusterc
tl-darwin-amd64 -o clusterctl
chmod +x clusterctl
```


### 2. Management cluster con mount del socket Docker
Il controller di CAPD deve poter creare container Docker per conto del management cluster: serve quindi montare /var/run/docker.sock dentro il nodo kind, fin dalla creazione, modifico allora kind--capi-config.yaml montando il socket dentro il nodo :

```bash
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
extraMounts:
- hostPath: /var/run/docker.sock
containerPath: /var/run/docker.sock
```

Poi creo il cluster capi-management utilizzando il file di configurazione appena creato:

```bash
kind create cluster --name capi-management --config kind-capi-config.yaml
```
### 3. Inizializzazione di Cluster Api
Con la variabile d'ambiente `export CLUSTER_TOPOLOGY=true` abilito il supporto sperimentale per ClusterClass dentro clusterctl, dato che senza clusterctl non permetterebbe di usare oggetti basati su ClusterClass, e poi con `clusterctl init --infrastructure docker`preparo il management cluster installandoci sopra tutto il necessario per far funzionare Cluster API(cert manager, provider cluster-api, bootstrap provider(kubeadm),il control plane provider e l'infrastucture provider docker CAPD con il flag inserito.

```bash
export CLUSTER_TOPOLOGY=true
clusterctl init --infrastructure docker
```

### 4. Generazione e applicazione del cluster
Utilizzo il comando preso dalla documentazione online `clusterctl generate cluster clusterapi` per generare solo un manifest YAML e lo salvo su file `cluster-api.yaml`, inserendoci la versione, il numero di control-plane-machine, il numero di worker machine che voglio e quale variante del template usare (flavor development), dato che CAPD non ha un template senza nome.
Infine applico il manifest:

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
Per seguire il provisioning passo passo uso:

```bash
clusterctl describe cluster clusterapi
```

### 5. CNI (obbligatoria con CAPD) 

Con `clusterctl get kubeconfig clusterapi > clusterapi.kubeconfig` recupero il kubeconfig necessario per parlare direttamente con il workload cluster.
Ho bisogno della `CNI` dato che K8S non implementa da solo la rete che permette ai POD di comunicare, ma lo fa la CNI che in un cluster normale,tipo uno creato con kind o minikube, è già implementato ma con clusterAPI no.

Quindi installo la CNI(scelgo Calico) dentro il  `workload cluster` invece che nel management cluster(è il primo in cui si trovano i pod non nel management cluster).

```bash
clusterctl get kubeconfig clusterapi > clusterapi.kubeconfig

kubectl --kubeconfig clusterapi.kubeconfig apply \
  -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

### 6. Fix kubeconfig su macOS (Docker Desktop)

Il kubeconfig generato da clusterctl contiene l'IP interno della rete Docker del load balancer, che su macOS non è raggiungibile perché Docker Desktop gira dentro una VM nascosta invece che direttamente sull'host come su Linux.
Quindi bisogna sostituirlo con `127.0.0.1` e la porta pubblicata sull'host (`55001`), che punta comunque alla stessa API server ma attraverso un percorso di rete che il Mac può effettivamente raggiungere.

```bash
grep server clusterapi.kubeconfig
sed -i.bak 's|https://172.18.0.4:6443|https://127.0.0.1:55001|' clusterapi.kubeconfig
```

*(la porta pubblicata si trova con `docker ps`, colonna PORTS del container `clusterapi-lb`)*

### 7. Verifica finale dei nodi

```bash
kubectl --kubeconfig clusterapi.kubeconfig get nodes


clusterapi-gj5j2-jwwpz              Ready      control-plane   21m     v1.30.0
clusterapi-md-0-gwnt2-ff88n-6fvfx   Ready      <none>          2m46s   v1.30.0 
clusterapi-md-0-gwnt2-ff88n-djq84   Ready   <none>          108s   v1.30.0
```

### 8. Deploy applicazione

Voglio deployare nel workload cluster l'applicazione dello step3 `flask-app-example` che ha già un `helm chart custom`.
Controllo prima se ho `helm` installato poi vedo se l'applicazione flask-app funzioni ancora e con `helm upgrade --install` con quei flag installa (o aggiorna) il chart flask-app sul workload cluster nel namespace dedicato, forzando il tag immagine a latest (per evitare l'errore del tag).

```bash
helm upgrade --install flask-app <path-al-chart> \
  --kubeconfig clusterapi.kubeconfig \
  --namespace flask-app --create-namespace \
  --set image.tag=latest
```

### 9. Verifica finale 
Faccio una verifica finale:
- con `kubectl --kubeconfig clusterapi.kubeconfig get pods -n flask-app` verifica lo stato dei Pod creati da Helm nel
  namespace flask-app.
- con `kubectl --kubeconfig clusterapi.kubeconfig port-forward -n flask-app <pod> 8080:5000` creo un tunnel temporaneo tra il
  mio Mac e il Pod dentro il cluster: apre la porta 8080 su localhost, e inoltra tutto il traffico che arriva lì verso la
  porta 5000 del Pod (la porta su cui ascolta Flask, default). Serve perché, di default, un Pod non è raggiungibile
  dall'esterno del cluster, quindi uso un port-forward per avere un modo rapido per testarlo.
- Infine con `curl http://localhost:8080` faccio una richiesta HTTP verso localhost:8080, grazie al tunnel del comando
  precedente, ottenendo la risposta Hello World.
