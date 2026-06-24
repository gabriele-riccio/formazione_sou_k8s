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

### Web App Flask e requirements.txt

Per prima cosa ho creato nella sottodirectory `app` il file `app.py` che usa Flask cioè un micro-framework Python per creare web app.

``` py

from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "<h1>Hello World</h1>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

```
Con esso importo la classe Flask dalla libreria, poi creo con `app = Flask(__name__)` un'istanza dell'app indicando con `__name__` il modulo
corrente.
Utilizzo il decorator `@app.route("/")` per dire a Flask che quando qualcuno visita / di eseguire la funzione `hello()`, che definisco subito dopo in modo che stampi`Hello World`.

Poi inserisco l'iterazione che fa in modo che se il modulo è il main, di fare ascoltare Flask su tutte le interfacce di rete con `host="0.0.0.0"`, altrimenti Flask ascolterebbe solo su localhost e non sarebbe raggiungibile fuori dal container, esponendo la porta 5000
e inserendo `debug=True` per farlo riavviare se ci sono modifiche al codice.

Poi ho creato il file `requirements.txt`, sempre nella stessa sottodirectory, per elencare tutte le librerie Python da installare ( ci serve solo Flask).

### Dockerfile
Poi ho creato il Dockerfile per generare l'immagine Docker, che poi andrà pushata tramite il Jenkinsfile su Dockerhub, e per installare Flask e le sue dipendenze.

Il Dockerfile è una lista di istruzioni che esegue Docker per buildare l'immagine, dove ogni istruzione crea un `layer` in modo che se essi non cambiano vengono riutilizzate nelle build successive.

``` dockerfile
FROM python:3.11-alpine

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

EXPOSE 5000

CMD ["python", "app.py"]

```

Per buildare l'immagine ho descritto 5 layer:
1. L'immagine che ho deciso di buildare è basata su `python:3.11-alpine`(molto più leggera rispetto a
   debian/ubuntu linux).
2. Ho impostato la cartella dentro il container dove avvengono le operazioni con `WORKDIR/app`.
3. Con Copy ho copiato soltanto il requirements.txt prima del resto per far installare con RUN pip install Flask e le sue dipendenze in modo
   da ottimizzare le build successive senza reinstallare Flask etc.
5. Dopo aver installato le dipendenze ho copiato il codice sorgente.
6. Infine ho esposto la porta 5000 e inserito i comandi che verranno eseguiti quando parte il container(python e app.py).

### Creazione account Dockerhub e inserimento credenziali Jenkins
Ho creato il mio account e un repository pubblico su DockerHub(registro pubblico immagini docker) dove poi ho pushato la mia prima immagine docker tramite Jenkins(tramite quanto scritto nella pipeline).

Come feci con GitHub ho generato un Access Token e poi una volta fatta partire la vm dell'esercizio precedente e raggiunto il sito di Jenkins ho salvato le credenziali in esso inserendo Username, Password( Access Token ) e un ID(che ho potuto scegliere in autonomia).

## Jenkinsfile

Ho creato il Jenkinsfile( che poi riprenderò da GitHub una volta pushato tramite Pipeline script from SCM) per scrivere una pipeline dichiarativa che dichiari in maniera strutturata i blocchi(pipeline, stages, steps) invece di scriverlo in maniera imperativa pura.

