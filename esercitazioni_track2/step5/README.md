# Step 5 - Check Deployment Best Practices

Script Bash che esegue un export del Deployment dell'applicazione Flask che ho installato negli step precendeti autenticandomi tramite un ServiceAccount dedicato (`cluster-reader`) e ne verifica le conformità alle best practices di Kubernetes ritornando errore:
`Readiness e Liveness Probles`, `Limits` e `Requests`.

Approccio scelto tra i quattro ammessi dalla consegna: **wrapping di `kubectl`**.

---

## Struttura

```
step5/
├── rbac/
│   └── cluster-reader.yaml   # ServiceAccount + ClusterRole + ClusterRoleBinding
├── export/                   # Output rigenerabile (escluso dal repo)
├── check-deployment.sh       # Script di automazione scritto in bash
└── README.md
```

| Voce | Scelta |
|---|---|
| Linguaggio script di automazione | Bash |
| Metodo di accesso alle API | wrapping di kubectl |
| Cluster | Minikube (locale) |
| Namespace | formazione-sou |
| Deployment target | flask-app-example (container: flask-app) installato via Helm (Step 4) |
| Chart Helm di riferimento | esercitazioni_track2/step3/charts/flask-app |

## Prerequisiti

| Requisito | Note |
|---|---|
| Cluster Kubernetes ≥ 1.24 | serve la TokenRequest API |
| `kubectl` | configurato con un contesto che possa creare un token |
| `jq` | parsing del JSON esportato |
| Deployment target | installato via Helm (Step 4) |

