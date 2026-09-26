#!/bin/sh
set -eu

namespace="${NAMESPACE:-todolist}"

generate() {
  openssl rand -base64 "$1" | tr -d '\n'
}

decode_base64() {
  base64 -d 2>/dev/null || base64 -D
}

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$namespace" create secret generic todolist-secrets \
  --from-literal=DB_USER=todolist \
  --from-literal=DB_PASSWORD="$(generate 24)" \
  --from-literal=SESSION_KEY="$(generate 36)" \
  --from-literal=ADMIN_USER=admin \
  --from-literal=ADMIN_PASSWORD=admin \
  --from-literal=CLEANUP_TOKEN="$(generate 24)" \
  --dry-run=client -o yaml | kubectl apply -f -

db_password=$(kubectl -n "$namespace" get secret todolist-secrets -o jsonpath='{.data.DB_PASSWORD}' | decode_base64)
kubectl -n "$namespace" create secret generic todolist-db-credentials \
  --from-literal=username=todolist \
  --from-literal=password="$db_password" \
  --dry-run=client -o yaml | kubectl apply -f -

printf 'Local TodoList secrets are present in namespace %s.\n' "$namespace"
