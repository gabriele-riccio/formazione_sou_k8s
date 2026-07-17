# Esercizio bonus — MariaDB Backup & Restore

Esercizio assegnato: creazione di un'istanza MariaDB, popolamento con dati di
test, backup, restore su una VM diversa, verifica di consistenza. Orchestrato
poi con Ansible + Vault, e infine integrato in AWX.

Questo documento copre tutte e tre le fasi dell'esercizio:

- **Fase 1** — procedura eseguita interamente a mano, propedeutica alla
  scrittura dei playbook Ansible
- **Fase 2** — lo stesso flusso orchestrato con playbook Ansible, credenziali
  del database cifrate in Ansible Vault
- **Fase 3** — i playbook della Fase 2 eseguiti tramite AWX (Project,
  Inventory, Credentials, Job Template)


### Prossimi passi

**Fase 3**: esecuzione dei playbook di questa Fase 2 tramite AWX — Project
puntato al repository, Inventory con i due host, Credentials per SSH e
Vault, Job Template/Workflow per concatenare le fasi.

---

## Fase 3 — AWX

Fase 3 dell'esercizio: i playbook Ansible della Fase 2 eseguiti tramite AWX
invece che da riga di comando, con Project, Inventory e Credentials
configurati nella UI.

### Ambiente AWX

- AWX Operator (tag `2.19.1`) installato su Minikube (driver Docker),
  namespace `awx`
- Custom Resource `awx-demo.yml` applicata separatamente dal kustomize
  dell'Operator (kustomize non permette di referenziare file fuori
  dall'albero `config/default`)
- Accesso alla UI tramite tunnel Minikube (`minikube service
  awx-demo-service -n awx --url`), porta dinamica ad ogni riavvio

### Configurazione AWX

### Project

- **Name**: MariaDB Backup Restore
- **Source Control Type**: Git
- **Source Control URL**: repository `formazione_sou_k8s`
- **Source Control Branch**: main

AWX clona l'intero repository, non solo la sottocartella
`esercizio_bonus_AWX/mariadb` — il path specifico dei playbook si indica
poi nel singolo Job Template.

### Inventory

- **Name**: Maria DB Inventory
- **Hosts**: `db-primario` (`ansible_host: 192.168.56.50`), `db-restore`
  (`ansible_host: 192.168.56.51`)
- **Groups**: `db_primario`, `db_restore` (ciascuno con il proprio host),
  raggruppati sotto un gruppo padre **`mariadb`** tramite Related Groups —
  equivalente della sintassi `[mariadb:children]` del file `hosts.ini`
  usato nella Fase 2. Senza questo gruppo padre, i playbook con
  `hosts: mariadb` falliscono con `skipping: no hosts matched`.

### Credentials

- **SSH VM MariaDB** (tipo Machine, username `vagrant`) — chiave privata
  di `db-primario`, resa valida anche per `db-restore` aggiungendo la
  chiave pubblica corrispondente agli `authorized_keys` di quella VM (vedi
  sezione Problemi incontrati)
- **Vault MariaDB** (tipo Vault) — contiene la password del Vault usato
  nella Fase 2 per decifrare `vars/vault.yml`

### requirements.yml

File nella **radice del repository** (non nella sottocartella del
progetto) che dichiara le collection Ansible necessarie:

```yaml
---
collections:
  - name: community.mysql
    version: ">=3.0.0"
```

AWX lo legge automaticamente durante il sync del Project e installa la
collection nell'Execution Environment prima di eseguire i playbook. Deve
stare nella root del repo clonato, non in una sottocartella, altrimenti
AWX non lo trova.

### Job Template creati

| Nome | Playbook | Credentials |
|---|---|---|
| Installazione MariaDB | `installazione_mariadb.yml` | SSH VM MariaDB |
| Popolo database | `popolo_database.yml` | SSH VM MariaDB, Vault MariaDB |
| backup DB | `backup.yml` | SSH VM MariaDB, Vault MariaDB |
| restore DB | `restore.yml` | SSH VM MariaDB, Vault MariaDB |
| backup corrotto restore DB | `backup_corrotto_restore.yml` | SSH VM MariaDB, Vault MariaDB |

Tutti eseguiti con **Inventory**: Maria DB Inventory, **Project**: MariaDB
Backup Restore.

### Esito delle esecuzioni

Tutti e cinque i Job Template completati con esito **Successful**:

- **Installazione MariaDB**: `ok=4` su entrambi gli host, idempotente
  (`changed=0` al secondo run)
- **Popolo database**: database, utente, tabella e dati creati
  correttamente su `db-primario`
