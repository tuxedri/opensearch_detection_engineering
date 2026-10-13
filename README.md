# OpenSearch Detection Engineering Lab

This repository is an educational lab for validating detection coverage by executing
attack simulations and confirming that the expected OpenSearch Security Analytics
findings actually occur.

> Atomic Red Team intentionally executes techniques that simulate malicious behavior.
> Run this lab only inside a disposable test VM or another isolated environment.

The implementation is in progress. See [PLAN.md](PLAN.md) for the design and
[TASKS.md](TASKS.md) for current status.

## Requirements

- Disposable Linux VM
- 4 vCPU, 8 GB RAM, and 40 GB disk recommended
- Docker Engine with the Docker Compose plugin
- Linux audit subsystem available to Auditbeat
- `make`, `curl`, and Python 3 for local validation

If Docker is installed but `docker compose` is unavailable, install the pinned,
checksum-verified project-local plugin:

```bash
make compose-install
```

The Make targets prefer a system Compose plugin and otherwise use this local copy.

## Disposable VM

The supported execution target is a disposable Ubuntu VM managed by Vagrant and
VirtualBox. The default VM has 4 vCPUs, 8 GB RAM, and a 40 GB disk. The repository
root is mounted bidirectionally at `/workspace/opensearch-detection-lab` and is also
available through `/home/vagrant/opensearch-detection-lab`.

Host requirements are Vagrant and VirtualBox. Start and enter the VM with:

```bash
make vm-up
make vm-ssh
cd /workspace/opensearch-detection-lab
make setup
```

After the stack starts, Dashboards is available on the host at
`http://127.0.0.1:5601`, and the OpenSearch API is forwarded to
`https://127.0.0.1:9200`. Docker publishes these ports on the VM's IPv4 network
interfaces so Vagrant can reach them. Vagrant's forwarded ports listen on host
localhost (`127.0.0.1`).

Resource and mount defaults can be overridden:

```bash
VM_CPUS=6 VM_MEMORY=12288 VM_DISK_GB=60 make vm-up
REPO_MOUNT_PATH=/opt/detection-lab make vm-up
VM_DASHBOARDS_PORT=15601 VM_OPENSEARCH_PORT=19200 make vm-up
```

VirtualBox shared folders are used by default. The optional libvirt provider remains
available when `vagrant-libvirt` and `virtiofs` are installed:

```bash
VM_PROVIDER=libvirt make vm-up
```

Destroy the disposable VM when finished:

```bash
make vm-destroy
```

## Current Workflow

```bash
cp .env.example .env
make setup
make health
make atomic
make coverage
```

The initial tracer executes the safe Atomic Red Team T1059.004 base64 command and
writes its execution manifest below `runtime/`. Security Analytics detector automation
is the next implementation phase.

## Dashboards Saved Objects

After starting the stack, run inside the VM:

```bash
make objects
```

This imports every `*.ndjson` file directly in
`config/opensearch-dashboards/objects/`: `indexpattern*` first, `dashboard*`
second, then remaining files, alphabetically within each group. Existing objects
with the same type and ID are overwritten, including saved visualizations.
Re-running the command reapplies the exports.

The helper requires host Python 3 and running `opensearch` and
`opensearch-dashboards` services. It uses curl and the existing admin credentials
inside the OpenSearch container. It waits up to 120 seconds for Dashboards;
override this with `OPENSEARCH_DASHBOARD_WAIT=300 make objects`.
An HTTP or object-level import error stops the command; earlier imports remain
applied. OpenSearch Dashboards 3.8 supports `overwrite=true`, but has no
`override=true` import option to bypass migration errors.

## Docker Metadata in Audit Events


Auditbeat resolves audited process IDs through the VM's cgroups and Docker API to
add `container.id`, `container.name`, `container.image.name`, and Docker labels.
Logstash removes the entire `container.labels` object before indexing.

See [Docker metadata](docs/docker-metadata.md) for the VM update commands, a
two-container verification, and the fields to display in Dashboards. `make up` also
installs the container mappings for existing indexes and all templates from
`config/opensearch/index-templates/` for new indexes.

To install or update those templates independently:

```bash
bash scripts/install-index-template.sh
```

