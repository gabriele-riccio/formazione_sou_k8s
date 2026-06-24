# Esercizio Bonus Jenkins — Pipeline Jenkins che esegua una build solo dal lunedì al venerdì

## Obiettivo

Scrivere una pipeline Jenkins che esegua la build solo dal lunedì al venerdì, e che stampi un messaggio di warning (senza eseguire la build) il sabato e la domenica. Vincolo dell'esercizio: il giorno della settimana non deve essere ricavato tramite un comando shell, ma utilizzando l'oggetto `Date` (e la classe `Calendar`) fornito nativamente da Groovy.

## Strumenti utilizzati

- Jenkins (immagine Docker ufficiale `jenkins/jenkins:lts`)
- Docker Desktop (macOS)
- Groovy (sintassi Pipeline dichiarativa)

## Setup dell'ambiente

1. Avvio di Jenkins tramite Docker:
```bash
   docker run -d -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts
```
2. Recupero della password iniziale:
```bash
   docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```
![prima_parte](jenkins/Screenshot%202026-06-18%20alle%2012.25.24.png)

3. Accesso alla dashboard su `http://localhost:8080`, installazione dei plugin consigliati, creazione del primo utente amministratore.
4. Creazione di un nuovo "Item" di tipo **Pipeline**, con definizione "Pipeline script" (script incollato direttamente, senza repository SCM collegato).

![seconda_parte](jenkins/Screenshot%202026-06-18%20alle%2012.40.25.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2012.37.19.png)
![quarta_parte](jenkins/Screenshot%202026-06-18%20alle%2012.37.44.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2012.37.51.png)

## Script principale (`Jenkinsfile`)

```groovy
pipeline {
    agent any

    stages {
        stage('Check del giorno della settimana') {
            steps {
                script {
                    def oggi = new Date()
                    int giornoSettimana = oggi[Calendar.DAY_OF_WEEK]

                    if (giornoSettimana == Calendar.SATURDAY || giornoSettimana == Calendar.SUNDAY) {
                        echo "WARNING: oggi è weekend, la build non verrà eseguita."
                        env.IS_WEEKEND = "true"
                    } else {
                        echo "Oggi è un giorno feriale, procedo con la build."
                        env.IS_WEEKEND = "false"
                    }
                }
            }
        }

        stage('Build') {
            when {
                expression { env.IS_WEEKEND == "false" }
            }
            steps {
                echo "Eseguo la build ..."
            }
        }
    }
}
```

## Svolgimento dello script

La pipeline è scritta in stile **dichiarativo** (`pipeline { ... }`), più leggibile e strutturato rispetto alla sintassi "scripted" pura. Il blocco `agent any` lascia a Jenkins la libertà di scegliere l'esecutore disponibile, dato che per questo esercizio non serve vincolarsi a una macchina specifica. Tutte le fasi della pipeline sono racchiuse in `stages { ... }`, dove ogni fase è uno `stage('nome')`: il nome assegnato è quello che compare nella Stage View di Jenkins, utile per individuare a colpo d'occhio dove si trova (o dove si è interrotta) l'esecuzione.

**Primo stage — calcolo del giorno della settimana.** Dentro `steps`, il blocco `script { ... }` è necessario ogni volta che serve scrivere Groovy "vero" (variabili, condizioni, logica) invece dei soli comandi predefiniti della Pipeline come `echo` o `sh`. Al suo interno, con `def oggi = new Date()` creo un oggetto che rappresenta l'istante esatto di esecuzione. Con la riga successiva, `int giornoSettimana = oggi[Calendar.DAY_OF_WEEK]`, invece sfrutto l'operatore `[]` che Groovy aggiunge alla classe `Date` (equivalente a creare un `Calendar`, fargli `setTime()` e poi chiamare `get()`) per estrarre direttamente il giorno della settimana come numero, da 1 (domenica) a 7 (sabato).

**Il controllo weekend.** Il valore ottenuto l'ho confrontato con le costanti `Calendar.SATURDAY` e `Calendar.SUNDAY`, molto più leggibili dei numeri grezzi (7 e 1). Se è sabato o domenica, viene stampato un messaggio di warning con `echo` e impostata la variabile ambiente true `env.IS_WEEKEND = "true"`; altrimenti viene stampato un messaggio diverso che dice la build verrà effettuata e impostata la variabile d'ambiente `env.IS_WEEKEND = "false"`.

**Secondo stage — build condizionata.** Lo `stage('Build')` ha, prima di `steps`, una direttiva `when { expression { ... } }` dove Jenkins valuta l'espressione (`env.IS_WEEKEND == "false"`) e, solo se è vera, esegue gli step contenuti altrimenti lo stage compare come "skipped" nella vista grafica, senza generare errori.


## Script di prova  (`Jenkinsfile2`)

```groovy
pipeline {
    agent any

    stages {
        stage('Check del giorno della settimana') {
            steps {
                script {
                    def oggi = new Date()
                    int giornoSettimana = oggi[Calendar.DAY_OF_WEEK]

                    if (giornoSettimana == Calendar.THURSDAY) {
                        echo "WARNING: oggi si va da CICCIO's, non verrà eseguita la build."
                        env.IS_WEEKEND = "true"
                    } else {
                        echo "Oggi ho il pranzo, dato che non andiamo da CICCIO's  procedo con la build."
                        env.IS_WEEKEND = "false"
                    }
                }
            }
        }

        stage('Build') {
            when {
                expression { env.IS_WEEKEND == "false" }
            }
            steps {
                echo "Eseguo la build ..."
            }
        }
    }
}
```
### Come funziona
Esattamente come quello sopra, soltanto che dato che oggi è giovedì per non farlo buildare e far vedere la risposta quando siamo nel weekend ho inserito come condizione if (giornoSettimana == Calendar.THURSDAY) in modo che non buildasse.
Ho aggiunto che essendo giovedì, la build non viene effettuata dato che mangiamo da CICCIO's e siamo stanchi.
> Il resto dello script l'ho lasciato identico, dato che è solo una prova.

## OUTPUT Jenkins:

![seconda_parte](jenkins/Screenshot%202026-06-18%20alle%2012.40.25.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2015.00.22.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2015.00.43.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2015.16.11.png)
![terza_parte](jenkins/Screenshot%202026-06-18%20alle%2015.16.35.png)