---
## Svolgimento
Dopo aver startato il cluster Minikube che ho utilizzato negli esercizi precedenti ho implementato RBAC di K8S (il quale serve viene utlizzato per la parte di `autorizzazione` per l'accesso alle API di K8S)

## Implementazione dell'RBAC
Vediamo prima gli oggetti:

| Ogetto | Scope | Funzione |
|---|---|---|
| ServiceAccount | namespace | Identità non umana; nome canonico: system:serviceaccount:<ns>:<nome> |
| Role | namespace | Insieme di permessi validi in un solo namespace |
| ClusterRole | cluster | Permessi su risorse cluster-scoped (nodes, PV, namespaces) e non-resource URL (/healthz) |
| RoleBinding | namespace | Associa un soggetto a un ruolo, limitatamente al proprio namespace |
| ClusterRoleBinding | cluster | Associa un soggetto a un ClusterRole in tutti i namespace |

>Un RoleBinding puo' referenziare un ClusterRole: in tal caso i permessi restano confinati al namespace del RoleBinding.
>E' il pattern corretto per riusare un ruolo scritto una sola volta senza concedere accesso all'intero cluster.

File: step5/rbac/cluster-reader.yaml

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-reader
  namespace: formazione-sou
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-reader
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]

  - apiGroups: [""]
    resources: ["pods", "services", "namespaces"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
  - kind: ServiceAccount
    name: cluster-reader
    namespace: formazione-sou

```


## Installazione dell'RBAC

```bash
kubectl apply -f rbac/cluster-reader.yaml
```

Il `ClusterRole` concede **solo lettura** e non include i Secret:

| apiGroup | Risorse | Verbi |
|---|---|---|
| `apps` | deployments, replicasets, statefulsets, daemonsets | get, list, watch |
| `""` (core) | pods, services, namespaces | get, list, watch |

Verifica dei permessi senza doversi autenticare come ServiceAccount:

```bash
kubectl auth can-i get deployments \
  --as=system:serviceaccount:formazione-sou:cluster-reader -n formazione-sou   # yes

kubectl auth can-i delete deployments \
  --as=system:serviceaccount:formazione-sou:cluster-reader -n formazione-sou   # no

kubectl auth can-i get secrets \
  --as=system:serviceaccount:formazione-sou:cluster-reader -n formazione-sou   # no
```

Le due risposte negative contano quanto quella positiva: dimostrano che il
ruolo non è sovradimensionato.

## Uso

```bash
chmod +x check-deployment.sh
./check-deployment.sh                       # usa i default
./check-deployment.sh altro-deployment      # deployment passato come argomento
NAMESPACE=produzione ./check-deployment.sh  # namespace da ambiente
```

### Parametri

| Variabile | Default | Descrizione |
|---|---|---|
| `NAMESPACE` | `formazione-sou` | namespace del Deployment |
| `$1` | `flask-app-example` | nome del Deployment |
| `SA` | `cluster-reader` | ServiceAccount da usare |
| `TOKEN_TTL` | `10m` | durata del token |
| `OUTDIR` | `./export` | cartella di output |

### Exit code

| Codice | Significato |
|---|---|
| `0` | Deployment conforme |
| `1` | Deployment **non** conforme (elenco degli attributi mancanti) |
| `2` | Errore operativo (dipendenze mancanti, RBAC, deployment inesistente) |

La distinzione tra `1` e `2` è ciò che rende lo script utilizzabile in una
pipeline: permette di separare una build fallita per non conformità reale da
un guasto infrastrutturale.

## Cosa viene verificato

Per **ogni** container in `.spec.template.spec.containers[]`:

- `readinessProbe`
- `livenessProbe`
- `resources.requests.cpu` e `resources.requests.memory`
- `resources.limits.cpu` e `resources.limits.memory`

Lo script non si ferma alla prima violazione ma le accumula tutte: un
validatore che rivela un problema per volta è inutilizzabile in CI.

### Esempio — Deployment non conforme

```
Identita   : system:serviceaccount:formazione-sou:cluster-reader
Export     : ./export/flask-app-example.json

=== Check best practices: Deployment 'flask-app-example' ===
ERRORE - 4 attributi obbligatori mancanti:
  [flask-app       ] manca: resources.requests.cpu
  [flask-app       ] manca: resources.requests.memory
  [flask-app       ] manca: resources.limits.cpu
  [flask-app       ] manca: resources.limits.memory
exit code: 1
```

### Esempio — Deployment conforme

```
=== Check best practices: Deployment 'flask-app-example' ===
OK - tutti i container definiscono probe, requests e limits.
exit code: 0
```

## Note tecniche

### Perché non basta `kubectl --token`

```bash
kubectl --token="$TOKEN" get deployment ...   # NON usa il ServiceAccount
```

Il contesto locale autentica con un *client certificate*, che `kubectl`
continua a presentare nell'handshake TLS. Lato server la catena di
autenticazione valuta per primo l'x509: se il certificato è valido, l'identità
risultante è quella dell'amministratore e il bearer token non viene nemmeno
letto. Lo script passerebbe quindi anche con un `cluster-reader` inesistente o
mal configurato — un test verde che non prova nulla.

Lo script costruisce perciò a runtime un **kubeconfig dedicato** contenente il
solo token, senza certificati client. La riga `kubectl auth whoami` stampa
l'identità effettiva a ogni esecuzione e funge da controprova.

### Gestione del token

- Generato via TokenRequest API con durata limitata (`--duration=10m`)
- Mai stampato a video né scritto su file versionati
- Kubeconfig temporaneo creato con `mktemp`, permessi `600`, rimosso da un
  `trap ... EXIT INT TERM` anche in caso di interruzione
- `export/` è in `.gitignore`: contiene output rigenerabile

### Analisi statica

```bash
shellcheck check-deployment.sh
```

L'unico rilievo (`SC2016`) è un falso positivo — `$c` e `\(...)` sono sintassi
jq, non Bash — ed è dichiarato esplicitamente con una direttiva
`# shellcheck disable`.

Da notare che `bash -n`, che esegue il solo parsing, non intercetta errori come
`VAR= "valore"` (con spazio dopo l'uguale): sintatticamente legittimo, ma
semanticamente tutt'altra cosa. Per quella classe di errori serve un linter.

## Correzione applicata al chart

Il chart generato da `helm create` definisce le probe ma lascia
`resources: {}` vuoto. Aggiunto in `step3/charts/flask-app/values.yaml`:

```yaml
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Ne risulta QoS class **Burstable**: il Pod può superare la propria request
quando il nodo è scarico, restando protetto rispetto a un `BestEffort` in caso
di eviction. Per ottenere **Guaranteed** basterebbe rendere i `limits`
identici alle `requests`.

Il template `deployment.yaml` conteneva già
`{{- toYaml .Values.resources | nindent 12 }}`, quindi non ha richiesto
modifiche: è bastato popolare i values.

```bash
helm lint "$CHART"
helm upgrade flask-app-example "$CHART" -n formazione-sou --wait
```

Il flag `--wait` fa attendere a Helm che i nuovi Pod siano effettivamente
`Ready` prima di dichiarare successo: senza, il comando tornerebbe subito e in
una pipeline non si saprebbe se il rollout è andato a buon fine.

## Possibili estensioni

- Estendere il controllo agli `initContainers[]`
- Aggiungere check su `securityContext.runAsNonRoot` e sul tag `latest`
- Applicare la validazione all'output di `helm template`, intercettando la non
  conformità *prima* del deploy

---


