# Configure a Linux detector

Start the stack, then open **Security Analytics → Detectors → Create detector**
in OpenSearch Dashboards. Choose `security-auditbeat` Alias as the data source and
Linux as the log type.

Select rules relevant to the enabled technique in `tests/atomic/invoke.yml`.
Review their actual conditions: an ATT&CK technique tag alone does not establish
that a particular Atomic command will match. Set an evaluation schedule suitable
for the lab, review field mappings, and create the detector. Alerts are optional
for this workflow; the findings importer reads findings rather than notifications.

## Auditbeat field mappings

| Rule field | Auditbeat field |
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

Confirm the detector is active, run one simulation, and wait for its next scheduled
evaluation. Verify source events in Discover and findings in Security Analytics
before running `make findings`. Detector setup is manual and UI labels can vary
between OpenSearch releases. This guide does not guarantee that every configured
Atomic test has a matching rule.
