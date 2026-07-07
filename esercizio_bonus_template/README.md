# Template Jinja nei Playbook Ansible

Esercitazione sull'utilizzo dei template Jinja all'interno dei playbook Ansible, con applicazione pratica su due file di configurazione di sistema: `/etc/security/limits.conf` e `/etc/security/access.conf`.

## Traccia:

- Creare un playbook Ansible che aggiunga in append sul file /etc/security/limits.conf alcuni settings per
  un’utente. In ambiente di produzione dobbiamo imporre un numero massimo di file aperti pari a 10000, mentre in
  ambiente di collaudo e sviluppo 1000.
- Supponiamo che in /etc/security/access.conf ci sia un’ultima riga che impedisce l’accesso agli utenti non
  esplicitamente autorizzati (“- : ALL : ALL”). Creare un playbook Ansible che aggiunga una lista di utenti in
  whitelist anteponendosi a tale riga (hint: utilizzare l’opzione insertbefore del modulo blockinfile).
> **Nota:** la traccia originale riporta la riga di deny come `"- : ALL : ALL"` (con spazi). Il formato realmente
> valido per la sintassi di `access.conf` è senza spazi: `-:ALL:ALL`. È stato usato il formato corretto in tutta
> la risoluzione.

## Introduzione teorica sui templates

