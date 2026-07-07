# Gestione dei Secret in Kubernetes

Esercizio sulla creazione, modifica e consumo di Secret Kubernetes: creazione via `--from-literal`, esportazione e modifica manuale in YAML (con codifica Base64 esplicita), e utilizzo del Secret come variabile d'ambiente in un Pod.

## Obiettivo

1. Creare un Secret contenente utente e password tramite `--from-literal`.
2. Visualizzare il Secret in formato YAML, salvarlo su file e modificarlo per creare un nuovo Secret con credenziali diverse (codificate
   manualmente in Base64).
3. Creare un Pod in cui uno dei due Secret venga esposto come variabili d'ambiente, ed entrare nel Pod per dare evidenza del valore con
   `echo`.

## Struttura dei file

```
esercitazione_secret/
├── README.md                     <- questo file
├── user-pass-secret.yaml         <- Secret originale esportato da kubectl
├── user-pass-secret-nuovo.yaml   <- Secret modificato con nuove credenziali
└── secret-pod.yaml               <- Pod che consuma il Secret come env var
```

## Prerequisiti

**Cluster Kubernetes** funzionante (in questo esercizio ho usato **Minikube** su Docker desktop).
Prima cosa avvio Docker Desktop, poi uso `docker info` per vedere se il demone risponde e cosa è attivo.

Poi avvio **Minikube** con `minikube start` e vado a vedere lo status e verificare i nodi con:

```bash
minikube status
kubectl get nodes
```

## 1. Creazione del Secret con `--from-literal`

Vado a creare il primo dei due Secret chiamato user-pass con --from-literal in modo che il tipo sia `Opaque` (che è di default con --from-literal), con 2 valori username e password.

```bash
kubectl create secret generic user-pass \
  --from-literal=username=pippo \
  --from-literal=password=admin123
```

Kubernetes codifica automaticamente i valori in Base64, dopo averlo creato verifico se ho creato il secret e verifico che non siano presenti nei log di kubectl describe, dove vedo solo il `byte count` dei valori (es. `password: 8 bytes`).

```bash
kubectl get secrets
kubectl describe secret user-pass
```

## 2. Esportazione in YAML e creazione di un secondo Secret

Per prima cosa effettuo l'esportazione in YAML con il comando:

```bash
kubectl get secret user-pass -o yaml > user-pass-secret.yaml
```
che esporta i valori già in Base64 (non cifrati — solo codificati) nel file yaml `user-pass-secret.yaml`:

```yaml
apiVersion: v1
data:
  password: YWRtaW4xMjM=
  username: cGlwcG8=
kind: Secret
metadata:
  name: user-pass
  namespace: default
    resourceVersion: "2983"
  uid: c5f0577e-0d1f-4f8c-bd5a-0788acea3a31
type: Opaque
```

Per creare un secondo Secret con credenziali diverse, il campo `data` richiede valori già codificati in Base64, se avessi usato `stringdata` non avrei dovuto codificarli in base64, lo avrebbe fatto di default.
Quindi codifico 2 nuovi valori di `username` e `password` in base64:

```bash
echo -n "paperino" | base64   # cGFwZXJpbm8=
echo -n "admin456" | base64   # YWRtaW40NTY=
```

Poi copio il file yaml in uno nuovo scrivendo i due valori Base64 appena calcolati in `data.username` e `data.password`, e cambio il `metadata.name` in uno nuovo:

```bash
cp user-pass-secret.yaml user-pass-secret-nuovo.yaml
vim user-pass-secret-nuovo.yaml
```

Infine applico il file nuovo e verifico che sia presente tra i secret :

```bash
kubectl apply -f user-pass-secret-nuovo.yaml
kubectl get secrets
```

## 3. Pod con il Secret come variabile d'ambiente

Ora posso generare il pod che andrà a consumare il secret come variabile d'ambiente definendo la `env`.
Le variabili d'ambiente descritte nel pod vengono prese dal secret usando `valueFrom` e `secretKeyRef`, scrivendo come nome il nome del file yaml dello script e come chiave username e password rispettivamente.
In breve ogni variabile è mappata singolarmente da una chiave del Secret tramite `secretKeyRef`.

`secret-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-envvar-pod
spec:
  containers:
    - name: secret-container
      image: alpine
      command: ["sleep", "3600"]
      env:
        - name: SECRET_USERNAME
          valueFrom:
            secretKeyRef:
              name: user-pass-nuovo
              key: username
        - name: SECRET_PASSWORD
          valueFrom:
            secretKeyRef:
              name: user-pass-nuovo
              key: password
```

> `command: ["sleep", "3600"]` è necessario perché Alpine non ha un processo di default che resta in esecuzione:
> senza un comando che aspetti attivamente, il container terminerebbe subito dopo l'avvio (il container vive finché vive il suo processo
> con PID 1).


Effettuo poi anche l'applicazione del pod e verifico che sia presente tra i pods:

```bash
kubectl apply -f secret-pod.yaml
kubectl get pods
```

## 4. Verifica dentro il Pod
Infine effettuo la verifica che le variabili siano state salavate come `SECRET_USERNAME` e `SECRET_PASSWORD` entrando nel pod.
Uso il nome scritto nei metadati del file `secret-pod.yaml` e immetto `-- sh` dato che l'immagine Alpine non ha la shell bash al suo interno.

```bash
kubectl exec -it secret-envvar-pod -- sh
```

Dentro la shell del container che si aprirà mi basterà verificare con `echo $SECRET_USERNAME` e `echo $SECRET_PASSWORD` che mi darà come output i valori immessi nel secret senza codifica:

```sh
/ # echo $SECRET_USERNAME
paperino
/ # echo $SECRET_PASSWORD
admin456
/ # exit
```

Questo output dimostra che il valore del Secret, una volta iniettato nel container come variabile d'ambiente, è leggibile in chiaro come semplice testo se si ha accesso al processo, non si ha nessuna protezione a runtime.
