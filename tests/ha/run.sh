#!/bin/sh
set -eu

namespace="${NAMESPACE:-todolist}"
deployment="${DEPLOYMENT:-todolist-todolist}"
cluster_name="${CLUSTER_NAME:-todolist-demo}"
health_url="${HEALTH_URL:-http://todolist.localhost/healthz}"
output_dir="evidence/generated/ha-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output_dir"

application_pods() {
  for pod in $(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=todolist -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
    owner=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}')
    phase=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.status.phase}')
    if [ "$owner" = "ReplicaSet" ] && [ "$phase" = "Running" ]; then
      printf '%s\n' "$pod"
    fi
  done
}

probe() {
  while :; do
    started=$(date -u +%s)
    status=$(curl --connect-timeout 1 --max-time 1 --silent --output /dev/null --write-out '%{http_code}' "$health_url" || true)
    printf '%s %s %s\n' "$started" "$(date -u +%FT%TZ)" "$status" >>"$output_dir/health.log"
    sleep 1
  done
}

probe &
probe_pid=$!
cleanup() {
  kill "$probe_pid" 2>/dev/null || true
  if [ -n "${stopped_worker:-}" ]; then
    docker start "$stopped_worker" >/dev/null 2>&1 || true
    kubectl wait --for=condition=Ready "node/$worker" --timeout=120s >"$output_dir/worker-recovery.txt" 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=180s
kubectl rollout restart "deployment/$deployment" -n "$namespace"
kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=180s

set -- $(application_pods)
[ "$#" -gt 0 ] || { printf 'No running application Pods were found.\n' >&2; exit 1; }
kubectl delete pod -n "$namespace" "$1" --wait=false
kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=180s

primary_pod=$(kubectl get cluster/todolist-db -n "$namespace" -o jsonpath='{.status.currentPrimary}')
[ -n "$primary_pod" ] || { printf 'CloudNativePG has no current primary.\n' >&2; exit 1; }
primary_node=$(kubectl get pod -n "$namespace" "$primary_pod" -o jsonpath='{.spec.nodeName}')
[ -n "$primary_node" ] || { printf 'Could not determine the primary database node.\n' >&2; exit 1; }

worker=""
for pod in $(application_pods); do
  node=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.nodeName}')
  if [ "$node" != "$primary_node" ]; then worker=$node; break; fi
done
[ -n "$worker" ] || { printf 'No application worker is available outside the primary database node.\n' >&2; exit 1; }

stopped_worker="$cluster_name-${worker#${cluster_name}-}"
printf 'primary_pod=%s\nprimary_node=%s\nstopped_worker=%s\n' "$primary_pod" "$primary_node" "$stopped_worker" >"$output_dir/worker-selection.txt"
kubectl get cluster/todolist-db -n "$namespace" -o wide >"$output_dir/database-before-worker-failure.txt"
docker stop "$stopped_worker" >/dev/null
sleep 10
kubectl get pods -n "$namespace" -o wide >"$output_dir/pods-after-worker-failure.txt"
kubectl get hpa,pdb -n "$namespace" >"$output_dir/availability-controls.txt"
kubectl get cluster/todolist-db -n "$namespace" -o wide >"$output_dir/database-after-worker-failure.txt"
sleep 5

finished=$(date -u +%s)
failed=$(awk '$3 != "200" { count++ } END { print count + 0 }' "$output_dir/health.log")
total=$(wc -l <"$output_dir/health.log" | tr -d ' ')
max_outage=$(awk -v finished="$finished" '
  $3 != "200" { if (start == "") start = $1; next }
  start != "" { outage = $1 - start; if (outage > max) max = outage; start = "" }
  END { if (start != "") { outage = finished - start; if (outage > max) max = outage }; print max + 0 }
' "$output_dir/health.log")
printf 'total=%s failed_samples=%s max_outage_seconds=%s\n' "$total" "$failed" "$max_outage" >"$output_dir/summary.txt"

if [ "$max_outage" -gt 10 ]; then
  printf 'HA test exceeded the 10-second node-failure error budget.\n' >&2
  exit 1
fi
printf 'HA test passed. Evidence: %s\n' "$output_dir"
