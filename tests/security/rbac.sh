#!/bin/sh
set -eu

namespace="${NAMESPACE:-todolist}"
service_account="${SERVICE_ACCOUNT:-todolist}"

kubectl auth can-i list pods -n "$namespace" --as="system:serviceaccount:$namespace:$service_account"
if kubectl auth can-i list secrets -n "$namespace" --as="system:serviceaccount:$namespace:$service_account" | grep -qx yes; then
  printf '%s\n' 'Service account unexpectedly has permission to list secrets.' >&2
  exit 1
fi
printf '%s\n' 'RBAC least-privilege check passed.'
