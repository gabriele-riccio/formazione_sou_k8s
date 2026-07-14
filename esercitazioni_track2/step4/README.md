# Step 4 – Helm Install via Jenkins Pipeline

## Obiettivo

Configurare Jenkins in modo che possa raggiungere il namespace `formazione-sou` sul cluster
Kubernetes locale (Minikube) e scrivere una pipeline dichiarativa che:

1. Prenda da GitHub il chart Helm versionato nello Step 3 (`flask-app`)
2. Esegua `helm install`/`upgrade` sull'istanza Minikube locale, nel namespace `formazione-sou`

## Architettura reale dell'ambiente

```
┌─────────────────────┐         SSH (192.168.56.1)        ┌──────────────────────┐
│   VM Vagrant         │ ─────────────────────────────────▶│   Mac host             │
│   192.168.56.20       │        tunnel -L 16443:...49907   │                        │
│                       │                                    │  Minikube (driver      │
│  ┌─────────────────┐  │                                    │  Docker)               │
│  │ jenkins-controller│ │                                    │  API server esposto    │
│  │ (Docker container)│ │                                    │  su 127.0.0.1:<porta   │
│  │                  │  │                                    │  dinamica>             │
│  │ - kubectl        │  │                                    │                        │
│  │ - helm           │  │                                    └──────────────────────┘
│  │ - sshpass         │ │
│  └─────────────────┘  │
└─────────────────────┘
```

Jenkins **non** gira sullo stesso host di Minikube: Jenkins è containerizzato dentro una VM
VirtualBox separata (provisionata con Vagrant + Ansible), mentre Minikube gira su Docker
Desktop direttamente sul Mac. Le due macchine comunicano tramite la rete host-only di
VirtualBox (`192.168.56.0/24`), il cui gateway verso il Mac è `192.168.56.1`.

## Perché serve un tunnel SSH

L'API server di Minikube (driver Docker) è esposto solo su `127.0.0.1:<porta>` **del Mac**,
non su un'interfaccia raggiungibile dalla rete host-only. Inoltre quella porta **cambia**
ogni volta che il cluster Minikube viene ricreato da zero (mapping dinamico assegnato da
Docker Desktop).

Soluzione adottata: ad ogni build, la pipeline

1. Si collega via SSH al Mac e legge la porta reale corrente di Minikube
   (`kubectl cluster-info` sul Mac)
2. Apre un tunnel SSH che inoltra una porta fissa locale al container Jenkins
   (`16443`) verso quella porta reale sul Mac
3. Genera un kubeconfig "runtime" che punta a `127.0.0.1:16443` (il lato locale del tunnel)

Questo rende la pipeline resiliente ai riavvii di Minikube, senza bisogno di fissare
manualmente la porta o toccare la configurazione a ogni build.

## Setup RBAC su Kubernetes

- **ServiceAccount** `jenkins-deployer` nel namespace `formazione-sou`
- **RoleBinding** che collega il ServiceAccount alla ClusterRole builtin `edit`,
  ristretto al namespace (non cluster-wide) — permette di gestire Deployment, Service,
  ConfigMap, Secret, Pod ecc. ma **non** di creare namespace o altre risorse cluster-scope
- **Token** generato con `kubectl create token jenkins-deployer -n formazione-sou --duration=8760h`
  (validità 1 anno), incorporato in un kubeconfig dedicato

File: `k8s/jenkins-sa.yaml` (ServiceAccount + RoleBinding)

## Credential Jenkins configurate

| ID Credential | Tipo | Contenuto |
|---|---|---|
| `jenkins-kubeconfig` | Secret file | Kubeconfig template con placeholder `__MINIKUBE_PORT__` |
| `mac-ssh-password` | Secret text | Password dell'account Mac, usata per il tunnel SSH |

## Stage della pipeline

1. **Checkout** — clona `formazione_sou_k8s` da GitHub
2. **Trova porta Minikube sul Mac** — SSH + `kubectl cluster-info` + parsing con `grep`/`cut`
3. **Apri tunnel SSH verso Minikube** — backgrounding esplicito (no `-f`), tracciamento PID,
   verifica di raggiungibilità reale con `curl`
4. **Genera kubeconfig runtime** — sostituisce il placeholder con la porta del tunnel
5. **Verifica connessione al cluster** — `kubectl get namespace formazione-sou`
6. **Helm lint** — valida il chart prima del deploy
7. **Helm upgrade --install** — deploy idempotente, con `--set image.tag=v1.0.0`

## Jenkinsfile completo

