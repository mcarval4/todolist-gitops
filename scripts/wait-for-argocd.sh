#!/bin/sh
set -eu

namespace="${ARGOCD_NAMESPACE:-argocd}"
application="${ARGOCD_APPLICATION:-todolist}"
attempts="${ARGOCD_WAIT_ATTEMPTS:-60}"
expected_revision="${GITHUB_SHA:-}"

attempt=1
while [ "$attempt" -le "$attempts" ]; do
  sync=$(kubectl get application "$application" -n "$namespace" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$(kubectl get application "$application" -n "$namespace" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  revisions=$(kubectl get application "$application" -n "$namespace" -o json 2>/dev/null | jq -r '.status.sync.revisions[]?' | tr '\n' ' ' || true)
  revision_is_current=true
  if [ -n "$expected_revision" ]; then
    case " $revisions " in
      *" $expected_revision "*) ;;
      *) revision_is_current=false ;;
    esac
  fi
  if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ] && [ "$revision_is_current" = true ]; then
    printf 'Argo CD application %s is synced and healthy.\n' "$application"
    exit 0
  fi
  printf 'Waiting for Argo CD: sync=%s health=%s revisions=%s expected=%s attempt=%s/%s\n' "$sync" "$health" "$revisions" "$expected_revision" "$attempt" "$attempts"
  sleep 10
  attempt=$((attempt + 1))
done

kubectl describe application "$application" -n "$namespace" || true
printf 'Argo CD application did not become synced and healthy.\n' >&2
exit 1
