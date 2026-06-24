# Step 2 - Pipeline Jenkins per Build e Push immagine Docker

## Obiettivo

Creare una pipeline Jenkins dichiarativa (Groovy) che automatizzi la build di un'immagine Docker di una web app Flask e il push su DockerHub, con logica di tagging basata sui tag e branch Git.

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
