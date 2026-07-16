# Esercizio bonus — MariaDB Backup & Restore

Esercizio assegnato: creazione di un'istanza MariaDB, popolamento con dati di
test, backup, restore su una VM diversa, verifica di consistenza. Orchestrato
poi con Ansible + Vault, e infine integrato in AWX.

Questo documento copre le prime due fasi dell'esercizio:

- **Fase 1** — procedura eseguita interamente a mano, propedeutica alla
  scrittura dei playbook Ansible
- **Fase 2** — lo stesso flusso orchestrato con playbook Ansible, credenziali
  del database cifrate in Ansible Vault

La Fase 3 (esecuzione dei playbook tramite AWX) sarà documentata a parte una
volta completata.

---

## Fase 1 — Procedura manuale

### Architettura

Due VM Rocky Linux 9, create con Vagrant + VirtualBox, in rete private
host-only:

| VM | Ruolo | IP |
|---|---|---|
| `db-primario` | Istanza sorgente | `192.168.56.50` |
| `db-restore` | Istanza destinazione | `192.168.56.51` |

Il trasferimento del backup avviene passando dal control node (Mac), non
tra le due VM direttamente — coerente con il modello agentless di Ansible
che orchestrerà questo flusso nella Fase 2.

### 1. Provisioning delle VM

```bash
vagrant up
```

Vagrantfile multi-machine con due blocchi `config.vm.define`
(`db-primario`, `db-restore`), box `generic/rocky9`, 1024MB RAM / 1 CPU
ciascuna.

Verifica raggiungibilità:

```bash
vagrant status
ping -c 2 192.168.56.50
ping -c 2 192.168.56.51
```

### 2. Installazione e hardening MariaDB (su entrambe le VM)

```bash
sudo dnf install -y mariadb-server
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo mariadb-secure-installation
```

Durante `mariadb-secure-installation`:
- password vuota iniziale → invio
- `unix_socket authentication` → **n** (serve autenticazione utente/password classica per Ansible/AWX)
- password root → impostata (cifrata poi in Ansible Vault nella Fase 2)
- utenti anonimi → rimossi
- login root remoto → disabilitato
- database `test` → rimosso

Verifica servizio attivo:

```bash
sudo systemctl status mariadb   # Active: active (running)
```

### 3. Creazione DB, utente applicativo e dati di test (`db-primario`)

```sql
CREATE DATABASE appdb;
CREATE USER 'app_user'@'%' IDENTIFIED BY '<PASSWORD_APP_USER>';
GRANT ALL PRIVILEGES ON appdb.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
```

> Nota: `'app_user'@'%'` permette connessioni da qualsiasi host, necessario
> per l'accesso futuro da Ansible/AWX (non solo `localhost`).

Tabella e dati di test:

```sql
CREATE TABLE utenti_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    data_creazione TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO utenti_test (nome, email) VALUES
('Mario Rossi', 'mario.rossi@test.it'),
('Luca Bianchi', 'luca.bianchi@test.it'),
('Anna Verdi', 'anna.verdi@test.it'),
('Giulia Neri', 'giulia.neri@test.it'),
('Paolo Gialli', 'paolo.gialli@test.it');
```

Risultato: 5 righe in `appdb.utenti_test`.

### 4. Backup logico (`db-primario`)

```bash
mysqldump -u root -p --single-transaction --routines --triggers appdb > /tmp/backup_appdb.sql
```

`--single-transaction` garantisce un dump coerente su storage engine InnoDB
senza bloccare le scritture concorrenti (MVCC), a differenza del vecchio
`--lock-tables`.

Verifica contenuto:

```bash
ls -lh /tmp/backup_appdb.sql          # 2.5K
grep INSERT /tmp/backup_appdb.sql     # conferma i 5 utenti presenti
```

### 5. Trasferimento del backup (control node → VM)

