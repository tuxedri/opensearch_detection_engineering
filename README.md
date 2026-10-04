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

## Validation

With the Python packages from `requirements.txt` installed, run:

```bash
make validate
make test
```

Validation parses YAML, checks each shell script individually, and validates Compose.

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
