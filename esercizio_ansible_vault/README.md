# Esercizio bonus: Ansible Vault

## Scopo

Creare un Vault contenente alcune variabili nel formato `var_name: value`, includerle in un playbook tramite la direttiva `vars_files` e stamparne il valore a video, attivando il prompt della password del Vault al lancio del playbook.

## Struttura del progetto

```
esercizio_ansible_vault/
├── README.md
└── ansible-vault/
    ├── vault_vars.yml       (file cifrato)
    └── vault_playbook.yml
```

### Cos'è Ansible Vault

Ansible Vault è una funzionalità nativa di Ansible che permette di cifrare file interi o singole variabili contenenti dati sensibili (password, chiavi API, token, credenziali). Serve a poter versionare playbook e variabili su repository Git senza esporre segreti in chiaro.

Vault utilizza cifratura simmetrica **AES256** dove la stessa password usata per cifrare serve anche per decifrare. Un file cifrato inizia sempre con un header identificativo:

```
$ANSIBLE_VAULT;1.1;AES256
```

dove `1.1` è la versione del formato e `AES256` è l'algoritmo. Il resto del file è il payload cifrato in esadecimale.

### Eseguo un playbook che usa Vault:

Quando un playbook referenzia un file cifrato tramite `vars_files`, va lanciato fornendo la password del vault:

| Flag | Comportamento |
|---|---|
| `--ask-vault-pass` | Chiede la password interattivamente (prompt) |
| `--vault-password-file <file>` | Legge la password da un file su disco |
| `--vault-id <label>@prompt` | Supporto a più vault con etichette diverse |

Senza uno di questi flag, Ansible fallisce con:
```
ERROR! Attempting to decrypt but no vault secrets found
```

### La direttiva vars_files

`vars_files` è una direttiva di livello play che carica variabili da uno o più file YAML esterni. Funziona identicamente sia con file in chiaro sia cifrati: Ansible rileva automaticamente l'header `$ANSIBLE_VAULT` e decifra al volo usando la password fornita a runtime.

```yaml
vars_files:
  - percorso/al/file_vars.yml
```

## Soluzione

### 1. Creazione del file Vault

```bash
ansible-vault create vault_vars.yml
```

Contenuto inserito (in chiaro nell'editor, cifrato automaticamente al salvataggio):

```yaml
db_user: admin
db_password: Admin123
api_key: abcd1234efgh5678 #ho scritto lettere e numeri a caso tanto per l'esercizio non mi servirà.
```

Verifica del contenuto senza modificarlo:
```bash
ansible-vault view vault_vars.yml
```

### 2. Il playbook

```yaml
---
- name: Esercizio con Ansible Vault
  hosts: localhost #in questo ho messo in local host in quello dopo ho messo rocky9, connessione SSH con una
  macchina creata per un esercizio precedente con vagrant.
  connection: local
  gather_facts: false

  vars_files:
    - vault_vars.yml

  tasks:
    - name: Stampa le variabili contenute nel vault
      debug:
        msg: "Utente: {{ db_user }} | Password: {{ db_password }} | API Key: {{ api_key }}"
```

Note sulla struttura:
- `hosts: localhost` + `connection: local`: il playbook gira in locale, senza connessione SSH.
- `gather_facts: false`: disabilita la raccolta di facts, non mi serve.
- il modulo `debug` con `msg` stampa a video le variabili interpolate che si trovano nel file vault con la
  sintassi Jinja2.

### 3. Esecuzione

```bash
ansible-playbook vault_playbook.yml --ask-vault-pass
```

Output ottenuto:

```
TASK [Stampa le variabili contenute nel vault] ********************
ok: [localhost] => {
    "msg": "Utente: admin | Password: Admin123 | API Key: abcd1234efgh5678"
}
PLAY RECAP **********************************************************
localhost   : ok=1  changed=0  unreachable=0  failed=0  skipped=0
```

- Il dato sensibile resta cifrato su disco (e quindi anche nel repository Git), diventando disponibile in chiaro solo a runtime, dopo l'inserimento della password corretta.
- Non salvare mai la password del vault in chiaro dentro il repository (es. tramite `--vault-password-file` puntato a un file versionato): vanificherebbe lo scopo di Vault. Il file password va tenuto fuori da Git (`.gitignore`) o gestito con un secret manager esterno.
- `vars_files` ha sintassi identica sia per file in chiaro sia cifrati: la decifratura è automatica e trasparente.

