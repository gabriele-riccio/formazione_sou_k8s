# Esercizio bonus: Esecuzione dei playbook fatti con Ansible eseguiti tramite AWX

Esecuzione dei playbook della fase Ansible tramite AWX invece che da riga di comando, configurando tramite UI:
Project puntato al repository, Inventory con i due host, Credentials per SSH e Vault, Job Template/Workflow per concatenare le fasi.

### PROCEDURA DA TERMINALE

- Ho verificato lo stato del cluster `minikube` e l'ho fatto partire `minikube start`.
- Ho clonato il repository ufficilae di `awx-operator`.
- Ho installo AWX Operator (tag `2.19.1`) su Minikube (driver Docker) con namespace `awx`.
- Ho creato un file di configurazione (Custom Resource AWX) `awx-demo.yml`.
- L'AWX Operator inietta un sidecar (`gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`) per proteggere l'endpoint delle metriche. Quel tag non era più disponibile sul
  registry (`manifest unknown`), causando `ImagePullBackOff` sul pod dell'Operator. Ho semplicemente disattivato il sidecar, dato che per l'esercizio non era
  necessario con `kubectl delete -k config/default`.
- Ho applicato il cluster con Kustomize `kubectl apply -k config/default` e poi separatamente ho applicato il file di configurazione (Custom Resource AWX) con
  `kubectl apply -f awx-demo.yml -n awx` dato che kustomize non permette di referenziare file fuori dall'albero `config/default`
- Ho aspettato che i POD siano andati su (ci ha messo tanto tempo essendo AWX molto grande), e poi una volta recuperata la password admin ho effettuato l'accesso
  alla UI tramite tunnel Minikube (`minikube service awx-demo-service -n awx --url`) lasciando la schermata aperta del del terminale per non far bloccare la sessione.
  
### Configurazione AWX

Ho poi svolto la configurazione di AWX da interfaccia grafica:
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.15.18.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.15.31.png)

### Project

- **Name**: MariaDB Backup Restore
- **Source Control Type**: Git
- **Source Control URL**: repository `formazione_sou_k8s`
- **Source Control Branch**: main

AWX clona l'intero repository, non solo la sottocartella `esercizio_bonus_AWX/mariadb` mentre il path specifico dei playbook lo indicherò poi nel singolo Job Template.

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.16.46.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.16.53.png)

### Inventory

- **Name**: Maria DB Inventory
- **Hosts**: `db-primario` (`ansible_host: 192.168.56.50`), `db-restore`
  (`ansible_host: 192.168.56.51`)
- **Groups**: `db_primario`, `db_restore` (ciascuno con il proprio host),
  raggruppati sotto un gruppo padre **`mariadb`** tramite Related Groups —
  equivalente della sintassi `[mariadb:children]` del file `hosts.ini`
  usato nella Fase 2. Senza questo gruppo padre, i playbook con
  `hosts: mariadb` falliscono con `skipping: no hosts matched`.

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.15.38.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.16.00.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.15.50.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.16.19.png)

### Credentials

- **SSH VM MariaDB** (tipo Machine, username `vagrant`) — chiave privata
  di `db-primario`, resa valida anche per `db-restore` aggiungendo la
  chiave pubblica corrispondente agli `authorized_keys` di quella VM (vedi
  sezione Problemi incontrati)
- **Vault MariaDB** (tipo Vault) — contiene la password del Vault usato
  nella Fase 2 per decifrare `vars/vault.yml`

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2011.16.36.png)

### requirements.yml

File nella **radice del repository** (non nella sottocartella del
progetto) che dichiara le collection Ansible necessarie (i playbooks venivano eseguiti in locale essendo le collection presenti in locale ma in questo caso ho bisogno di un file che AWX deve leggere per installare le collections nell'Execution Environment prima di eseguire i playbooks) :

```yaml
---
collections:
  - name: community.mysql
    version: ">=3.0.0"
```

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
  
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.01.41.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.02.35.png)

- **Popolo database**: database, utente, tabella e dati creati
  correttamente su `db-primario`

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.05.21.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.05.43.png)

- **backup DB**: dump eseguito su `db-primario`

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.06.21.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.06.42.png)

- **restore DB**: fetch + copy + import completati su `db-restore`,
  checksum coerente tra le due istanze

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.07.28.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.07.45.png)

- **backup corrotto restore DB**: `rescued=1` confermato anche in
  esecuzione da AWX — stesso comportamento osservato da CLI nella Fase 2
  (import fallito per violazione PRIMARY KEY, gestito dal blocco
  `rescue`, nessun dato scritto parzialmente)

![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.08.21.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.09.11.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.09.22.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.09.38.png)
![prima parte terminale](awx2/Screenshot%202026-07-17%20alle%2012.09.49.png)