The helper validates JSON before sending requests, then installs every `*.json`
file directly in that directory in alphabetical order. Template names come from
the filenames without `.json`, except `default-auditbeat-8.12.json`, which retains
the existing `security-auditbeat` template name. For example,
`sap-linux-findings.json` is installed as `sap-linux-findings`. Existing templates
with those names are updated. Any HTTP error or missing acknowledgement stops
installation; previously applied changes remain in place.

## Detector Configuration: Auditbeat Field Mappings

When configuring an OpenSearch Security Analytics detector for Auditbeat data,
use these recommended field mappings:

| OpenSearch detection rule field | Select Auditbeat field |
| --- | --- |
| `auditd.log.a0` | `auditd.data.a0` |
| `auditd.log.comm` | `process.name` |
| `auditd.log.exe` | `process.executable` |
| `auditd.log.uid` | `user.id` |
| `process.exe` | `process.executable` |
| `process.real_user.id` | `user.id` |
| `rsa.web.remote_domain` | Leave unmapped |
| `system.auth.user` | `user.name` |
| `timestamp` | `@timestamp` |

## Enriched findings

Run `make findings` inside the VM to import findings from all accessible detectors
into `securtiy-findings-view`. Each record includes the rule, complete source
document, and root-level `atomic.test` / `atomic.testrun` keyword filters. Repeated
runs update stable document IDs. See [findings view](docs/findings-view.md) for
dashboard setup, missing-document handling, and validation.

## Validation

Static checks parse YAML and JSON, syntax-check every script in `scripts/` and
`vm/`, and render the Compose configuration:

```bash
make validate
```

The regression suite and the attacker simulation are separate targets. Run the
simulation **inside the disposable VM**, where Docker is available and Auditbeat
collects the generated telemetry:

```bash
make unit-test   # Python regression tests (pytest)
make test        # Run Atomic Red Team techniques; one container per enabled test
```

`make test` reads `tests/atomic/invoke.yml`, runs `Invoke-AtomicTest <technique>`
in a fresh `redcanary/invoke-atomicredteam:latest` container for each enabled
technique (container name and labels are derived from the technique), and exits
non-zero if any test fails. It is non-interactive by default. Limit how many run
or attach a terminal with arguments:

```bash
make test ARGS="--limit 2"     # run only the first 2 enabled techniques
make test ARGS="--interactive" # attach a TTY (-it) for manual use
```

The configuration selects one upstream test per entry using `-TestGuids` in
`args`; `atomic_guid` supplies the container label only. In addition to the initial
two tests, these Linux tests are enabled:

| Technique | Selected test |
| --- | --- |
| T1556.003 | Malicious PAM rule |
| T1553.004 | Install root CA on Debian/Ubuntu |
| T1552.004 | Discover Private SSH Keys |
| T1552.001 | Find AWS credentials |
| T1548.003 | Unlimited sudo cache timeout |

The certificate entry generates its prerequisite certificate and then invokes the
test in the same container. PAM, certificate trust, and sudoers changes affect only
that disposable container. The image needs `sudo`, `visudo`, `openssl`,
`ca-certificates`, and `/etc/pam.d/su-l`. Credential discovery searches `/root`
inside the container; an empty search result is valid and does not demonstrate
successful credential collection.

`T1546` is recorded but disabled because its upstream tests are Windows-only.
Parent technique `T1552` is recorded but disabled because its Linux test requires
Stratus and a configured AWS account with cloud resources; it is not a local
credential-search test. Enabling either requires a suitable execution environment.

Preview the configured commands with `make test ARGS="--dry-run"`. For a live run,
inspect Atomic's `Exit code:` output as well as the runner result: upstream
`Invoke-AtomicTest` does not necessarily propagate a test's failure to the PowerShell
process exit status. The floating `latest` image may also contain older Atomic
definitions than upstream.

