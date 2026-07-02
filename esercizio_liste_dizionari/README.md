# Esercizio Bonus su Liste e Dizionari nei playbook Ansible

## Scopo

Comprensione e utilizzo delle strutture dati complesse (liste e dizionari) all'interno dei playbook Ansible.

## Obiettivo
Una volta studiato come vengono inserite e create liste e dizionari:
- Creare un playbook Ansible che installi/disinstalli una lista di pacchetti in base a quanto definito in un
  apposito dictionary.
- Creare un playbook Ansible che crei una lista di utenti usando le specifiche contenute in una lista di
  dictionary (gruppo, home directory, shell, etc.).

## Struttura del progetto

```
esercizio_liste_dizionari/
├── inventory.ini #dove ho inserito l'ambiente vagrant che ho utilizzato preso da un esercizio precedente.
└── playbooks/
    ├── playbook_pacchetti.yml
    └── playbook_utenti.yml
```

## Teoria

### Liste

Sequenza ordinata di valori, accessibile per indice numerico a partire da 0:

```yaml
vars:
  fruits:
    - banana
    - apple
    - watermelon
```

`{{ fruits[0] }}` → `banana`.
Per iterare in un task si usa `loop`, che rende disponibile l'elemento corrente in `item`:

```yaml
loop: "{{ fruits }}"
```

### Dizionari

Insieme di coppie chiave-valore:

```yaml
vars:
  fruits:
    banana: yellow
    apple: red
```

Accesso con `{{ fruits.banana }}` o `{{ fruits['banana'] }}`.

### Il filtro dict2items

Un dizionario **non può essere iterato direttamente** con `loop` in modo utile, perché `loop` si aspetta una sequenza ordinata, non un insieme di coppie. Il filtro `dict2items` trasforma il dizionario in una lista, dove ogni elemento è un sotto-dizionario con due chiavi fisse: `key` e `value`.

Dal dizionario:
```yaml
packages:
  tree: present
  wget: absent
```

`{{ packages | dict2items }}` produce concettualmente:


```yaml
- key: tree
  value: present
- key: wget
  value: absent
```

Dentro il `loop`, `item` è quindi l'intero sotto-dizionario, e si accede ai campi con `item.key` e `item.value` — **non** con `{{ item }}` da solo (che stamperebbe l'oggetto intero).

### Liste di dizionari

Combinazione delle due strutture, usata per rappresentare più entità con più attributi ciascuna:

```yaml
vars:
  fruits:
    - name: banana
      color: yellow
      price: 2
```

Qui **non serve alcun filtro**: la lista è già nella forma corretta per essere iterata direttamente con `loop: "{{ fruits }}"`, accedendo ai campi con `item.name`, `item.color`, ecc.

## Ambiente e inventory

```ini
[rocky9]
192.168.56.20 ansible_user=vagrant ansible_ssh_private_key_file=/Users/gabrielericciosourcesense/formazione_sou_k8s/esercitazioni_track2/step1/ansible-lab/.vagrant/machines/default/virtualbox/private_key
```

