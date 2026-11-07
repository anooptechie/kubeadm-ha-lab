# Versions (as last verified 2026-11-07)

| Component | Version | Notes |
| --- | --- | --- |
| Kubernetes | 1.37.2 | Built on 1.36.6, upgraded in place (see upgrade/RUNBOOK.md) |
| Calico | v3.33.0 | Operator install, VXLAN, BGP disabled |
| containerd | 2.4.2 | Installed from Docker's apt repository, SystemdCgroup = true |
| etcd | 3.7.0 | Upgraded by kubeadm during the 1.36 to 1.37 upgrade (was 3.6.8) |
| Node OS | Ubuntu Server 24.04 LTS (amd64) | |
| Instance type | t3.medium | 3 control planes + 3 workers |
| Region | us-east-1 | |
| Terraform | 1.17.1 | AWS provider ~> 6.0 |
| Ansible | 2.21.6 | In tools/ansible-venv (not committed) |