```bash
vagrant plugin install vagrant-scp   # una tantum

vagrant scp db-primario:/tmp/backup_appdb.sql ./backup_appdb.sql
vagrant scp ./backup_appdb.sql db-restore:/tmp/backup_appdb.sql
```

### 6. Setup DB/utente e restore (`db-restore`)

Database e utente vuoti (il restore ripristina solo tabelle/dati, non il
contenitore DB né l'utente):

```sql
CREATE DATABASE appdb;
CREATE USER 'app_user'@'%' IDENTIFIED BY '<PASSWORD_APP_USER>';
GRANT ALL PRIVILEGES ON appdb.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
```

Restore:

```bash
mysql -u root -p appdb < /tmp/backup_appdb.sql
```

### 7. Verifica consistenza dati

Confronto diretto:

```bash
mysql -u root -p -e "SELECT * FROM appdb.utenti_test;"
```

→ 5 righe identiche (stessi id, email, timestamp) su entrambe le VM.

Verifica formale con checksum:

```bash
mysql -u root -p -e "CHECKSUM TABLE appdb.utenti_test;"
```

| VM | Checksum |
|---|---|
| `db-primario` | `2247960139` |
| `db-restore` | `2247960139` |

**Checksum identico → consistenza dati confermata.**

### Esito Fase 1

| Punto traccia | Stato |
|---|---|
| 1. MariaDB + dati di test | ✅ |
| 2. Backup del DB | ✅ |
| 3. Restore su altra VM | ✅ |
| 4. Verifica consistenza | ✅ |

### Prossimi passi

- **Fase 2**: traduzione del flusso in playbook Ansible (`community.mysql.mysql_db`),
  credenziali DB in `vars/vault.yml` cifrato con Ansible Vault
- **Fase 3**: esecuzione dei playbook tramite AWX (Project, Inventory a due
  host, Credentials, Job Template/Workflow)


---

## Fase 2 — Ansible + Vault

Fase 2 dell'esercizio: lo stesso flusso già eseguito a mano nella Fase 1
(vedi `README.md` della cartella, sezione Fase 1) orchestrato tramite
playbook Ansible, con le credenziali del database cifrate in Ansible Vault.

### Struttura del progetto

```
mariadb/
├── Vagrantfile
├── ansible.cfg
├── .vault_pass              # password del Vault (NON versionato, in .gitignore)
├── inventory/
│   └── hosts.ini
├── vars/
│   ├── main.yml              # variabili non sensibili
│   └── vault.yml             # credenziali cifrate con Ansible Vault
└── playbooks/
    ├── installazione_mariadb.yml
    ├── popolo_database.yml
    ├── backup.yml
    └── restore.yml
```

### Configurazione

`ansible.cfg`:

```ini
[defaults]
inventory = inventory/hosts.ini
host_key_checking = False
vault_password_file = .vault_pass
```

`inventory/hosts.ini` — due gruppi (`db_primario`, `db_restore`) raggruppati
sotto `mariadb` per i task comuni:

```ini
[db_primario]
db-primario ansible_host=192.168.56.50

[db_restore]
db-restore ansible_host=192.168.56.51

[mariadb:children]
db_primario
db_restore

[mariadb:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=.vagrant/machines/{{ inventory_hostname }}/virtualbox/private_key
```

### Ansible Vault

Le credenziali del database (utente applicativo, password utente, password
root) sono cifrate in `vars/vault.yml`:

```bash
ansible-vault create vars/vault.yml
```

Contenuto (in chiaro, prima della cifratura):

```yaml
db_user: app_user
db_password: "<password_app_user>"
db_root_password: "<password_root>"
```

> Nota: la stessa coppia di credenziali (utente app + root) è condivisa tra
> `db-primario` e `db-restore` — le password sulle due VM sono state
> allineate manualmente prima di scrivere i playbook, così un unico Vault
> vale per entrambe le istanze.

Il file `.vault_pass` (password per cifrare/decifrare il Vault) **non è
versionato** — presente in `.gitignore`.

### 1. Installazione MariaDB (entrambe le VM)

`playbooks/installazione_mariadb.yml` — installa `mariadb-server` e
`python3-PyMySQL` (dipendenza dei moduli `community.mysql.*`), avvia e
abilita il servizio.

```bash
ansible-playbook playbooks/installazione_mariadb.yml
```

Idempotente: rilanciato più volte, `changed=0` dal secondo run in poi.

### 2. Creazione DB, utente e dati di test (solo db-primario)

`playbooks/popolo_database.yml` — crea database, utente applicativo
(`community.mysql.mysql_user`), tabella `utenti_test` con vincolo
**UNIQUE su email**, e inserisce i dati di test con `INSERT IGNORE`.

```bash
ansible-playbook playbooks/popolo_database.yml
```

Il vincolo `UNIQUE` + `INSERT IGNORE` garantisce idempotenza reale sui
dati: run ripetuti non producono righe duplicate (verificato: 5 righe
prima e dopo un secondo run).

> Nota tecnica: il task di creazione tabella e quello di inserimento dati
> usano `community.mysql.mysql_query`, un modulo non dichiarativo che
> segna sempre `changed: true` se la query va a buon fine, anche quando
> non modifica nulla (a differenza di `mysql_db`/`mysql_user`, che sono
> idempotenti anche a livello di stato riportato).

### 3. Backup (solo db-primario)

`playbooks/backup.yml` — dump con `community.mysql.mysql_db` e
`state: dump`, equivalente Ansible di `mysqldump`.

```bash
ansible-playbook playbooks/backup.yml
```

Sempre `changed` a ogni run: corretto, un dump riflette per definizione lo
stato corrente del database, non è un'operazione idempotente per natura.

### 4. Restore (fetch da db-primario, import su db-restore)

`playbooks/restore.yml` — due play nello stesso file:

1. Su `db_primario`: `fetch` del dump verso il control node (`flat: true`
   per evitare la sottocartella con il nome host)
2. Su `db_restore`: `copy` del dump sulla VM, creazione DB/utente se
   mancanti, `mysql_db` con `state: import` per il restore

```bash
ansible-playbook playbooks/restore.yml
```

### Verifica di consistenza

```bash
mysql -u root -p -e "CHECKSUM TABLE appdb.utenti_test;"
```

Eseguito su entrambe le VM dopo il flusso Ansible completo: checksum
identico (`150684391`) — consistenza dei dati confermata end-to-end,
questa volta orchestrata interamente da Ansible.

### Problemi incontrati e risolti

- **Password root disallineate tra le due VM**: il Vault contiene un'unica
  `db_root_password`, ma la password di root era stata impostata in modo
  diverso su `db-restore` durante l'hardening manuale della Fase 1.
  Risolto allineando manualmente la password di root su `db-restore` a
  quella presente nel Vault, prima di eseguire `restore.yml`.
- **Tabella senza vincolo UNIQUE**: la tabella creata a mano nella Fase 1
  non aveva il vincolo `UNIQUE` su `email`. Il primo run del playbook
  `popolo_database.yml` ha quindi duplicato le righe (`INSERT IGNORE` non
  aveva nulla da ignorare). Risolto con backup di sicurezza della tabella
  (`mysqldump` della sola tabella), `DROP TABLE` e rilancio del playbook,
  che ricrea la tabella con il vincolo corretto.

### Esito Fase 2

| Punto traccia | Descrizione | Stato |
|---|---|---|
| 4 | Orchestrazione con Ansible + credenziali in Vault | ✅ |

### Prossimi passi

**Fase 3**: esecuzione dei playbook di questa Fase 2 tramite AWX — Project
puntato al repository, Inventory con i due host, Credentials per SSH e
Vault, Job Template/Workflow per concatenare le fasi.
