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