```groovy
pipeline {
    agent any

    environment {
        NAMESPACE      = 'formazione-sou'
        RELEASE_NAME   = 'flask-app-example'
        CHART_PATH     = 'esercitazioni_track2/step3/charts/flask-app'
        LOCAL_PORT     = '16443'
        MAC_USER       = 'gabrielericciosourcesense'
        MAC_GATEWAY_IP = '192.168.56.1'
        KUBECONFIG_FILE = "${WORKSPACE}/runtime-kubeconfig.yaml"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/gabriele-riccio/formazione_sou_k8s.git'
            }
        }

        stage('Trova porta Minikube sul Mac') {
            steps {
                withCredentials([string(credentialsId: 'mac-ssh-password', variable: 'MAC_PASSWORD')]) {
                    script {
                        env.MINIKUBE_REAL_PORT = sh(
                            script: """
                                sshpass -p '${MAC_PASSWORD}' ssh -o StrictHostKeyChecking=no ${MAC_USER}@${MAC_GATEWAY_IP} \
                                "/usr/local/bin/kubectl cluster-info | grep -m1 -o '127.0.0.1:[0-9]*' | cut -d: -f2"
                            """,
                            returnStdout: true
                        ).trim()
                        echo "Porta reale Minikube sul Mac: ${env.MINIKUBE_REAL_PORT}"
                    }
                }
            }
        }

        stage('Apri tunnel SSH verso Minikube') {
            steps {
                withCredentials([string(credentialsId: 'mac-ssh-password', variable: 'MAC_PASSWORD')]) {
                    sh """
                        sshpass -p '${MAC_PASSWORD}' ssh -N -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes \
                          -L ${LOCAL_PORT}:127.0.0.1:${env.MINIKUBE_REAL_PORT} \
                          ${MAC_USER}@${MAC_GATEWAY_IP} > /tmp/tunnel.log 2>&1 &
                        TUNNEL_PID=\$!
                        echo "PID tunnel avviato: \$TUNNEL_PID"
                        sleep 2
                        if ! kill -0 \$TUNNEL_PID 2>/dev/null; then
                            echo "ERRORE: il processo del tunnel non e' piu' attivo dopo 2 secondi"
                            cat /tmp/tunnel.log
                            exit 1
                        fi
                        echo "Processo tunnel confermato attivo (PID \$TUNNEL_PID)"
                        curl -vk --max-time 3 https://127.0.0.1:${LOCAL_PORT}/version
                        CURL_EXIT=\$?
                        echo "Curl exit code: \$CURL_EXIT"
                        if [ "\$CURL_EXIT" -ne 0 ]; then
                            echo "ERRORE: porta non raggiungibile nonostante il processo sia attivo"
                            cat /tmp/tunnel.log
                            exit 1
                        fi
                    """
                }
            }
        }

        stage('Genera kubeconfig runtime') {
            steps {
                withCredentials([file(credentialsId: 'jenkins-kubeconfig', variable: 'KUBECONFIG_TEMPLATE')]) {
                    sh """
                        sed 's/__MINIKUBE_PORT__/${LOCAL_PORT}/' "\$KUBECONFIG_TEMPLATE" > ${KUBECONFIG_FILE}
                    """
                }
            }
        }

        stage('Verifica connessione al cluster') {
            steps {
                sh "kubectl --kubeconfig=${KUBECONFIG_FILE} get namespace ${NAMESPACE}"
            }
        }

        stage('Helm lint') {
            steps {
                sh "helm lint ${CHART_PATH}"
            }
        }

        stage('Helm upgrade --install') {
            steps {
                sh """
                    helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
                      --kubeconfig=${KUBECONFIG_FILE} \
                      --namespace ${NAMESPACE} \
                      --set image.tag=v1.0.0
                """
            }
        }
    }

    post {
        always {
            sh 'pkill -f "ssh -N -o StrictHostKeyChecking" || true'
        }
        success {
            echo "Deploy completato su namespace ${NAMESPACE}"
        }
        failure {
            echo "Deploy fallito, controlla i log sopra"
        }
    }
}
```

## Problemi incontrati e soluzioni

| Problema | Causa | Soluzione |
|---|---|---|
| Jenkins non raggiungibile su vecchio IP | Container/VM diversi da quelli attesi | Individuata la VM corretta (`step1-rocky9`, IP `192.168.56.20`) tramite `vagrant global-status` e `grep` sui playbook |
| `vagrant provision` non eseguiva nulla | Vagrantfile senza blocco `config.vm.provision` | Playbook Ansible lanciato manualmente con `ansible-playbook` |
| `ModuleNotFoundError: requests` | Libreria Python mancante sulla VM | Installato `python3-pip` + `pip3 install requests` |
| `connection refused` al Docker socket | Docker non installato sulla VM ricreata | Installato Docker CE da zero via `dnf` |
| `kubectl: command not found` via SSH | PATH/shell zsh non interattiva | Path assoluto `/usr/local/bin/kubectl` |
| `no matches found: jsonpath={...}` | zsh interpreta `[...]` come glob pattern | Sostituito `jsonpath` con parsing `grep`/`cut` su `kubectl cluster-info` |
| Tunnel "attivo" ma `curl` restituiva `Connection refused` | Flag `-f` di SSH (doppio fork) non sopravviveva nell'ambiente Jenkins | Backgrounding esplicito con `&` + tracciamento PID + verifica con `curl -v` |
| `namespaces is forbidden` | `--create-namespace` richiede permessi cluster-scope, il ServiceAccount ne ha solo a livello namespace | Rimosso `--create-namespace` (il namespace esisteva già) |
| `ErrImagePull` | Tag immagine di default (`1.0.0`, da `appVersion`) diverso dal tag reale su DockerHub (`v1.0.0`) | Aggiunto `--set image.tag=v1.0.0` esplicito in `helm upgrade` |
| Token Kubernetes esposto su GitHub pubblico | `git add .` ha incluso per errore il kubeconfig con token | File rimosso dal tracking, aggiunto a `.gitignore`, token rigenerato (invalidando quello vecchio) |

## Risultato finale

```
NAME: flask-app-example
STATUS: deployed
REVISION: 2

pod/flask-app-example-665f9b6c9f-t5plv   1/1   Running
```

Verificato con `kubectl port-forward` che l'app Flask risponde correttamente
("Hello World") su `http://127.0.0.1:8080`.

## File del repository

```
esercitazioni_track2/step4/
├── Jenkinsfile              # pipeline dichiarativa completa
├── jenkins-sa.yaml          # ServiceAccount + RoleBinding
├── jenkins-kubeconfig.yaml  # template kubeconfig (NON committato, in .gitignore)
└── README.md
```

## Nota di sicurezza

Il file `jenkins-kubeconfig.yaml` contiene un token di autenticazione al cluster e
**non va mai committato in chiaro** su Git. È stato aggiunto a `.gitignore` dopo un
incidente di esposizione accidentale (risolto rigenerando il token).
