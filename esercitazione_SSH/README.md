# Esercizio Bonus per sabotare SSH con vari metodi 

## Descrizione

Con questo esercizio ho potuto studiare il funzionamento del demone SSH (`sshd`) attraverso la sua configurazione e i meccanismi di sicurezza documentati nel manuale di sistema (`man sshd_config`, `man sshd`).

- L'obiettivo finale è stato comprendere in profondità come SSH gestisce le connessioni, l'autenticazione e la negoziazione
  crittografica, andando a vedere cosa succede se si applicano configurazioni errate o restrittive per osservarne il
  comportamento.

L'ambiente di lavoro è composto da due VM generate con Vagrant:
- **SSH-rocky9** (`192.168.56.20`) — Rocky Linux 9, OpenSSH 8.x
- **SSH-ubuntu18** (`192.168.56.21`) — Ubuntu 18.04, OpenSSH 7.6
  > Solo di prova, per trovare un algoritmo che non fosse supportato da Rocky Linux 9 e utilizzarlo per generare un errore.

---

## Ambiente

```
formazione_sou_k8s/
└── esercitazione_SSH/
    ├── Vagrantfile              # Rocky Linux 9
    └── esercitazione_SSH_2/
        └── Vagrantfile          # Ubuntu 18.04
```

---

## Metodi utilizzati:

- **1. Blocco per gli indirizzi IP**(`Match Address`)
- **2. Disabilitazione di Tutti i Metodi di Autenticazione**(`PasswordAuthentication` e `PubkeyAuthentication`)
- **3. Conflitto di Porta**(`Port`)
- **4. Incompatibilità Crittografica**(`Ciphers` invcece di `3des`)
- **5. Blocco Connessioni Non Autenticate**(`MaxStartups`)

## Blocco per gli indirizzi IP
La direttiva `Match` in `sshd_config` permette di applicare regole condizionali basate su parametri come l'indirizzo IP del client. Aggiungendo un blocco `Match Address` è possibile negare l'accesso a tutti gli utenti provenienti da un determinato IP.

Per prima cosa come per ogni metodo ho aperto  il file di configurazione:

```bash
sudo nano /etc/ssh/sshd_config
```

Quando un client si connette, sshd legge il file di configurazione e quando incontra un blocco Match, valuta la condizione.

Se la condizione è vera, le direttive contenute nel blocco sovrascrivono quelle globali per quella specifica connessione. Questo avviene dopo che la connessione TCP è già stata stabilita e dopo la negoziazione degli algoritmi crittografici (Fasi 1-4), ma prima dell'autenticazione dell'utente (Fase 5).

**Configurazione applicata:**
In questo caso ho inserito questa configurazione nel file:

```
Match Address 10.0.2.2
    DenyUsers *
```

**Effetto:** La direttiva `DenyUsers *` all'interno del blocco Match dice al server di rifiutare l'autenticazione per qualsiasi utente. 
Il risultato è che la connessione TCP viene accettata, il canale cifrato viene stabilito, ma il server nega l'accesso nella fase di autenticazione.
Il client riceve:

```bash
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```

Per il **ripristino** bisogna semplicemente rimuovere il blocco `Match` da `sshd_config` e riavviare il servizio con 'sudo systemctl restart sshd'.

---

### 2. Disabilitazione di Tutti i Metodi di Autenticazione

SSH supporta diversi metodi di autenticazione (password, chiave pubblica, GSSAPI). Disabilitandoli tutti contemporaneamente, il server non ha più nessun metodo valido da offrire al client.

In questo caso nel file di configurazione `sudo nano /etc/ssh/sshd_config` modifico i metodi di autenticazione `PasswordAutentication` e `PubkeyAuthentication` mettendoci semplicemente `no` per bloccarli.

**Configurazione applicata:**

```bash
PasswordAuthentication no
PubkeyAuthentication no
```
Il server comunica al client quali metodi sono disponibili durante la Fase 5 e se tutti i metodi sono disabilitati, il server non ha nessun meccanismo valido da offrire e rifiuta la connessione immediatamente.
Il client riceverà :

```
Permission denied (gssapi-keyex,gssapi-with-mic)
```
La voce `publickey` che c'era sopra nel primo metodo scompare dalla lista.
Il server non la propone più perché è stata disabilitata a livello globale, non solo per un IP specifico

