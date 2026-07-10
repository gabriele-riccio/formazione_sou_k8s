# Step 3 — Helm Chart per flask-app-example

## Obiettivo

Creare un Helm Chart utilizzando `helm init custom` (trabocchetto o versione vecchia esercizio dato che Helm 3 non supporta più helm init ho usato `helm create`) che effettui il deploy dell'immagine creata tramite la pipeline `flask-app-example-build` (in input deve essere possibile specificare quale tag rilasciare).
Versionare Helm Chart nella repo "formazione_sou_k8s" in una sub-folder denominata "charts"

## Struttura

```
charts/flask-app/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── ingress.yaml          (disabilitato di default)
│   ├── hpa.yaml               (disabilitato di default)
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   └── tests/test-connection.yaml
└── .helmignore
```

Generata con lo scaffold ufficiale di Helm 3 (modificando alcune cose).
Ho usato il comando:

```bash
helm create charts/flask-app
```

## Cosa è stato modificato rispetto allo scaffold di default??

### Chart.yaml

```bash
apiVersion: v2
name: flask-app
description: Helm chart per il deploy di flask-app esercizio per Kubernetes

# A chart can be either an 'application' or a 'library' chart.
#
# Application charts are a collection of templates that can be packaged into versioned archives
# to be deployed.
#
# Library charts provide useful utilities or functions for the chart developer. They're included as
# a dependency of application charts to inject those utilities and functions into the rendering
# pipeline. Library charts do not define any templates and therefore cannot be deployed.
type: application

# This is the chart version. This version number should be incremented each time you make changes
# to the chart and its templates, including the app version.
# Versions are expected to follow Semantic Versioning (https://semver.org/)
version: 0.1.0

# This is the version number of the application being deployed. This version number should be
# incremented each time you make changes to the application. Versions are not expected to
# follow Semantic Versioning. They should reflect the version the application is using.
# It is recommended to use it with quotes.
appVersion: "1.0.0"
```


| Campo | Valore | Note |
|---|---|---|
| `name` | `flask-app` | invariato, coincide con la cartella |
| `description` | aggiornata | Ho descritto l'esercizio che deve fare il deploy di flask-app-example |
| `version` | `0.1.0` | versione del chart (struttura/template) |
| `appVersion` | `"1.0.0"` | versione applicativa di riferimento, usata come fallback del tag immagine |
> Ho aggiornato l'appVersion in `"1.0.0"` dato che
### values.yaml

```yaml
image:
  repository: gabbogr71809/flask-app-example
  pullPolicy: IfNotPresent
  tag: ""        # vuoto di proposito(lo spiego sotto)

service:
  type: ClusterIP
  port: 5000      # L' ho cambiato dato che Flask ascolta su 0.0.0.0:5000
```

Tutti gli altri valori (probe, resources, autoscaling, ingress, ecc.) sono rimasti
quelli generati di default da Helm, inoltre ho disabilitato quelli che non servono per questo esercizio.



### deployment.yaml / service.yaml

Nessuna modifica necessaria: lo scaffold di Helm referenzia già correttamente
`.Values.image.repository`, `.Values.image.tag` e `.Values.service.port`, quindi
basta aggiornare `values.yaml` perché la configurazione si propaghi automaticamente
in entrambi i template.

## Tag dell'immagine: come funziona il parametro in input

Nel `deployment.yaml` generato da Helm:

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

Il tag è risolto così:

1. Se `image.tag` viene passato esplicitamente (file values o `--set`), quel valore vince.
2. Se `image.tag` è vuoto (default in `values.yaml`), si usa `appVersion` da `Chart.yaml`
   come fallback.

Questo permette di specificare il tag da rilasciare al momento dell'installazione,
senza dover modificare il chart:

```bash
helm upgrade --install flask-app charts/flask-app \
  --set image.tag=<TAG_DA_RILASCIARE> \
  --namespace formazione-sou --create-namespace
```

## Verifiche effettuate

```bash
helm lint charts/flask-app
# 1 chart(s) linted, 0 chart(s) failed

helm template flask-app charts/flask-app
# image: "gabbogr71809/flask-app-example:1.0.0"   (fallback su appVersion)

helm template flask-app charts/flask-app --set image.tag=2.0.1
# image: "gabbogr71809/flask-app-example:2.0.1"   (override applicato correttamente)
```

Entrambi i test confermano che il meccanismo di parametrizzazione del tag funziona
come richiesto dall'esercizio.

## Riferimenti

- Scaffold generato con `helm create` (Helm 3, non più `helm init`, deprecato da Helm 2)
