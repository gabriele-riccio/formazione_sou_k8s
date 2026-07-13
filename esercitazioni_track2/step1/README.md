# Step 1 — Workstation Mac

Automazione completa dell'infrastruttura: una VM Rocky Linux 9 gestita da Vagrant viene configurata interamente tramite Ansible, che installa Docker, configura le reti e deploya Jenkins Master e Agent come container.

---

## Requisiti della traccia

| # | Requisito | Stato |
|---|-----------|-------|
| 1 | VM Rocky Linux 9 via Vagrant (Intel) | Completato |
| 2 | Installazione Docker via Ansible | Completato |
| 3 | Configurazione Docker Network con IP statici via Ansible | Completato |
| 4 | Jenkins Master via Ansible + Docker con IP statico | Completato |
| 5 | Jenkins Agent via Ansible + Docker collegato al Master | Completato |

---

## Architettura

```
Mac (control node)
│
├── Vagrant → VM Rocky9 (192.168.56.20)
│             │
│             └── Docker
│                  ├── jenkins_network (172.18.0.0/16)
│                  │    ├── jenkins-controller  → Jenkins Master (porta 8080, 50000)
│                  │    └── jenkins-agent       → Jenkins Agent (label: docker)
│                  │
│                  └── [EXTRA] step1_network (172.26.0.0/24)
│                       ├── app_web   → Nginx  (172.26.0.10, porta 8081)
│                       └── app_cache → Redis  (172.26.0.11, rete interna)
│
└── Ansible
     ├── playbooks/install_docker.yml   → installa Docker sulla VM
     ├── playbooks/deploy_jenkins.yml   → avvia Jenkins Master + Agent
     └── [EXTRA] playbooks/deploy_app.yml → deploya stack Nginx + Redis
```

---

## Struttura del progetto

```
esercitazioni_track2/step1/
├── ansible-lab/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.ini
│   ├── vars/
│   │   ├── main.yml       # variabili in chiaro
│   │   └── vault.yml      # variabili cifrate con Ansible Vault
│   ├── .vault_pass        # password Vault (gitignored)
│   └── playbooks/
│       ├── install_docker.yml
│       ├── deploy_jenkins.yml
│       ├── [EXTRA] deploy_app.yml
│       └── roles/
│           ├── jenkins_stack/   # Master + Agent
│           └── [EXTRA] app_stack/  # Nginx + Redis
├── [EXTRA] esercitazione_step1/
│   └── Jenkinsfile
└── README.md
```

---

## Prerequisiti

- macOS con processore Intel
- Vagrant + VirtualBox installati
- Ansible installato sul Mac
- Account GitHub con accesso al repository `formazione_sou`

---

## Ricostruzione da zero

### 1. Avvia la VM

```bash
cd esercitazioni_track2/step1/ansible-lab
vagrant up
```

Verifica la connettività SSH:

```bash
vagrant ssh
exit
```

Verifica la connettività Ansible:

```bash
ansible rocky9 -m ping
```

> **Nota**: la chiave SSH generata da Vagrant su macOS Ventura è di tipo RSA, deprecato dal client SSH di default. L'inventory include già `ansible_ssh_common_args` con le opzioni di compatibilità necessarie.

### 2. Installa Docker sulla VM

```bash
ansible-playbook playbooks/install_docker.yml
```

Il playbook installa Docker Engine, abilita il servizio, e aggiunge l'utente `vagrant` al gruppo `docker`. Installa anche le librerie Python necessarie (`requests`, `setuptools`) per i moduli Ansible della collection `community.docker`.

### 3. Deploya Jenkins Master e Agent

```bash
ansible-playbook playbooks/deploy_jenkins.yml
```

Il playbook:
- Crea la rete Docker `jenkins_network`
- Crea il volume `jenkins_home` per la persistenza dei dati
- Avvia il container `jenkins-controller` (Jenkins Master) sulla porta 8080
- Avvia il container `jenkins-agent` collegato al Master

Jenkins è disponibile su `http://192.168.56.20:8080`.

### 4. Configura Jenkins al primo avvio

Recupera la password iniziale:

```bash
ansible rocky9 -m command \
  -a "docker exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword" \
  -b
```

Sul browser:
1. Incolla la password → **Continue**
2. **Install suggested plugins**
3. Crea utente admin
4. **Save and Finish** → **Start using Jenkins**

### 5. Collega l'Agent al Master

Su Jenkins → **Gestisci Jenkins → Nodi → New Node**:

| Campo | Valore |
|-------|--------|
| Nome | `agent-docker-1` |
| Tipo | Permanent Agent |
| Remote root directory | `/home/jenkins/agent` |
| Labels | `docker` |
| Launch method | Launch agent by connecting it to the controller |

Copia il **secret token** generato dalla pagina del nodo, poi aggiornalo nel ruolo:

```
playbooks/roles/jenkins_stack/tasks/main.yml → JENKINS_SECRET
```

Riesegui il playbook per aggiornare il container con il secret corretto:

```bash
ansible-playbook playbooks/deploy_jenkins.yml
```

Verifica nei log che l'Agent sia connesso:

```bash
ansible rocky9 -b -m command -a "docker logs jenkins-agent --tail 5"
```

Deve comparire `INFO: Connected`.

---


## Problemi noti e soluzioni

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `Permission denied` SSH | macOS depreca `ssh-rsa` | Aggiunto `PubkeyAcceptedAlgorithms+ssh-rsa` nell'inventory |
| IP in conflitto con altra VM | Stesso IP `192.168.56.10` già in uso | Usato `192.168.56.20` |
| `No module named requests` | Libreria Python mancante sulla VM | Aggiunto task installazione `python3-requests` nel playbook Docker |
| Agent Jenkins offline | Tipo nel nome variabile d'ambiente (`JENNKINS_SECRET`) | Corretto in `JENKINS_SECRET` |
