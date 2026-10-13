#!/usr/bin/env python3
"""Materialize Security Analytics findings and their source documents."""

import argparse
import hashlib
import json
import logging
from pathlib import Path
import subprocess
from typing import Any, Iterator
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
INDEX = "securtiy-findings-view"
LOG = logging.getLogger(__name__)


class ImportFailure(RuntimeError):
    """An incomplete import; rerunning is safe."""


class Client:
    def request(self, method: str, path: str, body: Any = None,
                ndjson: bool = False) -> dict:
        payload = body if ndjson else json.dumps(body) if body is not None else ""
        command = ["bash", str(ROOT / "scripts/compose.sh"), "exec", "-T",
                   "opensearch", "sh", "-c",
                   'exec curl --silent --show-error --fail --insecure '
                   '--connect-timeout 10 --max-time 120 '
                   '--user "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" "$@"',
                   "sh", "--request", method, "--header",
                   "Content-Type: application/x-ndjson" if ndjson else
                   "Content-Type: application/json", "https://localhost:9200/" + path]
        if body is not None:
            command += ["--data-binary", "@-"]
        result = subprocess.run(command, input=payload, text=True, capture_output=True,
                                cwd=ROOT, timeout=150, check=False)
        if result.returncode:
            # Never log response bodies or subprocess output containing source data.
            raise ImportFailure(f"{method} {path.split('?')[0]} failed (exit {result.returncode}); check Compose/OpenSearch health and permissions")
        try:
            response = json.loads(result.stdout)
        except ValueError as exc:
            raise ImportFailure("OpenSearch returned invalid JSON") from exc
        if not isinstance(response, dict) or response.get("error"):
            raise ImportFailure("OpenSearch returned an error response")
        return response


def prepare_index(client: Client) -> None:
    template = json.loads((ROOT / "config/opensearch/index-templates/securtiy-findings-view.json").read_text())
    result = client.request("PUT", "_index_template/securtiy-findings-view", template)
    if result.get("acknowledged") is not True:
        raise ImportFailure("Index template was not acknowledged")
    # Wildcard metadata lookup returns {} when this exact index does not exist.
    existing = client.request("GET", INDEX + "?allow_no_indices=true&ignore_unavailable=true")
    if INDEX in existing:
        result = client.request("PUT", INDEX + "/_mapping", template["template"]["mappings"])
    else:
        result = client.request("PUT", INDEX, template["template"])
    if result.get("acknowledged") is not True:
        raise ImportFailure("Index creation/mapping update was not acknowledged")


def finding_pages(client: Client, size: int) -> Iterator[list[dict]]:
    offset = 0
    seen = set()
    while True:
        params = urlencode({"sortOrder": "asc", "size": size, "startIndex": offset})
        result = client.request("GET", "_plugins/_security_analytics/findings/_search?" + params)
        rows = result.get("findings")
        total = result.get("total_findings")
        if not isinstance(rows, list) or not isinstance(total, int) or total < 0:
            raise ImportFailure("Invalid findings pagination response")
        if not rows:
            if offset < total:
                raise ImportFailure("Findings pagination ended before total_findings")
            return
        identities = {(r["detectorId"], r["id"]) for r in rows}
        if not identities - seen:
            raise ImportFailure("Findings pagination made no progress")
        seen.update(identities)
        yield rows
        offset += len(rows)
        LOG.info("Fetched %d of %d findings", offset, total)
        if offset >= total:
            return


def source_entries(client: Client, finding: dict) -> list[dict]:
    entries = [dict(entry) for entry in (finding.get("document_list") or [])]
    present = {entry["id"] for entry in entries}
    for doc_id in finding.get("related_doc_ids", []):
        if doc_id not in present:
            entries.append({"id": doc_id, "index": finding["index"]})
            present.add(doc_id)
    for entry in entries:
        entry.setdefault("index", finding["index"])
    missing = [entry for entry in entries if entry.get("document") is None]
    for start in range(0, len(missing), 500):
        batch = missing[start:start + 500]
        result = client.request("POST", "_mget", {"docs": [
            {"_index": e["index"], "_id": e["id"]} for e in batch]})
        docs = result.get("docs", [])
        if len(docs) != len(batch):
            raise ImportFailure("Incomplete _mget response")
        for entry, doc in zip(batch, docs):
            if doc.get("error"):
                raise ImportFailure("Source document lookup failed")
            if (doc.get("_index"), doc.get("_id")) != (entry["index"], entry["id"]):
                raise ImportFailure("Source document lookup identity mismatch")
            entry["found"] = doc.get("found", False)
            entry["document"] = doc.get("_source")
    if not entries:
        LOG.warning("Finding has no associated source document IDs")
    return entries


