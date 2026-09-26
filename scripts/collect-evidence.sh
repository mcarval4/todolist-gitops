#!/bin/sh
set -eu

output_dir="evidence/generated/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output_dir"
kubectl get nodes -o wide >"$output_dir/nodes.txt"
kubectl get pods --all-namespaces -o wide >"$output_dir/pods.txt"
kubectl get hpa,pdb,networkpolicy -n todolist >"$output_dir/workload-controls.txt"
kubectl get events -n todolist --sort-by=.lastTimestamp >"$output_dir/events.txt"
printf 'Evidence written to %s\n' "$output_dir"