I template Jinja (https://jinja.palletsprojects.com/en/stable/) sono in grado di generare file dinamicamente utilizzando variabili, costrutti condizionali e cicli. Ansible li utilizza sia per l'espansione delle variabili ovunque nei playbook (`{{ }}`) sia per la generazione di file interi tramite il modulo `template`.

### I tre delimitatori di sintassi

| Sintassi | Ruolo | Esempio |
|---|---|---|
| `{{ ... }}` | Output — stampa un'espressione | `{{ nome_utente }}` |
| `{% ... %}` | Statement — logica di controllo (if, for, set...) | `{% if ambiente == 'produzione' %}` |
| `{# ... #}` | Commento — non finisce nell'output | `{# nota interna #}` |

### If / elif / else

```jinja2
{% if fruit in [ 'ananas', 'avocado' ] %}
Tropical
{% elif fruit == 'hazelnut' %}
Dried fruit
{% endif %}
```

### Cicli for

```jinja2
{% for i in range(1,10) %}
  <p>Number {{i}}</p>
{% endfor %}
```

### Integrazione con Ansible: modulo template

```yaml
- name: Creazione nuovo file da template
  ansible.builtin.template:
    src: /tmp/mytemplate.j2
    dest: /tmp/output.txt
  delegate_to: localhost
```

Il file viene depositato sull'host dove viene eseguito il task. Le variabili nel template sono quelle disponibili nel contesto del playbook (definite in `vars`, `group_vars`/`host_vars`, o passate da linea di comando con `--extra-vars`).

### Iniezione del contenuto con blockinfile

Il contenuto generato dal template può popolare un file su un host target tramite `blockinfile`, leggendo il file intermedio con `lookup`:

```yaml
- name: append block to file
  ansible.builtin.blockinfile:
    path: /home/myfile.txt
    block: "{{ lookup('ansible.builtin.file', '/tmp/output.txt') }}"
    insertafter: EOF
    create: yes
```

**Punto fondamentale:** `blockinfile` non esegue il rendering Jinja del parametro `block`. Se il contenuto dipende da variabili o logica dinamica, va prima generato con `template` (che fa il rendering) e solo dopo letto con `lookup('ansible.builtin.file', ...)`.

I marcatori automatici `# BEGIN ANSIBLE MANAGED BLOCK` / `# END ANSIBLE MANAGED BLOCK` rendono l'operazione idempotente: rilanciando il playbook, il blocco esistente viene riconosciuto e aggiornato, non duplicato.

## Ambiente utilizzato

- **Host di controllo:** MacBook Pro 2017 (Intel), macOS Ventura 13.7.8
- **Virtualizzazione:** VirtualBox + Vagrant
- **VM target:** Rocky Linux 9 (box `generic/rocky9`), IP privato statico `192.168.56.40`
- **Ansible:** eseguito dal Mac verso la VM via SSH

## Struttura del progetto

```
jinja-lab/
├── Vagrantfile
├── inventory/
│   └── host.ini
├── templates/
│   ├── limits.conf.j2
│   └── access_whitelist.j2
├── limits_playbook.yml
└── access_playbook.yml
```

## Preparazione dell'ambiente

### Vagrantfile

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/rocky9"
  config.vm.hostname = "jinja-lab"

  config.vm.network "private_network", ip: "192.168.56.40"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "jinja-lab-rocky9"
    vb.memory = "1024"
    vb.cpus = 1
  end
end
```

Ho assegnato un IP statico (`192.168.56.40`) per avere un target di rete prevedibile. Il nome della VM l'ho impostato esplicitamente con `vb.name` per evitare conflitti con altre VM già registrate in VirtualBox.

Avvio:

```bash
vagrant up
```

### Inventory Ansible

Il percorso della chiave privata SSH generata da Vagrant lo recupero con:

```bash
vagrant ssh-config
```

Copiare il valore di `IdentityFile` (percorso assoluto) nell'inventory/host.ini:

```ini
[jinjalab]
jinja-lab ansible_host=192.168.56.40 ansible_user=vagrant ansible_private_key_file= /percorso...

[jinjalab:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```
ho inserito anche il gruppo jinjalab:vars per le variabili per 

Verifica connettività:

```bash
ansible -i inventory/host.ini jinjalab -m ping
```

Output atteso:

```
jinja-lab | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

## Punto 1 — limits.conf parametrico per ambiente

### Obiettivo

Generare le direttive per `/etc/security/limits.conf` con un limite `nofile` (numero massimo di file aperti) che varia in base a una variabile `ambiente`: 10000 in produzione, 1000 in collaudo/sviluppo.

### Template — `templates/limits.conf.j2`

```jinja2
{% if ambiente == 'produzione' %}
{{ nome_utente }} hard nofile 10000
{{ nome_utente }} soft nofile 10000
{% elif ambiente in ['collaudo', 'sviluppo'] %}
{{ nome_utente }} hard nofile 1000
{{ nome_utente }} soft nofile 1000
{% else %}
{{ nome_utente }} hard nofile 512
{{ nome_utente }} soft nofile 512
{% endif %}
```

- `hard` è il limite massimo invalicabile (solo root può alzarlo).
- `soft` è il limite di default della sessione, modificabile dall'utente entro il tetto di `hard`.
- Il ramo `else` è un fallback prudenziale per un ambiente non riconosciuto.

### Playbook — `limits_playbook.yml`

```yaml
---
- name: Genera limits.conf da template
  hosts: localhost
  gather_facts: no
  vars:
    nome_utente: "appuser"
    ambiente: "produzione"
  tasks:
    - name: Creazione file temporaneo da template
      ansible.builtin.template:
        src: templates/limits.conf.j2
        dest: /tmp/limits_output.txt

- name: Applica limits.conf sul target
  hosts: jinjalab
  gather_facts: no
  tasks:
    - name: Append blocco a /etc/security/limits.conf
      ansible.builtin.blockinfile:
        path: /etc/security/limits.conf
        block: "{{ lookup('ansible.builtin.file', '/tmp/limits_output.txt') }}"
        insertafter: EOF
        create: yes
      become: yes
```

**Spiegazione:**

- Primo play (`hosts: localhost`): eseguito sulla macchina di controllo. Rende il template con le variabili definite in `vars` e scrive il risultato in `/tmp/limits_output.txt` sulla macchina locale.
- Secondo play (`hosts: jinjalab`): eseguito sulla VM target. Legge il file generato dal primo play tramite `lookup('ansible.builtin.file', ...)` e lo inietta in `/etc/security/limits.conf` con `blockinfile`.
- `insertafter: EOF` posiziona il blocco alla fine del file.
- `create: yes` crea il file se non esiste.
- `become: yes` è necessario perché modificare `/etc/security/limits.conf` richiede privilegi root.

### Esecuzione

> **Nota:** `--check` (dry-run) non funziona su questo playbook. Il primo play simula la scrittura del file temporaneo senza crearlo realmente su disco; il secondo play, che cerca di leggerlo, fallisce con `file not found`. Va eseguito il playbook realmente (con `--diff` per vedere le modifiche).

```bash
ansible-playbook -i inventory/host.ini limits_playbook.yml --diff
```

Risultato (estratto):

```diff
+# BEGIN ANSIBLE MANAGED BLOCK
+appuser hard nofile 10000
+appuser soft nofile 10000
+# END ANSIBLE MANAGED BLOCK
changed: [jinja-lab]
```

### Verifica idempotenza

Rilanciando lo stesso playbook senza modifiche: `changed=0` su entrambi i play — `blockinfile` riconosce che il contenuto è identico.

Cambiando `ambiente: "sviluppo"` nel playbook: il blocco esistente viene **sovrascritto** (non duplicato) con `nofile 1000`, grazie ai marcatori BEGIN/END.

## Punto 2 — whitelist utenti in access.conf

### Obiettivo

Autorizzare esplicitamente una lista di utenti in `/etc/security/access.conf`, inserendo le relative righe **prima** della riga che nega l'accesso a tutti gli altri (`-:ALL:ALL`).

> `access.conf` viene valutato riga per riga da `pam_access`: la prima riga che fa match determina l'esito. La whitelist deve quindi trovarsi prima della regola generale di deny, altrimenti quest'ultima verrebbe applicata per prima e la whitelist non avrebbe mai effetto.

### Verifica preliminare

Il file esisteva già di default, ma la riga di deny globale era commentata:

```
# All other users should be denied to get access from all sources.
#-:ALL:ALL
```

Poiché la traccia presuppone che questa riga sia già attiva, è stata aggiunta realmente (non commentata) in fondo al file, come step di preparazione (non parte del playbook finale):

```bash
ansible -i inventory/host.ini jinjalab -b -m lineinfile -a \
  "path=/etc/security/access.conf line='-:ALL:ALL' insertafter=EOF"
```

Risultato:

```
# All other users should be denied to get access from all sources.
#-:ALL:ALL
-:ALL:ALL
```

### Template — `templates/access_whitelist.j2`

```jinja2
{% for utente in utenti_whitelist %}
+:{{ utente }}:ALL
{% endfor %}
```

Sintassi di `access.conf`: `<permesso>:<utente/gruppo>:<origine>`, dove `+` = permit, `-` = deny, `ALL` come origine = da qualsiasi provenienza.

### Playbook — `access_playbook.yml`

```yaml
---
- name: Genera whitelist da template
  hosts: localhost
  gather_facts: no
  vars:
    utenti_whitelist:
      - alice
      - bob
      - carlo
  tasks:
    - name: Creazione file temporaneo da template
      ansible.builtin.template:
        src: templates/access_whitelist.j2
        dest: /tmp/access_whitelist.txt

- name: Applica whitelist sul target
  hosts: jinjalab
  gather_facts: no
  tasks:
    - name: Inserisci whitelist prima della riga di deny globale
      ansible.builtin.blockinfile:
        path: /etc/security/access.conf
        block: "{{ lookup('ansible.builtin.file', '/tmp/access_whitelist.txt') }}"
        insertbefore: '^-:ALL:ALL$'
        create: yes
      become: yes
```

**Spiegazione:**

- `utenti_whitelist` è una lista Ansible; il ciclo `for` nel template genera una riga per ciascun elemento, indipendentemente dalla lunghezza della lista.
- `insertbefore: '^-:ALL:ALL$'` è una regex ancorata (`^` e `$`) che identifica esattamente la riga attiva `-:ALL:ALL`, senza confonderla con la riga commentata `#-:ALL:ALL` (che inizia con `#`, non con `-`).
- Se `insertbefore` non trova corrispondenze, `blockinfile` si comporta come `insertafter: EOF` di default: per questo è importante aver verificato prima che la riga target esista nella forma esatta attesa.

### Esecuzione

```bash
ansible-playbook -i inventory/host.ini access_playbook.yml --diff
```

Risultato finale nel file:

```
# All other users should be denied to get access from all sources.
#-:ALL:ALL
+:alice:ALL
+:bob:ALL
+:carlo:ALL
-:ALL:ALL
```

Le regole di permit precedono la regola generale di deny: `pam_access` autorizzerà alice, bob e carlo; qualsiasi altro utente verrà negato dalla riga finale. Rilanciando il playbook senza modifiche: `changed=0` su entrambi i play (idempotenza confermata).





---

*Documentazione realizzata nell'ambito della DevOps Academy di Sourcesense — repository `formazione_sou_k8s`.*