Per ripristinarlo basta reimpostare `PubkeyAuthentication yes` e riavviarlo.

---

### 3. Conflitto di Porta (`Port`)

La direttiva `Port` specifica su quale porta TCP il demone SSH si mette in ascolto. Se la porta indicata è già occupata da un altro processo, `sshd` non riesce a fare il bind e va in crash all'avvio.

Per fare questo metodo ho avviato inizialmente un server HTTP sulla porta 8080 con `python3 -m http.server 8080 &`. In questo modo ho la porta 22 in ascolto da SSH e la porta 80 da python.
Ora uso la direttiva Port scrivendo `Port 8080` alla fine del file di configurazione 
Se provo ad effettuare il restart con `sudo systemctl restart sshd` ottengo:

```bash
[vagrant@rocky9 ~]$ sudo systemctl restart sshd
Job for sshd.service failed because the control process exited with error code.
See "systemctl status sshd.service" and "journalctl -xeu sshd.service" for details.
```
Il servizio va in blocco con un errore in rosso dato che la porta è gia occupata.

Per il ripristino basta rimuovere `Port 8080` da `sshd_config` e riavviare il servizio.

---

### 4. Incompatibilità Crittografica (`Ciphers` invece di '3des')

SSH deve negoziare un algoritmo di cifratura comune tra client e server.Per procedere, client e server devono trovare **almeno un algoritmo in comune** per ogni categoria. Se non esiste nessun algoritmo comune, la connessione viene interrotta immediatamente — non si arriva mai alla fase di autenticazione.

Avevo provato ad offrire come cifrario '3des' solo che era accettato da Rocky Linux 9 e quindi di conseguenza avvenniva la connessione senza problemi. Allora ho provato a connettere un'altra VM (Ubuntu 18.04), tramite un secondo Vagrantfile, in modo da trovare un cifrario deprecato per la mia Rocky Linux 9.

**Procedura (su Ubuntu 18.04):**

Le versioni moderne di OpenSSH hanno progressivamente rimosso il supporto per algoritmi considerati insicuri. Un algoritmo storico è `Chipers rijndael-cbc@lysator.liu.se` in modalità CBC che è presente in OpenSSH 7.6 (Ubuntu 18.04) ma rimosso nelle versioni successive.
Configurando il server per offrire **solo** questo cifrario, i client moderni non riescono a trovare un algoritmo comune e la connessione fallisce.

Ho verificato la differenza di algoritmi supportati tra Ubuntu 18.04 e il client MacOS con `SSQ -Q cipher` e ho visto che il client MacOs non supportava `Chipers rijndael-cbc@lysator.liu.se`.

Ho aggiunto quindi questa configurazione nel file di configurazione
```
Ciphers rijndael-cbc@lysator.liu.se
```
Andando a connettere il client, esso non riesce a negoziare un cifrario comune con la VM dando come risposta:

```bash
Unable to negotiate with 192.168.56.21 port 22: no matching cipher found.
Their offer: rijndael-cbc@lysator.liu.se
```
In breve il server ha offerto solo `rijndael-cbc@lysator.liu.se`, ma il client non lo supporta.
La connessione viene chiusa prima ancora di stabilire il canale cifrato.

Per ripristinare il tutto, basta eliminare la configurazione aggiunta dal file e utilizzare un cifrario comune a MacOs.

### 5. Blocco Connessioni Non Autenticate (`MaxStartups`)

La direttiva `MaxStartups` controlla quante connessioni TCP non ancora autenticate il server accetta simultaneamente. Impostando il valore a `0`, il server rifiuta immediatamente qualsiasi nuova connessione prima ancora di avviare il processo di autenticazione.

**Configurazione applicata:**

```
MaxStartups 0
```

Ho come effetto che il server è attivo e in ascolto sulla porta 22, ma rifiuta ogni tentativo di connessione a livello di rete:

```bash
ssh: connect to host 192.168.56.20 port 22: Connection refused
```

**Nota:** La sintassi estesa `0:0:0` non era valida sulla mia versione di OpenSSH.

Per il ripristino mi basta rimuovere come al solito `MaxStartups 0` da `sshd_config` e riavviare il servizio.

