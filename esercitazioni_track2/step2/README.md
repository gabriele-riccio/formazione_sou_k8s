# Step 2 - Pipeline Jenkins dichiarativa (Groovy) per build immagine Docker

## Traccia

- Creare repo GitHub denominata "formazione_sou_k8s"
- Creare Dockerfile app di esempio Flask (Python) che esponga una pagina avente stringa "hello world" (prendere spunto da qui:
  https://github.com/docker/awesome-compose/tree/master/flask/app)
- Creare un account su DockerHub
- Scrivere una pipeline dichiarativa Jenkins chiamata flask-app-example-build che esegua i seguenti passi:
  - Effettui la build dell'immagine Docker della WebApp di esempio "hello world"
  - Effettui il push di tale immagine sul proprio account Docker Hub appena creato
> NOTA: In caso di problemi con il rate limit di Docker, installare localmente un registry Docker (va bene anche il registry nativo di
> Docker https://docs.docker.com/registry/ senza autenticazione).

- Modificare la pipeline in modo da tenere conto dei tag Git. Il tag dell'immagine Docker deve essere:
  - Uguale al tag git se "buildata" da tag git
  - latest se "buildata" da branch master
  - uguale  a "develop + SHA commit GIT" se "buildata" da branch develop
> NOTA: non è richiesto di lanciare il container con la webapp dalla pipeline. E' lasciato come esercizio Bonus (Tips: valutare se lanciarlo
> sulla stessa instanza di Docker che ospita Jenkins o su un'altra su una diversa VM. Cosa occorre fare per interfacciarsi con il Docker da
> Jenkins in ambo i casi ? )

---

## Struttura del progetto
```

esercitazioni_Track2/step2/
├── app/
│
│   ├── app.py              # Web app Flask
│
│   └── requirements.txt    # Dipendenze Python
│
├── Dockerfile              # Istruzioni build immagine Docker
│
├── Jenkinsfile             # Pipeline Jenkins dichiarativa
│
└── README.md

```
---

## Componenti

### Web App Flask

App Python minimale che espone una pagina "hello world" sulla porta 5000.

### Dockerfile

Immagine basata su `python:3.11-alpine`. Il build avviene in 5 layer:
1. Immagine base Python Alpine
2. Impostazione WORKDIR
3. Copia e installazione dipendenze
4. Copia codice sorgente
5. Esposizione porta 5000

### Jenkinsfile

Pipeline dichiarativa con 3 stage:
- **Checkout** — scarica il codice da GitHub
- **Determine Tag** — determina il tag Docker in base a branch/tag Git
- **Build** — esegue build e push su DockerHub

---

## Logica di tagging

| Trigger | Tag immagine Docker |
|---|---|
| Tag Git (es. `v1.0.0`) | uguale al tag Git |
| Branch `main` | `latest` |
| Branch `develop` | `develop-<SHA commit>` |
| Altro branch | `branch-<SHA commit>` |

---

## Prerequisiti Jenkins

- Plugin **Docker Pipeline** installato
- Credenziali DockerHub salvate in Jenkins con ID `dockerhub-credentials`
- Agente Jenkins con accesso al socket Docker (`/var/run/docker.sock` montato)

---

## Ambiente

- Jenkins in esecuzione su VM Rocky Linux 9 (`192.168.56.20`) via Vagrant + Docker
- Jenkins controller + inbound agent sulla rete `jenkins_network`

---

## Risultato

Immagine disponibile su DockerHub: `gabbogr71809/flask-app-example`

Tag prodotti durante l'esercizio:

| Tag | Origine |
|---|---|
| `latest` | branch `main` |
| `v1.0.0` | tag Git `v1.0.0` |
| `develop-d442b04` | branch `develop` |
