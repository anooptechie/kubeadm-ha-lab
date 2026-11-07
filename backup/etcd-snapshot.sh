#!/usr/bin/env bash
# Takes an etcd snapshot on a control-plane node, verifies it, and also archives
# /etc/kubernetes. Run as root. Prints the backup directory as its LAST line.
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/etcd}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${BACKUP_ROOT}/${TS}"
mkdir -p "${DEST}"

ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "${DEST}/etcd-snapshot.db"

# Verify the snapshot is readable and show its size and revision
etcdutl snapshot status "${DEST}/etcd-snapshot.db" -w table

# Certificates, manifests and configs (contains private keys, keep it private)
tar -czf "${DEST}/kubernetes-dir.tar.gz" -C / etc/kubernetes

(cd "${DEST}" && sha256sum etcd-snapshot.db kubernetes-dir.tar.gz > SHA256SUMS)

echo "${DEST}"