- **backup DB**: dump eseguito su `db-primario`
- **restore DB**: fetch + copy + import completati su `db-restore`,
  checksum coerente tra le due istanze
- **backup corrotto restore DB**: `rescued=1` confermato anche in
  esecuzione da AWX — stesso comportamento osservato da CLI nella Fase 2
  (import fallito per violazione PRIMARY KEY, gestito dal blocco
  `rescue`, nessun dato scritto parzialmente)

### Problemi incontrati e risolti

### Sidecar `kube-rbac-proxy` con tag immagine rotto

L'AWX Operator, tramite la patch `manager_auth_proxy_patch.yaml`, inietta
un sidecar (`gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`) per proteggere
l'endpoint delle metriche. Quel tag non era più disponibile sul registry
(`manifest unknown`), causando `ImagePullBackOff` sul pod dell'Operator.

**Risoluzione**: rimossa la riga `patches: - path:
manager_auth_proxy_patch.yaml` da `config/default/kustomization.yaml`
(funzionalità non necessaria per questo esercizio), poi `kubectl delete -k
config/default` + `kubectl apply -k config/default`.

### kustomize non accetta file fuori dal proprio albero

Tentativo iniziale di referenziare `awx-demo.yml` (nella root del repo
awx-operator) dentro `config/default/kustomization.yaml` bloccato da
kustomize per motivi di sicurezza (`file is not in or below`).

**Risoluzione**: Custom Resource applicata separatamente con `kubectl
apply -f awx-demo.yml -n awx`, dopo che l'Operator è già attivo — è il
flusso standard raccomandato, non un workaround.

### Due chiavi SSH diverse per le due VM

Ogni VM Vagrant genera la propria coppia di chiavi indipendente. Un
singolo Job Template AWX collega una sola Credential Machine a livello di
esecuzione, quindi due chiavi diverse per due host nello stesso Inventory
non sono supportate nativamente in un unico run.

**Risoluzione**: estratta la chiave pubblica corrispondente alla chiave
privata di `db-primario` (`ssh-keygen -y -f
.vagrant/machines/db-primario/virtualbox/private_key`) e aggiunta agli
`authorized_keys` di `db-restore`. Una singola Credential Machine
(`SSH VM MariaDB`) risulta così valida su entrambe le VM.

### Vault non decifrabile in AWX

Primo run fallito con `Invalid vars_file ... Attempting to decrypt but no
vault secrets found`: il file `.vault_pass` usato da CLI esiste solo sul
Mac, non nel container di esecuzione di AWX.

**Risoluzione**: creata una Credential di tipo **Vault** con la password
del Vault, aggiunta ai Job Template insieme a quella Machine.

### `skipping: no hosts matched`

I playbook con `hosts: mariadb` non trovavano host, perché l'Inventory
AWX aveva solo i gruppi `db_primario`/`db_restore`, senza il gruppo padre
`mariadb` che li raggruppa (equivalente di `[mariadb:children]`).

**Risoluzione**: creato il gruppo `mariadb`, con `db_primario` e
`db_restore` aggiunti come **Related Groups** (non come Hosts diretti).

### `community.mysql.mysql_db` non risolvibile

Job falliti con `couldn't resolve module/action
'community.mysql.mysql_db'`: la collection era installata solo
localmente sul Mac (`ansible-galaxy collection list`), non
nell'Execution Environment di AWX.

**Risoluzione**: creato `requirements.yml` con la collection richiesta.
Primo tentativo fallito perché il file era stato posizionato dentro
`esercizio_bonus_AWX/mariadb/` — AWX lo cerca solo nella **radice** del
repository clonato. Spostato in `formazione_sou_k8s/requirements.yml` e
risolto dopo un nuovo sync del Project.

### VM Vagrant "aborted" dopo riavvio del Mac

Dopo un riavvio completo del Mac (necessario per sbloccare Docker
Desktop/Minikube in stato di TLS handshake timeout), le VM Vagrant
risultavano `aborted`, causando `Operation timed out` sulle connessioni
SSH da AWX.

**Risoluzione**: `vagrant up` su entrambe le VM per riportarle allo stato
`running` prima di rilanciare i Job Template.

### Esito Fase 3

| Punto traccia | Descrizione | Stato |
|---|---|---|
| 5 | Studio ed esecuzione dei playbook Ansible tramite AWX | ✅ |

Tutti i punti della traccia originale dell'esercizio bonus sono ora
completati, sia manualmente (Fase 1) sia in automazione con Ansible/Vault
(Fase 2) sia orchestrati da AWX (Fase 3).
