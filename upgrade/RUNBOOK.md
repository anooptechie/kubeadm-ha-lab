# Runbook: in-place minor-version upgrade

Performed once in this lab: 1.36.6 to 1.37.2, one node at a time, with the playbook
`ansible/upgrade.yml`. Evidence and the problems met along the way are in
`docs/evidence/phase5-*` and `docs/troubleshooting.md`.

## Rules
- Upgrade exactly one minor version at a time (skipping a minor is unsupported).
- Control planes first, then workers. Kubelets may be older than the API server, never newer.
- One node at a time, so the cluster keeps quorum and the PodDisruptionBudgets can be honoured.

## Before you start
1. **Check the container runtime supports the target version.** containerd publishes a
   compatibility table (containerd.io/releases). Kubernetes 1.37 needs containerd 2.3.0+ or
   2.4.0+; this lab had 2.4.2 (`ansible all -a "containerd --version"`).
2. **Check Calico supports the target version** in Tigera's requirements page. Calico v3.33
   is listed for Kubernetes 1.35 to 1.37, so no CNI upgrade was needed.
3. **Check the target repository exists:** `curl -sIL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | grep HTTP` ends in 200.
4. **Take a fresh backup** and verify it (see `backup/RESTORE.md`):
   `ansible-playbook backup.yml`, then `sha256sum -c SHA256SUMS` in the new backup folder.
5. **Confirm a healthy baseline:** all nodes Ready, `kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` empty, all etcd members healthy.
6. **Start an availability probe** (API `/readyz` through the load balancer, and the demo app
   on each worker) writing one short line per sample to a log. Count failures by sample,
   not by line.

## Run
~~bash
cd ansible
ansible-playbook upgrade.yml -e target_minor=1.37
~~

What the playbook does:
1. First control plane: switch the apt repository to the new minor, find the newest patch,
   install the new `kubeadm`, show `kubeadm upgrade plan`, run `kubeadm upgrade apply`,
   drain, install `kubelet` and `kubectl`, restart kubelet, wait for the new version and
   `Ready`, uncordon.
2. Other control planes, one at a time: same, but `kubeadm upgrade node` instead of `apply`.
3. Workers, one at a time: same as step 2. Each drain waits on the PodDisruptionBudget while
   replacement pods start elsewhere.

Packages are held (`apt-mark hold`) outside of upgrades, and the playbook skips any node
already on the target version, so a failed run can simply be started again.

## After the upgrade
- Verify: `kubectl get nodes` (all on the new version, none `SchedulingDisabled`), no stuck pods,
  `kubectl get tigerastatus` all Available, the demo PDB back to its normal allowed disruptions.
- **kubeadm also upgrades etcd.** Here etcd went 3.6.8 to 3.7.0. Update `etcd_version` in
  `ansible/group_vars/all.yml`, re-run `ansible-playbook backup.yml` (it reinstalls matching
  `etcdctl`/`etcdutl`) and take a fresh backup. Do not rely on backups taken before the upgrade.
- Update `k8s_minor` and `k8s_package_version` in `group_vars/all.yml` and `versions.md`,
  so a rebuild produces the new version.

## Known issues seen in this lab
- During a control-plane restart the API server briefly answered 503/403, which broke `kubectl`
  calls inside the playbook ("Forbidden"). The role now retries these calls, and the load
  balancer health check uses `/readyz` (an HTTPS check with `matcher = "200"`).
- Measured: 26 of 938 API probes failed (2.8%) in three clusters, one per control-plane restart,
  under the old TCP health check. The demo app refused connections on all workers for about 12 s
  once; the cause is **not proven** (see `docs/evidence/phase5-upgrade-findings.md`).

## Rollback
There is no automatic rollback after `kubeadm upgrade apply`. The safety net is the pre-upgrade
etcd snapshot plus the `/etc/kubernetes` archive that `backup.yml` takes. Restoring them
was **not tested across a version change**: a snapshot from before the upgrade holds data written
by the old etcd version, and the old binaries and manifests would also have to be restored.
Treat the upgrade as a one-way step, and rehearse it on a copy of the cluster first.
