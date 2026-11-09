# Demo run sheet (about 10 minutes of drills)

Build the lab first with the README (about 12 minutes of work). Everything below runs from the
repository root on the workstation, with the Ansible virtualenv active. Last rehearsed: NOT YET.

## Before the demo
~~bash
cd ~/rebuild-test
source tools/ansible-venv/bin/activate
# Old backups belong to a previous cluster and must never be used to restore this one.
[ -d ~/etcd-backups ] && mv ~/etcd-backups ~/etcd-backups-old-$(date +%s)
cd ansible && ansible-playbook backup.yml && cd ..     # installs the etcd tools, takes a first backup
kubectl apply -f manifests/pdb-demo.yaml
kubectl -n pdb-demo rollout status deployment/web
~~
Open two terminals: A for commands, B for the control-plane drill.

## Drill 0: it is real (1 min)
~~bash
kubectl get nodes -o wide
kubectl -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key member list -w table
~~
Say: 3 control planes with stacked etcd behind an internal load balancer, 3 workers, no public IPs.

## Drill 1: PodDisruptionBudget protects a drain (3 min)
The app has 4 replicas and a budget of at least 3 available.
~~bash
# 1a. Drain with spare capacity: it succeeds, one pod at a time
BUSY=$(kubectl -n pdb-demo get pods -l app=web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
kubectl drain $BUSY --ignore-daemonsets --delete-emptydir-data --timeout=120s
kubectl uncordon $BUSY

# 1b. Remove the spare capacity: the drain is blocked
BUSY=$(kubectl -n pdb-demo get pods -l app=web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
OTHERS=$(printf '%s\n' worker1 worker2 worker3 | grep -v "^$BUSY$")
for n in $OTHERS; do kubectl cordon $n; done
kubectl drain $BUSY --ignore-daemonsets --delete-emptydir-data --timeout=45s
kubectl -n pdb-demo get pods,pdb

# 1c. Restore capacity: the drain completes
for n in $OTHERS; do kubectl uncordon $n; done
sleep 20
kubectl drain $BUSY --ignore-daemonsets --delete-emptydir-data --timeout=120s
kubectl uncordon $BUSY
kubectl get nodes
~~
Say: in 1b the drain repeats "Cannot evict pod as it would violate the pod's disruption budget"
and times out, the budget shows 0 allowed disruptions, and the app stays at 3 ready pods.

## Drill 2: lose a control plane (2 min)
Terminal B (stops the API server on cp3 for 60 s, then restores it):
~~bash
cd ~/rebuild-test/ansible
ansible cp3 -b -m shell -a "mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ && sleep 60 && mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/"
~~
Terminal A, while that runs (retry once if the first call fails: the load balancer needs a few
seconds to take the server out):
~~bash
kubectl get nodes
kubectl create deployment demo-ha --image=nginx:1.27
kubectl get deployment demo-ha
kubectl -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://10.20.11.91:2379,https://10.20.12.180:2379,https://10.20.13.199:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key endpoint health
kubectl delete deployment demo-ha
~~
Say: the cluster still accepts changes with one control plane down, because etcd keeps quorum (2 of 3).
The etcd command lists node addresses from the original build: replace them with the IPs from
`kubectl get nodes -o wide`.

## Drill 3: etcd backup and restore (4 min)
~~bash
cd ~/rebuild-test/ansible
kubectl create namespace demo-restore
kubectl -n demo-restore create deployment keep-me --image=nginx:1.27 --replicas=2
kubectl -n demo-restore create configmap important-data --from-literal=note="must survive"
kubectl -n demo-restore rollout status deployment/keep-me

ansible-playbook backup.yml
SNAP=$(ls -d ~/etcd-backups/*/ | sort | tail -1); SNAP=${SNAP%/}; echo "$SNAP"
(cd "$SNAP" && sha256sum -c SHA256SUMS)

# the disaster, plus a change made after the backup
kubectl -n demo-restore delete deployment keep-me
kubectl -n demo-restore delete configmap important-data
kubectl -n demo-restore create configmap created-after-backup --from-literal=note="will be lost"
kubectl -n demo-restore get deployment,configmap

time ansible-playbook restore.yml -e snapshot_dir=$SNAP
sleep 20
kubectl -n demo-restore get deployment,configmap
ansible control_plane -b -m shell -a "rm -rf /var/lib/etcd.pre-restore-* /var/backups/etcd-restore.db"
~~
Say: the deployment and configmap are back, the one created after the backup is gone, and that is
the cost of a restore. The playbook took 58 seconds in the earlier drill.
If the restore goes wrong: `ansible-playbook restore-rollback.yml -e restore_ts=<stamp it printed>`.

## Do not demo live
The upgrade takes about 25 minutes. Show `upgrade/RUNBOOK.md` and `docs/evidence/phase5-*` instead.

## After the demo
~~bash
cd ~/rebuild-test && ./scripts/teardown.sh
~~