Il percorso della chiave SSH deve essere **assoluto**: un percorso relativo funziona solo se Ansible viene lanciato dalla stessa cartella del Vagrantfile originale(quindi avrei dovuto svolgere l'esercizio nella cartella dello step1 della track2).
Il percorso corretto si ottiene con `vagrant ssh-config` (lanciato dalla cartella del Vagrantfile), leggendo la riga `IdentityFile`.

## Soluzione:

### playbook_pacchetti.yml

```yaml
---
- name: Playbook per le liste dei pacchetti
  hosts: rocky9
  become: true
  vars:
    packages:
      tree: present
      wget: absent

  tasks:
    - name: Installazione o rimozione pacchetti
      ansible.builtin.dnf:
        name: "{{ item.key }}"
        state: "{{ item.value }}"
      loop: "{{ packages | dict2items }}"
```

### playbook_utenti.yml

```yaml
---
- name: Creazione utenti da lista di dizionari
  hosts: rocky9
  become: true
  vars:
    utenti:
      - username: pippo
        group: users
        home: /home/pippo
        shell: /bin/bash
      - username: pluto
        group: users
        home: /home/pluto
        shell: /bin/bash

  tasks:
    - name: Creazione utente
      ansible.builtin.user:
        name: "{{ item.username }}"
        group: "{{ item.group }}"
        home: "{{ item.home }}"
        shell: "{{ item.shell }}"
        state: present
      loop: "{{ utenti }}"
```

### Esecuzione

```bash
# modalità simulata
ansible-playbook -i inventory.ini playbooks/playbook_pacchetti.yml --check
ansible-playbook -i inventory.ini playbooks/playbook_utenti.yml --check

# esecuzione reale
ansible-playbook -i inventory.ini playbooks/playbook_pacchetti.yml
ansible-playbook -i inventory.ini playbooks/playbook_utenti.yml
```

Output ottenuto (entrambi i playbook, esito positivo):
```
PLAY RECAP ***********************************************************
192.168.56.20   : ok=2  changed=1  unreachable=0  failed=0  skipped=0
```


## Note sul modulo user (ansible-doc user)

| Parametro | Significato |
|---|---|
| `name` (obbligatorio, alias `user`) | Nome dell'utente da creare/rimuovere/modificare |
| `group` | Gruppo primario dell'utente |
| `home` | Percorso della home directory |
| `shell` | Shell di login assegnata |
| `state` | `present` (default) o `absent` |

Per i moduli builtin (es. `user`, `dnf`), la forma corta (`user`) e il FQCN (`ansible.builtin.user`) sono equivalenti nel comportamento. Il FQCN è considerato best practice per evitare ambiguità quando sono installate più collection con moduli omonimi.


## Problemi affrontati durante lo svolgimento

### ansible senza pattern host
`ansible -i inventory.ini all -m ping` — manca il pattern host come argomento posizionale. Corretto: `ansible -i inventory.ini all -m ping` (con `all` esplicito).

### Host key SSH cambiata
VM ricreata → nuova chiave host SSH, diversa da quella salvata in `~/.ssh/known_hosts`. Risolto con `ssh-keygen -R <ip>` seguito da accettazione della nuova fingerprint.

### Permission denied — percorso chiave relativo
Lavorando da una cartella diversa da quella del Vagrantfile, il percorso relativo della chiave privata nell'inventory non era più valido. Risolto sostituendolo con il percorso assoluto ottenuto da `vagrant ssh-config`.

### Uso scorretto di item dopo dict2items
`{{ item }}` da solo stampa l'intero oggetto `{key, value}`, non il singolo campo. Verificato stampando prima `item` per intero con un task di debug, poi corretto con `item.key` / `item.value`.



### Repository DNF irraggiungibile (DNS)
Il modulo `dnf` aggiorna i metadati di **tutti** i repository configurati prima di installare qualsiasi pacchetto: un solo repository irraggiungibile (`docker-ce`, poi anche `epel`) blocca l'intera operazione. Diagnosi sulla VM:

```bash
sudo dnf repolist
sudo dnf makecache
```

Errore risultante: `Could not resolve host: download.docker.com` — problema di **risoluzione DNS**, non di connettività di rete (verificato con `ping -c 3 8.8.8.8`, riuscito). Causa: `/etc/resolv.conf` puntava a un nameserver di una rete diversa e non più raggiungibile(mi sono rovinato usando una vm in local sarebbe stato molto più semplice).

Fix temporaneo:
```bash
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
```

**Metodo generale di diagnosi rete su una VM:** prima isolare se il problema è di connettività (ping su IP pubblico noto, bypassa il DNS) o di risoluzione nomi (nslookup/dig su un dominio, dipende dal DNS), poi applicare la soluzione mirata.