Each invocation generates one six-character random hexadecimal `testrun` ID,
prints it in the startup log, and labels every test container with
`com.redcanary.atomic.test=<technique>`, `com.redcanary.atomic.name=<name>`,
`com.redcanary.atomic.link=<source>` (the human-readable technique page) and
`com.redcanary.atomic.testrun=<id>`. Logstash copies the dedotted labels to
`atomic.test`, `atomic.name`, `atomic.link` and `atomic.testrun` before removing
container labels. Tagged events go to
`security-auditbeat-<id>-YYYY.MM.dd`; events without a run ID retain the normal
`security-auditbeat-YYYY.MM.dd` index. All techniques in the invocation share the
run ID; a run spanning dates creates one index per date. Short random IDs can
collide and are not a guarantee of uniqueness.

After updating the pipeline, restart Logstash with
`./scripts/compose.sh restart logstash`. Refresh the Auditbeat index pattern's
field list in Dashboards after the first tagged events arrive to discover
`atomic.test`, `atomic.name`, `atomic.link` and `atomic.testrun`. The `security-auditbeat-*` index template matches per-run indexes.

## Troubleshooting Host Access

Use **HTTP** for Dashboards (`http://127.0.0.1:5601/`) and **HTTPS** for the OpenSearch
API (`https://127.0.0.1:9200/`). Connecting to Dashboards with HTTPS causes a TLS error.

If containers are healthy but the host browser receives an empty response or a
connection reset, check the Docker port bindings inside the VM. The original
`127.0.0.1:5601:5601` and `127.0.0.1:9200:9200` bindings only accepted guest-loopback
connections. Vagrant forwards traffic to the guest network interface. The corrected
Compose bindings use `0.0.0.0` inside the VM; host-side access uses Vagrant's
localhost listeners.

After updating the code, run from the repository directory **inside the VM**:

```bash
./scripts/compose.sh config --quiet
./scripts/compose.sh up --detach --wait --wait-timeout 360 opensearch opensearch-dashboards
```

`up` recreates containers with changed port mappings. A container `restart` does not
apply those changes.

Then check the response **on the host**:

```bash
curl -q -I --max-time 10 http://127.0.0.1:5601/
```

Expect an HTTP response, typically `200` or `302`. Vagrant can automatically select a
different host port if the requested port is occupied. To find the actual Dashboards
port, run from the repository root on the host:

```bash
VAGRANT_CWD="$PWD/vm" vagrant port --guest 5601
```

Use the returned port in the browser URL.

## Troubleshooting OpenSearch Startup

Repeated `Authentication finally failed for admin from [::1]` warnings about every
10 seconds indicate that the container's healthcheck cannot authenticate. OpenSearch
is responding, but its unhealthy status blocks Dashboards and Logstash startup.

The lab uses the image's demo-security installer to apply
`OPENSEARCH_INITIAL_ADMIN_PASSWORD` on first initialization. Cluster, node, and
network settings are supplied through `compose.yaml`. A mounted `opensearch.yml`
containing `plugins.security.*` settings makes the installer skip password setup;
the legacy file in `config/opensearch/` is therefore only a reference.

The admin password is stored in the persistent OpenSearch security index. Updating
the environment variable or recreating the container does not change that stored
password. An installation initialized with the old configuration can therefore
continue failing authentication after the code is updated.

For a **disposable lab**, run the following from the repository root inside the VM
after updating the code. It identifies the data volume from the existing container
and deletes that volume, including **all OpenSearch indexes and security state**.
If the data must be retained, recover the existing credentials instead.

```bash
(
  set -euo pipefail
  container_id="$(./scripts/compose.sh ps --all --quiet opensearch)"
  if [[ -z "$container_id" ]]; then
    printf 'OpenSearch container not found; cannot identify its data volume.\n' >&2
    exit 1
  fi
  volume="$(docker inspect --format '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/usr/share/opensearch/data")}}{{.Name}}{{end}}{{end}}' "$container_id")"
  if [[ -z "$volume" ]]; then
    printf 'No named OpenSearch data volume found.\n' >&2
    exit 1
  fi
  docker volume inspect --format 'Resetting OpenSearch volume: {{.Name}}' "$volume"
  ./scripts/compose.sh down
  docker volume rm "$volume"
  make up
  ./scripts/compose.sh up --detach --wait --wait-timeout 360
  make health
)
```

The final Compose command waits for all core services, including Auditbeat, to become
healthy. `make reset` only stops the stack and preserves its volumes.