def transform(finding: dict, entry: dict) -> tuple[str, dict]:
    document = entry.get("document")
    if isinstance(document, str):
        try:
            document = json.loads(document)
        except ValueError:
            # Do not leak embedded event/credential values; report only identifiers so the
            # exact source can be inspected directly in its index. One bad document must not
            # abort the whole import.
            LOG.warning(
                "Source document %s in index %s for finding %s (detector %s) is not valid JSON; recording it as a missing source",
                entry["id"], entry["index"], finding["id"], finding["detectorId"],
            )
            document = None
    if document is not None and not isinstance(document, dict):
        raise ImportFailure("Source document must be a JSON object")
    identity = [finding["detectorId"], finding["id"], entry["index"], entry["id"]]
    doc_id = hashlib.sha256(json.dumps(identity, separators=(",", ":")).encode()).hexdigest()
    queries = finding.get("queries") or []
    query = queries[0] if queries else {}
    output = {
        "@timestamp": finding["timestamp"],
        "finding": {"id": finding["id"], "detector_id": finding["detectorId"]},
        "index": entry["index"],
        "rule": {key: query[key] for key in ("name", "query", "tags") if key in query},
        "source_document": {"id": entry["id"], "found": document is not None},
    }
    if document is not None:
        output["document"] = document
        atomic = document.get("atomic") or {}
        output["atomic"] = {key: atomic[key] for key in ("test", "testrun", "name", "link") if key in atomic}
    return doc_id, output


def write_batch(client: Client, records: list[tuple[str, dict]]) -> tuple[int, int]:
    lines = []
    for doc_id, document in records:
        lines.extend([json.dumps({"index": {"_index": INDEX, "_id": doc_id}}),
                      json.dumps(document)])
    result = client.request("POST", "_bulk", "\n".join(lines) + "\n", ndjson=True)
    items = result.get("items", [])
    failures = [item for item in items if item.get("index", {}).get("status") not in (200, 201)]
    if result.get("errors") or failures or len(items) != len(records):
        raise ImportFailure(f"Bulk indexing incomplete: {len(failures)} failed items; earlier writes may have succeeded")
    created = sum(item["index"].get("result") == "created" for item in items)
    return created, len(items) - created


def run(client: Client, page_size: int) -> None:
    prepare_index(client)
    LOG.info("Starting findings import into %s (page size %d)", INDEX, page_size)
    findings = created = updated = missing = 0
    pending = []
    for page in finding_pages(client, page_size):
        for finding in page:
            findings += 1
            for entry in source_entries(client, finding):
                record = transform(finding, entry)
                missing += not record[1]["source_document"]["found"]
                pending.append(record)
                if len(pending) >= 500:
                    new, old = write_batch(client, pending)
                    created += new
                    updated += old
                    pending = []
        if pending:
            new, old = write_batch(client, pending)
            created += new
            updated += old
            pending = []
    result = client.request("POST", INDEX + "/_refresh")
    if result.get("_shards", {}).get("failed", 0):
        raise ImportFailure("Index refresh failed")
    LOG.info("Import complete: findings=%d created=%d updated=%d missing_sources=%d",
             findings, created, updated, missing)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page-size", type=int, default=1000)
    args = parser.parse_args()
    if not 1 <= args.page_size <= 10000:
        parser.error("--page-size must be between 1 and 10000")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    try:
        run(Client(), args.page_size)
    except (ImportFailure, OSError, subprocess.TimeoutExpired, KeyError, TypeError, ValueError) as exc:
        # Unexpected schema errors must not print embedded event/credential values.
        LOG.error("%s", str(exc) if isinstance(exc, ImportFailure) else
                  f"Import failed ({type(exc).__name__}); check service availability and response schema")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
