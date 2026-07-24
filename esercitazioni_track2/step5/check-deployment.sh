#!/usr/bin/env bash

# Esporto un deployment autendicandomi come ServiceAccount "cluster-reader"
# con wrapping di kubectl e verifico se sono presenti: 
# readinessProbe, livenessProbe, resources.requests, resources.limits

# Uso: ./check-deployment.sh dopo averlo reso eseguibile
# Exit code: 0 conforme , 1 non conforme , 2 errore 

set -euo pipefail

# 1) Dichiaro le variabili che mi rappresentano i parametri
NAMESPACE="${NAMESPACE:-formazione-sou}"
DEPLOYMENT="${1:-flask-app-example}"
SA="${SA:-cluster-reader}"
TOKEN_TTL="${TOKEN_TTL:-10m}"
OUTDIR="${OUTDIR:-./export}"

command -v kubectl >/dev/null 2>&1 || { echo "ERRORE: kubectl non trovato."; exit 2; }
command -v jq      >/dev/null 2>&1 || { echo "ERRORE: jq non trovato."; exit 2; }

# 2) Dichiaro le credenziali del ServiceAccount
APISERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CACERT="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')"

if ! TOKEN="$(kubectl create token "$SA" -n "$NAMESPACE" --duration="$TOKEN_TTL" 2>/dev/null)"; then
  echo "ERRORE: impossibile generare il token per il ServiceAccount '${SA}' in '${NAMESPACE}'."
  exit 2
fi

# 3) Faccio generare il kubeconfig effimero con SOLO token, niente client certificate
KCFG="$(mktemp "${TMPDIR:-/tmp}/kubeconfig-sa.XXXXXX")"
ERRLOG="$(mktemp "${TMPDIR:-/tmp}/kubectl-err.XXXXXX")"
chmod 600 "$KCFG"
trap 'rm -f "$KCFG" "$ERRLOG"' EXIT INT TERM

kubectl --kubeconfig="$KCFG" config set-cluster sa-cluster \
  --server="$APISERVER" --certificate-authority="$CACERT" --embed-certs=true >/dev/null
kubectl --kubeconfig="$KCFG" config set-credentials "$SA" --token="$TOKEN" >/dev/null
kubectl --kubeconfig="$KCFG" config set-context sa \
  --cluster=sa-cluster --user="$SA" --namespace="$NAMESPACE" >/dev/null
kubectl --kubeconfig="$KCFG" config use-context sa >/dev/null
unset TOKEN

WHOAMI="$(kubectl --kubeconfig="$KCFG" auth whoami \
            -o jsonpath='{.status.userInfo.username}' 2>/dev/null || echo 'n/d')"
echo "API server : ${APISERVER}" 
echo "Identità   : ${WHOAMI}"

# 4a) Export del Deployment
mkdir -p "$OUTDIR"
OUT="${OUTDIR}/${DEPLOYMENT}.json"

if ! kubectl --kubeconfig="$KCFG" get deployment "$DEPLOYMENT" -o json > "$OUT" 2>"$ERRLOG"; then
  echo "ERRORE durante l'export del Deployment '${DEPLOYMENT}':"
  sed 's/^/ /' "$ERRLOG"
  exit 2
fi
echo "Export     : ${OUT}"

# 4b) Validazione best practices
# Per ogni container emette righe "container|attributo_mancante".
# In jq l'accesso a un campo di null restituisce null senza errore, quindi
# .resources.requests.cpu funziona anche se .resources non e' definito.
# shellcheck disable=SC2016  # $c e \(...) sono sintassi jq, non Bash
JQ_RULES='
.spec.template.spec.containers[]
| .name as $c
| [
    (if .readinessProbe            == null then "readinessProbe"            else empty end),
    (if .livenessProbe             == null then "livenessProbe"             else empty end),
    (if .resources.requests.cpu    == null then "resources.requests.cpu"    else empty end),
    (if .resources.requests.memory == null then "resources.requests.memory" else empty end),
    (if .resources.limits.cpu      == null then "resources.limits.cpu"      else empty end),
    (if .resources.limits.memory   == null then "resources.limits.memory"   else empty end)
  ][]
| "\($c)|\(.)"
'

echo
echo "=== Check best practices: Deployment '${DEPLOYMENT}' ==="

VIOLATIONS="$(jq -r "$JQ_RULES" "$OUT")"

if [[ -z "$VIOLATIONS" ]]; then
  echo "OK - tutti i container definiscono probe, requests e limits."
  exit 0
fi

COUNT="$(printf '%s\n' "$VIOLATIONS" | wc -l | tr -d ' ')"
echo "ERRORE - ${COUNT} attributi obbligatori mancanti:"
while IFS='|' read -r container attr; do
  printf '  [%-16s] manca: %s\n' "$container" "$attr"
done <<< "$VIOLATIONS"

exit 1
