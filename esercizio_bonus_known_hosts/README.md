# Esercizio Bonus — Verifica del Cambio Fingerprint SSH

## Scopo

Verificare concretamente cosa succede quando la fingerprint SSH di una VM cambia, con `host_key_checking` di Ansible prima attivo (comportamento di default) e poi disattivato.

## Struttura del progetto

```
esercizio_bonus_known_hosts/
├── README.md
├── Vagrantfile
├── ansible.cfg
├── inventory/
|   └── host.ini
└── playbooks/
    └── playbook.yml
```

## Teoria

### Il meccanismo delle host key SSH

Ogni server SSH possiede una coppia di chiavi crittografiche univoche (host key), generate al primo avvio del servizio `sshd`. Al primo collegamento, il client SSH salva la chiave pubblica del server in `~/.ssh/known_hosts`, associata all'indirizzo usato.

Ad ogni connessione successiva, il client confronta la chiave presentata con quella salvata:
- se coincidono, la connessione prosegue senza chiedere nulla.
- se sono diverse, SSH blocca la connessione per proteggere da un possibile attacco `man-in-the-middle`.

### Quando cambia la fingerprint di una VM Vagrant?

La fingerprint cambia legittimamente quando la VM viene **ricreata** (`vagrant destroy` + `vagrant up`): il sistema operativo genera nuove host key al primo avvio, anche se l'IP resta lo stesso. Comandi come `halt`/`up`, `reload` o `suspend`/`resume` invece **non** la cambiano, perché riutilizzano lo stesso disco.

Lo stesso effetto si può simulare senza distruggere l'intera VM, rigenerando manualmente le chiavi:

```bash
sudo rm /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo systemctl restart sshd
```

`ssh-keygen -A` genera tutte le host key mancanti per il server SSH, senza sovrascrivere quelle che ci sono già.
Se elimino quelle che ci sono già con `sudo rm /etc/ssh/ssh_host_*` allora `ssh-keygen -A` non trova più nulla e le rigenera tutte da zero, ottenendo chiavi diverse dalle precedenti, quindi una fingerprint diversa. 

### host_key_checking in Ansible

E' un opzione in `ansible.cfg` nella sezione `[defaults]`:

| Valore | Comportamento |
|---|---|
| `True` (default) | Ansible verifica la fingerprint contro `known_hosts`. Se diversa, blocca l'esecuzione. |
| `False` | Ansible ignora il controllo, si connette senza verificare, senza prompt né avviso. |

`False` è como con gli esercizi (soprattutto con VM ricreate spesso), ma va evitato contro host remoti reali o in produzione, perché rimuove una protezione di sicurezza effettiva.

### ssh-keygen -R

```bash
ssh-keygen -R <indirizzo_ip>
```

Rimuove da `known_hosts` tutte le righe associate a quell'indirizzo (salvando `known_hosts.old` come backup). La connessione successiva viene trattata come nuova: SSH chiede conferma della nuova fingerprint e la salva pulita.

## Procedura
Genero il **Vagrantfile**, l'**inventory** e il **playbook**

### Vagrantfile

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/rocky9"
  config.vm.hostname = "rocky99"
  config.vm.network "private_network", ip: "192.168.56.30"
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "rocky99"
    vb.memory = 1024
    vb.cpus   = 1
  end
end
```

### inventory.ini

```ini
[rocky9]
192.168.56.30 ansible_user=vagrant ansible_ssh_private_key_file=/Users/gabrielericciosourcesense/formazione_sou_k8s/formazione_sou_k8s/esercizio_bonus_known_hosts/.vagrant/machines/default/virtualbox/private_key

```

Il percorso della chiave  lo ottengo con `vagrant ssh-config` (dalla cartella del Vagrantfile), leggendo `IdentityFile`. Deve essere assoluto, non relativo.

### ansible.cfg (fase iniziale, controllo con true)

```ini
[defaults]
inventory = inventory.ini
host_key_checking = True
```

### playbooks/playbook.yml

```yaml
---
- name: Test di connettività SSH
  hosts: rocky9
  gather_facts: false
  tasks:
    - name: Ping della VM
      ansible.builtin.ping:
```

### Fase 1 — Primo collegamento

```bash
ansible-playbook playbooks/playbook.yml
```
Confermo la fingerprint (`yes`), verifico l'esito (`pong`).

### Fase 2 — Simulo il cambio di fingerprint(con quello scritto sopra)

```bash
vagrant ssh
sudo rm /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo systemctl restart sshd
exit
```

### Fase 3 — Osservo il blocco (host_key_checking = True)

```bash
ansible-playbook playbooks/playbook.yml
```
Ottengo: `REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key verification failed`.

### Fase 4 — Pulisco e riconfermo

```bash
ssh-keygen -R 192.168.56.30
ansible-playbook playbooks/playbook.yml
```
Atteso: richiesta di conferma (`yes`), poi successo.

### Fase 5 — Ripeto il cambio con host_key_checking disattivato( host_key_checking = False)

Ripeti la Fase 2, poi modifica `ansible.cfg`:
```ini
[defaults]
inventory = inventory.ini
host_key_checking = False
```
```bash
ansible-playbook playbooks/ping_test.yml
```
Atteso: nessun blocco, nessun avviso, connessione diretta nonostante `known_hosts` contenga ancora la fingerprint vecchia.

## Riepilogo esiti attesi

| Fase | host_key_checking | known_hosts pulito? | Risultato atteso |
|---|---|---|---|
| 3 | True (default) | No | Blocco, errore fingerprint |
| 4 | True (default) | Sì (ssh-keygen -R) | Funziona, richiede conferma yes |
| 5 | False | No | Funziona subito, nessun avviso |

