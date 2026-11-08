# etcd backup and restore

etcd holds every object in the cluster. Losing it without a backup means losing the cluster,
even though the servers survive. Worker pods keep running during an etcd outage, but nothing can
be changed until the API is back.

## Backup
~~bash
cd ansible
ansible-playbook backup.yml
~~
`backup.yml` installs `etcdctl` and `etcdutl` at the same version as the running etcd (variable
`etcd_version`; the tools must match the server), runs `backup/etcd-snapshot.sh` on the first
control plane, and copies the result to `~/etcd-backups/<timestamp>/` on the workstation:
- `etcd-snapshot.db`: the snapshot (`etcdctl snapshot save`, checked with `etcdutl snapshot status`)
- `kubernetes-dir.tar.gz`: `/etc/kubernetes` (certificates and manifests)
- `SHA256SUMS`: verify the copy with `sha256sum -c SHA256SUMS`

Both files contain cluster secrets. They live outside the repository, and `.gitignore` blocks
`*.db`, `kubernetes-dir.tar.gz` and `etcd-backups/` as a safety net.

Last backup in this lab: 626 keys, 13 MB, etcd 3.7.0.

## Restore (all control planes from one snapshot)
~~bash
cd ansible
ansible-playbook restore.yml -e snapshot_dir=$HOME/etcd-backups/<timestamp>
~~
The playbook, per control plane:
1. Verifies the snapshot checksums on the workstation, and copies the snapshot to each node.
2. Parks `kube-apiserver.yaml` and `etcd.yaml` (moves them out of the static-pod directory),
   which stops both, and waits until the processes are gone.
3. Moves the current data to `/var/lib/etcd.pre-restore-<stamp>` (the rollback copy).
4. Runs `etcdutl snapshot restore` into a fresh `/var/lib/etcd` with this member's name, the full
   member list, a new cluster token and its peer URL.
5. Puts back `etcd.yaml`, waits for etcd to be healthy, puts back `kube-apiserver.yaml`, and
   waits for the API to answer.

Restore **all** members from the **same** snapshot. Restoring just one member of a healthy
cluster would leave it with different data from the others.

The restore tools must match the version the snapshot was written by.

### If it goes wrong
~~bash
ansible-playbook restore-rollback.yml -e restore_ts=<stamp printed by the restore>
~~
puts the saved pre-restore data back. Take a fresh backup of the current state **before** a
restore, as a way back.

### Clean up afterwards
Delete `/var/lib/etcd.pre-restore-*` and `/var/backups/etcd-restore.db` once the restore is
confirmed (they hold old cluster secrets):
~~bash
ansible control_plane -b -m shell -a "rm -rf /var/lib/etcd.pre-restore-* /var/backups/etcd-restore.db"
~~

## The drill performed in this lab
1. Created a namespace with a deployment (2 replicas) and a configmap; took a backup.
2. Deleted the deployment and the configmap, and created a new configmap.
3. Restored from the earlier snapshot (601 keys, 11 MB, etcd 3.6.8, 3 members).
4. Result: the deployment and configmap were back, the configmap created after the snapshot was
   gone, all 6 nodes Ready, all 3 etcd members healthy. The restore playbook took **58 seconds**.
   Evidence: `docs/evidence/phase4-*`.

## What a restore costs
Everything created or changed after the snapshot is lost. How often you back up decides how much
you can afford to lose.

## Limits
- 58 s covers the playbook only, not the time to notice a failure and decide to restore.
- Only restoring a healthy cluster's own snapshot was tested; loss of all control-plane servers
  and rebuilding from the backup was not.
- Backups are stored only on the first control plane and the workstation. There is no copy
  off-site (for example in S3).
- A restore across a Kubernetes or etcd version upgrade was not tested.
