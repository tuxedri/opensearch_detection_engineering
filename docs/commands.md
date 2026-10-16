# Command reference

Run all Make commands inside the disposable VM, from
`/workspace/opensearch-detection-lab`, with `source .venv/bin/activate`.
Install Python dependencies with `python3 -m pip install -r requirements.txt`.
VM lifecycle commands run on the host; see [VM setup](vm.md).

## Discovery and lifecycle

| Command |  Behavior and result |
| --- | --- |
| `make`, `make help` |  Print the supported commands; start nothing. |
| `make setup`, `make up` |  Identical commands. Validate Compose, start OpenSearch, Dashboards and Logstash, wait for OpenSearch, install index templates, then start Auditbeat. Run `make health` to check all services. |
| `make down` |  Stop and remove stack containers/networks; retain named data volumes. |
| `make reset` |  Same shutdown behavior as `down`, with logging. Does not reset indexes, passwords, or volumes. |
| `make status` |  Show Compose container status. |
| `make health` |  Check OpenSearch, Dashboards, Logstash and Auditbeat; return nonzero if any is not healthy/running. Does not validate telemetry or detection. |
| `make logs` |  Follow service logs. Ctrl-C stops following, not the services. |

## Dashboards and findings

### `make objects`

Imports all `*.ndjson` files directly in `config/opensearch-dashboards/objects/`.
Index-pattern exports first, dashboard exports second, then other exports, alphabetically within
each group.

```bash
make objects
```
See [dashboards](dashboards.md).

### `make findings`

Imports findings from accessible detectors into `securtiy-findings-view` (existing
index spelling). Installs its template and mappings and updates stable record IDs.
It runs once, not continuously; rerun after new findings arrive.

## Atomic simulations: `make test`

 Each enabled entry starts a disposable `redcanary/invoke-atomicredteam:latest` container. Configuration
defaults to `tests/atomic/invoke.yml`. Run the telemetry stack first to collect events.

```bash
make test
```

Each invocation logs a six-character hexadecimal run ID. Container labels become
`atomic.test`, `atomic.name`, `atomic.link`, and `atomic.testrun` in audit events.
Tagged events use `security-auditbeat-<run>-YYYY.MM.dd`; untagged events retain
`security-auditbeat-YYYY.MM.dd`. Run IDs can collide; also constrain the time range.

The runner returns nonzero for container command failures or timeouts. Inspect
Atomic's own `Exit code:` output too: upstream PowerShell can exit successfully
even when a test fails. The floating image can change test behavior between runs.
`atomic_guid` is a label; the `args` entry's `-TestGuids` selects the upstream test.