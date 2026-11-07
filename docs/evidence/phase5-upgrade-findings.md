# Upgrade 1.36.6 to 1.37.2: what the availability probe showed

Probe: API via the NLB (/healthz) and the pdb-demo NodePort on all 3 workers, every 2 s.
Raw log: phase5-upgrade-probe.log (note: a failed API sample prints several lines, so count
samples by timestamp, not by line).

- 938 samples. 26 had a bad API answer (2.8%), in three clusters of about a minute each,
  matching the restarts of cp1, cp2 and cp3.
- Cause (likely): the NLB health check is TCP on 6443, so it sends traffic to an API server
  that has opened its port but is not ready yet (503/500/403 responses).
- One incident, 15:08:07 to 15:08:17 (6 consecutive samples): the demo app refused connections
  on all 3 workers. All three workers were briefly marked NotReady while cp3 restarted, so
  their pods dropped out of the service endpoints. The pods kept running (events show
  "Cancelling deletion"). Why all three workers went NotReady is not yet proven.
- Ansible failed twice with "Forbidden" for the same reason (a just-restarted API server
  answering before its RBAC rules had loaded). Fixed with retries in the role.

## Follow-up test: API server stopped on cp3 for 60 s (after switching the NLB health check to /readyz)
- 164 samples. 1 bad API sample (about 16 s after the stop). 0 worker failures.
- Only the stopped control-plane node went NotReady. The 6 workers stayed Ready.
- Conclusion: a restarting API server alone does not make workers flap. The 12-second
  all-workers outage during the upgrade (15:08:07 to 15:08:17) was NOT reproduced and its
  cause is unproven. cp3 was also restarting etcd (3.6.8 to 3.7.0) at that moment.
- Limits: one test, one control plane, one run.
