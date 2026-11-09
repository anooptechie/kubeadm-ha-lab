# kubeadm HA Cluster Lab

A highly available Kubernetes cluster on AWS, built entirely from code with Terraform and
Ansible (kubeadm, containerd, Calico), then put through the operations a cluster owner
actually faces: losing a control-plane node, a protected node drain, etcd backup and
restore, and an in-place minor-version upgrade.

Everything described here was run for real. Raw output, including the things that went
wrong, is in [`docs/evidence/`](docs/evidence/) and [`docs/troubleshooting.md`](docs/troubleshooting.md).

> Clean-rebuild test: on 2026-11-09 I destroyed everything with `scripts/teardown.sh`, cloned this repo into an empty folder and rebuilt by following only this README. `terraform apply` took about 3 minutes and `ansible-playbook site.yml` about 9 minutes. Result: 6 nodes Ready on 1.37.2, 3 etcd members, 3 healthy load balancer targets (`docs/evidence/phase6-clean-rebuild.txt`). Findings: no step failed; the times are estimates from AWS and file timestamps (Ansible is an upper bound).

## Architecture

~~
Workstation VPC ── VPC peering ── Lab VPC 10.20.0.0/16
                                  ├─ 3 public subnets (one per AZ): NAT gateway
                                  └─ 3 private subnets (one per AZ):
                                       3 control planes + 3 workers
                                       internal Network Load Balancer :6443 -> the 3 API servers
~~

- 3 control planes (stacked etcd) and 3 workers, all t3.medium, Ubuntu Server 24.04
- Kubernetes 1.37.2 (built on 1.36.6 and upgraded in place), containerd 2.4.2,
  Calico v3.33.0 (VXLAN, BGP disabled), etcd 3.7.0. See [`versions.md`](versions.md)
- Nodes have no public IPs and are reached from a workstation in a peered VPC
- The internal NLB is the cluster endpoint (`--control-plane-endpoint`); its health check
  calls the API server's `/readyz` over HTTPS
- Tags (`Project`, `Environment`, `ManagedBy`) are applied to everything by the provider

## What I measured

| Exercise | Result |
| --- | --- |
| One control plane stopped for 8 min 16 s | 243 of 243 probes of the API and a demo app succeeded; etcd kept quorum (2 of 3). This was a graceful shutdown, not a crash |
| PodDisruptionBudget (minAvailable 3 of 4), drain with spare capacity | Succeeded; the drain waited for each replacement pod before evicting the next |
| PodDisruptionBudget, drain with no spare capacity | Blocked: timed out after 60 s with the budget at 0 allowed disruptions; the app stayed at 3 ready pods; resolved by uncordoning |
| etcd restore (601 keys, 11 MB) on all 3 members | 58 s for the playbook; deleted objects came back; an object created after the snapshot was gone |
| Upgrade 1.36.6 to 1.37.2, one node at a time | All 6 nodes upgraded. During it, 26 of 938 API probes failed (2.8%), in three clusters matching the three control-plane restarts, and the demo app refused connections on all workers for about 12 s once. The cause of that 12 s is **not proven** (see `docs/evidence/phase5-upgrade-findings.md`) |
| After switching the NLB health check to `/readyz`: API server stopped for 60 s | 1 bad API sample out of 164; no worker failures |

Limits of these numbers: one run each, a small cluster, probes every 2 seconds.

## How to run

Prerequisites, on a machine inside a VPC that the lab can peer with (the "workstation"):
- AWS credentials that can create the resources (I used an EC2 instance role)
- Terraform >= 1.6, the AWS CLI, `jq`, and `kubectl` (within one minor version of the cluster)
- Ansible in a virtualenv, for example:
  `python3 -m venv tools/ansible-venv && source tools/ansible-venv/bin/activate && pip install ansible`
  (`tools/ansible-venv` is gitignored; activate it in every new terminal)

~~bash
# 1. SSH key used for the nodes
ssh-keygen -t ed25519 -f ~/.ssh/kubeadm-lab -N "" -C kubeadm-lab

# 2. Infrastructure (edit terraform.tfvars: set workstation_vpc_id)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cd terraform && terraform init && terraform apply && cd ..

# 3. Inventory from the Terraform outputs, then build the cluster
./scripts/gen-inventory.sh
cd ansible && ansible-playbook site.yml && cd ..

# 4. kubectl on the workstation
mkdir -p ~/.kube
CP1=$(cd terraform && terraform output -json control_plane_private_ips | jq -r '.[0]')
ssh -i ~/.ssh/kubeadm-lab -o StrictHostKeyChecking=no ubuntu@$CP1 cat /home/ubuntu/.kube/config > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes
~~

## Operations

~~bash
cd ansible
ansible-playbook backup.yml                                  # etcd snapshot, copied to ~/etcd-backups (outside the repo)
ansible-playbook restore.yml -e snapshot_dir=$HOME/etcd-backups/<timestamp>
ansible-playbook upgrade.yml -e target_minor=<next minor>    # one minor at a time
cd .. && ./scripts/teardown.sh                               # destroy everything, then check for leftovers
~~

Before an upgrade, check that your containerd version supports the target Kubernetes
version (containerd.io/releases), take a fresh backup, and afterwards update
`k8s_minor`, `k8s_package_version` and `etcd_version` in `ansible/group_vars/all.yml`.
Details: [`upgrade/RUNBOOK.md`](upgrade/RUNBOOK.md) and [`backup/RESTORE.md`](backup/RESTORE.md).

## Repository layout

~~
terraform/   VPC, subnets, NAT, peering, security groups, instances, NLB
ansible/     roles: common, containerd, kube_packages, control_plane, calico, cp_join, worker,
             etcd_tools, k8s_upgrade; playbooks: site, backup, restore, restore-rollback, upgrade
manifests/   Calico settings, test apps (nginx NodePort, PDB demo)
backup/      etcd snapshot script and restore notes
upgrade/     upgrade runbook
scripts/     inventory generation from Terraform outputs, teardown
docs/        troubleshooting log, evidence (command output and probe logs)
~~

## Shortcuts and limitations

- SSH host key checking is off in `ansible/ansible.cfg` (a lab convenience).
- The workstation uses the cluster-admin kubeconfig. There is no RBAC separation.
- One shared NAT gateway; a NAT failure would cut outbound traffic for all nodes.
- IAM: the workstation's instance role used for Terraform has three broad AWS-managed policies attached (AmazonEC2FullAccess, AmazonVPCFullAccess, ElasticLoadBalancingFullAccess), which gives far more access than this project needs. I designed a least-privilege policy set (scoped statements with region and tag conditions) but never attached it. The cluster nodes have no IAM role at all. To tighten: replace the managed policies with one generated from CloudTrail activity using IAM Access Analyzer, restrict `iam:PassRole`, and add a permissions boundary.
- The backup stays on the control plane and the workstation only (no off-cluster copy such as S3).
- The HA test used a graceful stop; a hard crash was not tested.

## Credits

Based on the Day 54 (cluster build) and Day 55 (cluster upgrade) material from
CloudWithVarJosh's CKA course. The Terraform, Ansible, runbooks, drills and troubleshooting
notes in this repository are my own work from running the project.
