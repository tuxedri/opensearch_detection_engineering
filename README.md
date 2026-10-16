# OpenSearch Detection Engineering Lab

Run Atomic Red Team simulations, inspect Linux audit telemetry, and investigate
OpenSearch Security Analytics findings in a disposable lab.

**Rule count is not detection coverage.** This lab helps you compare what executed,
what was collected, and what produced a finding.

The project is experimental. It includes a telemetry stack, configurable Atomic
simulations, saved dashboards, and an on-demand findings importer. Detector setup
is manual; automated coverage classification is not part of the current workflow.

> Run only in a disposable Linux VM. Atomic tests simulate malicious behavior, and
> Auditbeat collects VM-wide audit events. Do not use a production host.

## Requirements

On the host:

- Vagrant and VirtualBox. 
- Resources for the default VM: **4 vCPUs, 12 GB RAM, and 40 GB disk**.
- Internet access for VM images, packages, and container images.

Run Vagrant commands on the host from the repository's `vm/` directory. Make is
used inside the VM. The default provider is VirtualBox; the Ubuntu 24.04 VM has
4 vCPUs, 12 GB RAM, and a 40 GB disk.

Provisioning installs Docker Engine, Docker Compose, and Make in Ubuntu 24.04,
configures kernel limits, and disables the VM's auditd service so Auditbeat can
collect audit events.

## Quick start

Clone this repository, then run **on the host**, from its root:

```bash
cd vm
vagrant validate
vagrant up --provider=virtualbox
vagrant ssh
```

Run the remaining commands **inside the VM**:

```bash
cd /workspace/opensearch-detection-lab
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
cp .env.example .env
```

Set your local admin password in `.env` before first startup. Do not commit that
file. Reuse an existing `.env` rather than overwriting it when returning to the lab.

```bash
make setup
make health
make objects
```

Startup can take several minutes. If `make health` reports services still starting,
check `make status` and `make logs`, then check health again.

Open **http://127.0.0.1:5601** on the host. 

Sign in as `admin` using the password configured in `.env`. 

The OpenSearch API is at **https://127.0.0.1:9200**.

The API uses the lab's self-signed certificate.

All Make commands below run inside the VM from the repository root,
with `.venv` activated.

## Run and investigate a simulation

1. In Security Analytics, create a Linux detector for `security-auditbeat-*`, select
   rules relevant to the technique you want to exercise, and configure the
   [Auditbeat field mappings](docs/detectors.md).
2. Preview the selected commands, then execute one enabled technique:

   ```bash
   make test ARGS="--dry-run --limit 1"
   make test ARGS="--limit 1"
   ```

3. Note the `testrun` ID in the runner output. Open the Auditbeat overview dashboard,
   choose a time range covering the run, and filter by `atomic.testrun`.

4. Wait for the detector's next scheduled evaluation. Inspect its findings, then
   import them into the dashboard view:

   ```bash
   make findings
   ```

5. Open **Atomic | Findings Overview Dashboard** and filter by the same run ID.

A successful simulation is not proof of detection. First confirm telemetry, then
check the selected rules and findings. An empty findings view can mean no matching
rule, missing telemetry, detector configuration issues, or evaluation still pending.
The [dashboard guide](docs/dashboards.md) explains each panel and its limitations.

## Commands

Run `make` or `make help` for a summary. See the [complete command reference](docs/commands.md)
for prerequisites, options, side effects, and expected results.

| Command | Purpose |
| --- | --- |
| `make setup`, `make up` | Start and configure the telemetry stack |
| `make health`, `make status` | Check service health and container status |
| `make logs` | Follow service logs |
| `make objects` | Import saved dashboards and index patterns |
| `make test` | Run configured Atomic simulations |
| `make findings` | Import enriched Security Analytics findings |
| `make down`, `make reset` | Stop the stack and preserve data volumes |
| `make unit-test` | Run Python regression tests |
| `make validate` | Check configuration and script syntax |

## Stop the lab

Inside the VM, `make down` stops containers without deleting their data volumes.
Exit SSH, then run `vagrant halt` from the host's `vm/` directory to stop the VM.
Use `vagrant destroy` there to delete the disposable VM and its VM-local data.
The shared repository directory remains on the host.

## Documentation

- [Command reference](docs/commands.md)
- [Detector setup and field mappings](docs/detectors.md)
- [Dashboards](docs/dashboards.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing and validation](CONTRIBUTING.md)

## License

Original project contributions are licensed under the [Apache License 2.0](LICENSE).
Third-party components and content retain their respective licenses. See
[attribution](docs/attribution.md).