```groovy
pipeline {
    agent any

    environment {
        DOCKERHUB_USER     = 'gabbogr71809'
        IMAGE_NAME         = "${DOCKERHUB_USER}/flask-app-example"
        DOCKERHUB_CREDS_ID = 'dockerhub-credentials'

    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Determine Tag') {
            steps {
                script {
                    def gitTag    = sh(script: "git tag --points-at HEAD", returnStdout: true).trim()
                    def gitBranch = env.GIT_BRANCH.replaceAll('origin/','')?:''
                    def gitSHA    = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    if (gitTag) {
                        env.DOCKER_TAG = gitTag
                        echo "Build da tag Git - ${env.DOCKER_TAG}"
                    } else if (gitBranch == 'master' || gitBranch == 'main') {
                        env.DOCKER_TAG = 'latest'
                        echo "Build da master - latest"
                    } else if (gitBranch == 'develop') {
                        env.DOCKER_TAG = "develop-${gitSHA}"
                        echo "Build da develop - ${env.DOCKER_TAG}"
                    } else {
                        env.DOCKER_TAG = "branch-${gitSHA}"
                        echo "Build da branch generico - ${env.DOCKER_TAG}"
                    }
                }
            }
        }

        stage('Build') {
             steps {
                script {
                    docker.withRegistry('https://index.docker.io/v1/', env.DOCKERHUB_CREDS_ID) {
                        def image = docker.build("${env.IMAGE_NAME}:${env.DOCKER_TAG}", "esercitazioni_track2/step2")
                        image.push()
                    }
                }
            }
        }
    }

    post {
        success {
            echo " Immagine pushata: ${env.IMAGE_NAME}:${env.DOCKER_TAG}"
        }
        failure {
            echo "Pipeline fallita."
        }
    }
}
```

Ci sono **i primi due blocchi** dove:
1. agent any : Specifico che può eseguire la pipeline qualsiasi nodo/agent disponibile.
2. blocco environment : Dove definisco tutte le variabili d'ambiente che utilizzo nella pipeline(Username,Image e Id).
> Nel Image_Name avevo dimenticato la sintassi ${}, in questo modo la variabile non veniva espansa e il suo valore diventava letteralmente `{DOCKERHUB_USER}/flask-app-example`(E' stato uno dei motivi per il quale all'inizio non compilava).

Poi ci sono degli **stages** definiti con def che defenisce le variabili locali:
> In una pipeline dichiarativa, i blocchi `steps` accettano solo istruzioni predefinite Jenkins.
> Quando voglio scrivere logica Groovy libera (variabili, if/else) devo racchiuderla dentro un blocco `script { }`(lo uso per gitTag e      > gitSHA).

1. **`Checkout`**: Utilizzo il comando checkout scm(Source Control Management) che scarica il codice sorgente da GitHub.
2. **`Determine Tag`**: Qui viene determinato il tag dell'immagine docker tramite i branch/tag di git. Inserisco un blocco script{} per
   scrivere in logica Groovy libera all'interno degli step dove definisco 3 variabili git:
   - **`gitTag`**: Attraverso il comando git tag --points-at HEAD restituisce i tag Git che puntano al commit attuale(se non sono presenti
     tag viene lasciato vuoto).
   - **`gitBranch`**: Attraverso il comando env.GIT_BRANCH che mi rappresenta la variabile Jenkins con il nome del branch(con replaceall
     elimino origin/ che di solito sta davanti il branch).
   - **`gitSHA`**: Attraverso il comando git rev-parse --short HEAD restituisce i primi 7 caratteri del commit per il tag.
   Poi c'è il blocco `if/else` che se la condizione è verificata crea una variabile d'ambiente env.DOCKER_TAG chiamata in maniera diversa a     seconda del tipo di tag:

   | Trigger | Tag immagine Docker |
   |---|---|
   | Tag Git (es. `v1.0.0`) | uguale al tag Git |
   | Branch `main` | `latest` |
   | Branch (es.`develop`) | `develop-<SHA commit>` |

3. **`Build`**: Dove ho inserito delle istruzioni per la build:
   - **`docker.withRegistry(url, credId)`** che usando le credenziali Jenkins si autentica al registry(DockerHub)
   - **`docker.build(nome:tag context)`** che esegue la build dell'immagine, con il tag che viene specificato ogni volta con
     `${env.DOCKER_TAG}`.
     > Inserisco il build context esercitazioni_track2/step2 dato che senza esso Docker cerca il file nella root dell'ambiente di lavoro e
     > non trovandolo la build fallisce.
   - **`image.push()`** che fa il push dell'immagine su DockerHub con il tag specificato in docker.build.

Infine c'è il blocco **post** che viene eseguito sempre alla fine della pipeline, indipendentemente dall'esito, con le sezioni `success` e `failure` vengono eseguite rispettivamente solo in caso di successo o fallimento.

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

Output 
