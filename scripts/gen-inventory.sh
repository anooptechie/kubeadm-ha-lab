#!/usr/bin/env bash
# Builds ansible/inventory/hosts.ini from the Terraform outputs.
set -euo pipefail

cd "$(dirname "$0")/../terraform"
out=$(terraform output -json)
inv="../ansible/inventory/hosts.ini"
mkdir -p "$(dirname "$inv")"

{
  echo "[control_plane]"
  i=1
  for ip in $(echo "$out" | jq -r '.control_plane_private_ips.value[]'); do
    echo "cp${i} ansible_host=${ip}"
    i=$((i + 1))
  done

  echo
  echo "[workers]"
  i=1
  for ip in $(echo "$out" | jq -r '.worker_private_ips.value[]'); do
    echo "worker${i} ansible_host=${ip}"
    i=$((i + 1))
  done

  echo
  echo "[k8s:children]"
  echo "control_plane"
  echo "workers"

  echo
  echo "[k8s:vars]"
  echo "control_plane_endpoint=$(echo "$out" | jq -r '.control_plane_endpoint.value')"
} > "$inv"

echo "Wrote $inv"
