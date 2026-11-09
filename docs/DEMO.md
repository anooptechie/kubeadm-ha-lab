# Demo run sheet (about 10 minutes of drills)

Build the lab first with the README (about 12 minutes of work). Everything below runs from the
repository root on the workstation, with the Ansible virtualenv active. Last rehearsed: 2026-11-09.

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

## Drill 2: lose a control plane (3 min)
Terminal B (stops the API server and the etcd member on cp3 for 90 s, then restores both):
~~~bash
cd ~/rebuild-test/ansible
ansible cp3 -b -m shell -a "mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ && mv /etc/kubernetes/manifests/etcd.yaml /tmp/ && sleep 90 && mv /tmp/etcd.yaml /etc/kubernetes/manifests/ && mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/"
~~~
Terminal A, started right after B, from the repository root:
~~~bash
cd ~/rebuild-test
EP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[*]}https://{.status.addresses[?(@.type=="InternalIP")].address}:2379,{end}' | sed 's/,$//')
kubectl get nodes
sleep 40
kubectl -n kube-system exec etcd-cp1 -- etcdctl --endpoints=$EP \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key endpoint health
kubectl create deployment demo-ha --image=nginx:1.27
kubectl get deployment demo-ha
~~~
Say: the stopped member shows "connection refused" and is unhealthy, the other two are healthy, and the
cluster still accepted a change, because etcd needs only 2 of its 3 members. (Wait the 40 s: the
etcd member takes a few seconds to stop, and checking too early shows all three healthy.)
After terminal B finishes (about 90 s):
~~~bash
kubectl delete deployment demo-ha
kubectl get nodes
~~~

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
