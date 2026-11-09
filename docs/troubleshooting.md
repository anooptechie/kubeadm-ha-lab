# Troubleshooting log

Each entry is a problem that actually happened while building and operating this lab:
symptom, how it was diagnosed, cause, fix, and how to avoid it.

## 1. `terraform validate`: "Reference to undeclared input variable"
- **Symptom:** errors for `azs`, `public_subnet_cidrs` and `private_subnet_cidrs`.
- **Diagnosis:** `cat variables.tf` showed only `workstation_vpc_id`.
- **Cause:** a later step used `cat > variables.tf` (overwrite) instead of `cat >> variables.tf` (append), which erased the earlier variables.
- **Fix:** re-added the three variables with `>>`.
- **Prevention:** `cat` a file after editing it; commit after every working step so `git diff` shows lost lines.

## 2. SSH test from the wrong machine
- **Symptom:** `Identity file /Users/.../kubeadm-lab not accessible: No such file or directory`.
- **Cause:** the command ran on a laptop. The key lives on the workstation, and the nodes only have private IPs reachable through the VPC peering.
- **Fix:** run SSH from the workstation.
- **Prevention:** keep private keys on one machine; check the prompt (`ubuntu@...`) before running commands.

## 3. `ansible-playbook: command not found`
- **Cause:** the Ansible virtualenv was not active in a new terminal session.
- **Fix:** `source tools/ansible-venv/bin/activate` (not `apt install ansible-core`, which would create a second install).
- **Prevention:** the prompt shows `(ansible-venv)` when it is active.

## 4. `'k8s_minor' is undefined`
- **Symptom:** the `kube_packages` role failed on its first task.
- **Cause:** Ansible did not find `ansible/group_vars/all.yml`, where the version variables live.
- **Fix:** create the file with the variables, then re-run.
- **Prevention:** keep every setting a role needs in `group_vars/all.yml` and check the role runs with `--syntax-check` and a first run on one host.

## 5. `No such file or directory` writing `manifests/calico-installation.yaml`
- **Cause:** the `manifests/` directory did not exist yet, and a shell redirect does not create directories.
- **Fix:** `mkdir -p manifests` first.

## 6. Calico wait failed: "no matching resources found"
- **Symptom:** `kubectl wait --for=condition=Available tigerastatus --all` failed straight after the install tasks, although Calico was installing correctly.
- **Cause:** the wait ran milliseconds after the settings were applied, before the Tigera operator had created its status resources, so `--all` matched nothing.
- **Fix:** first wait (with retries) until `kubectl get tigerastatus` lists resources, then wait for them to become Available.
- **Prevention:** when waiting on resources an operator creates asynchronously, wait for existence first.

## 7. NLB health check change rejected: "Health check matcher HTTP code cannot be empty"
- **Symptom:** `terraform apply` failed with a 400 ValidationError on the target group.
- **Cause:** switching a Network Load Balancer health check from TCP to HTTPS requires an explicit list of accepted status codes.
- **Fix:** added `matcher = "200"` next to `path = "/readyz"`.

## 8. `crictl: No such file or directory`
- **Symptom:** the pre-check before the etcd restore failed on all control planes.
- **Cause:** the restore playbook used `crictl` to confirm that etcd and the API server had stopped, but it is not installed by the kubeadm packages.
- **Fix:** replaced the check with `pgrep` on the process names (in `restore.yml` and `restore-rollback.yml`).
- **Prevention:** run a read-only pre-check of every tool a destructive playbook uses. This one was caught before anything was changed.

## 9. Duplicate variable in `group_vars/all.yml`
- **Cause:** an append command ran twice, so `etcd_version` appeared twice.
- **Fix:** rewrote the file once with the four variables.
- **Prevention:** make setup steps idempotent (replace the line with `sed`, or rewrite the whole file).

## 10. Glob not expanded: `ls: cannot access '/var/lib/etcd.pre-restore-*'`
- **Cause:** Ansible's default `command` module does not use a shell, so `*` was passed literally.
- **Fix:** use `-m shell` for anything that needs globs, pipes or redirects.

## 11. `Forbidden: User "kubernetes-admin" cannot get resource "nodes"` during the upgrade
- **Symptom:** the upgrade playbook failed twice, after upgrading cp2 and then cp3, on `kubectl wait` and `kubectl uncordon`. Seconds later the same user could do the same thing.
- **Diagnosis:** `kubectl get nodes` and `kubectl auth can-i get nodes` worked immediately afterwards, so permissions were fine; a probe log showed bad API answers (503, 403) clustered around each control-plane restart.
- **Cause:** the NLB health check was a plain TCP check on port 6443. A restarting API server opens the port before it can serve or authorize requests, so the load balancer sent traffic to it too early.
- **Fix:** (1) retries on every kubectl task in the upgrade role; (2) the NLB health check now calls `/readyz` over HTTPS. A test that stopped one API server for 60 s afterwards saw 1 bad sample out of 164.
- **Prevention:** health checks should test readiness, not just an open port.

## 12. Measurement pitfall: counting lines instead of samples
- **Symptom:** the upgrade probe reported "910 API failures" out of 1,822 lines, which contradicted a working cluster.
- **Cause:** a failed API sample prints a long multi-line error body, so counting lines inflated the number. The real count was 26 bad samples out of 938.
- **Fix:** count samples by timestamp, and later probes print one short line per sample.
- **Prevention:** sanity-check a surprising number against what you observed before reporting it.

## Open question
- During the upgrade, the demo app refused connections on all workers for about 12 seconds
  (all 3 workers briefly NotReady while cp3 restarted its kubelet and etcd). A follow-up test
  that only restarted an API server did not reproduce it. The cause is not proven.
  See `docs/evidence/phase5-upgrade-findings.md`.

## 13. etcd tools download timed out: "Failure downloading ... The read operation timed out"
- **Symptom:** `backup.yml` failed on all three control planes in the `unarchive` task that downloads the etcd release from GitHub, twice in a row.
- **Diagnosis:** `curl` from the same node fetched the same file (23 MB) in 0.2 s with HTTP 200, so the network and GitHub were fine.
- **Cause:** not proven. The failure was in Ansible's built-in download path (it had worked on an earlier build).
- **Fix:** download with `curl --retry` and unpack with `tar` (guarded with `creates`).
- **Prevention:** for large downloads use a tool with retries and a long timeout, and test the download by hand before blaming the network.
