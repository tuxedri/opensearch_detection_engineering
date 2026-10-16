# Troubleshooting

## Services are starting or unhealthy

Inside the VM, run `make status`, `make health`, and `make logs`. Initial image
downloads and JVM startup can take several minutes. Setup starts Auditbeat last;
its completion message does not mean every healthcheck has already passed.

## Browser cannot reach Dashboards

Use HTTP for Dashboards and HTTPS for the OpenSearch API. On the host, from `vm/`,
run `vagrant port --guest 5601` to find the forwarded port. If Compose port mappings
changed, recreate services with `make up`; a container restart does not apply new
port mappings.

## OpenSearch authentication fails

The initial admin password is applied on first initialization and stored in the
persistent OpenSearch security index. Changing `.env` does not change an existing
cluster's password. Recover the existing credentials or use OpenSearch's supported
password-management procedure. `make reset` preserves the security index and data.

## No Atomic fields or findings

Check source telemetry first, then the detector's rules, field mappings, schedule,
and findings. Refresh the `security-auditbeat-*` index pattern's field list after
the first tagged events arrive. Auditbeat resolves container metadata through VM
cgroups and the Docker API; Logstash copies selected Atomic labels and removes
`container.labels` before indexing.