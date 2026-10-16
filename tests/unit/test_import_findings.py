import importlib.util
import json
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest


SPEC = importlib.util.spec_from_file_location(
    "import_findings", Path(__file__).resolve().parents[2] / "scripts/import-findings.py")
importer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(importer)


def finding(detector="detector-a", doc_id="doc-1"):
    return {
        "id": "finding-1", "detectorId": detector, "index": "events",
        "timestamp": 1791638060144, "related_doc_ids": [doc_id],
        "queries": [{"name": "Example rule", "query": "process.name:ip", "tags": ["linux"]}],
        "document_list": [{"id": doc_id, "index": "events", "found": True,
                           "document": json.dumps({"atomic": {"test": "T1548.003", "testrun": "4cbc6c"},
                                                   "process": {"name": "ip"}})}],
    }


def test_transform_preserves_source_and_promotes_filters():
    row = finding()
    doc_id, output = importer.transform(row, row["document_list"][0])
    assert len(doc_id) == 64
    assert output["atomic"] == {"test": "T1548.003", "testrun": "4cbc6c"}
    assert output["document"] == json.loads(row["document_list"][0]["document"])
    assert output["rule"] == row["queries"][0]
    assert output["@timestamp"] == row["timestamp"]


def test_ids_stable_and_distinct_for_multiple_documents_and_detectors():
    row = finding()
    entry = row["document_list"][0]
    original = importer.transform(row, entry)[0]
    assert importer.transform(row, dict(entry))[0] == original
    assert importer.transform(row, {**entry, "id": "doc-2"})[0] != original
    assert importer.transform({**row, "detectorId": "other"}, entry)[0] != original
    assert importer.transform(row, {**entry, "index": "other"})[0] != original


def test_malformed_json_is_recorded_as_missing_source(monkeypatch):
    row = finding()
    captured = []
    monkeypatch.setattr(
        importer.LOG, "warning", lambda *args, **kwargs: captured.append((args, kwargs)))
    doc_id, output = importer.transform(
        row, {**row["document_list"][0], "document": "not valid json"})
    assert len(doc_id) == 64
    assert output["source_document"]["found"] is False
    assert "document" not in output
    assert "atomic" not in output
    assert captured, "an operational warning identifying the source is expected"
    # Only identifiers are logged; embedded event/credential values must not appear.
    log_text = " ".join(str(arg) for call in captured for arg in call[0])
    assert "ip" not in log_text and "T1548.003" not in log_text


@pytest.mark.parametrize("value", ["[]", 123])
def test_non_object_source_fails_without_logging_contents(value):
    row = finding()
    with pytest.raises(importer.ImportFailure):
        importer.transform(row, {**row["document_list"][0], "document": value})


def test_lookup_fills_partial_document_list_and_keeps_missing_sources():
    row = finding()
    row["related_doc_ids"] += ["doc-2", "deleted"]

    class Client:
        def request(self, method, path, body):
            assert path == "_mget"
            assert [d["_id"] for d in body["docs"]] == ["doc-2", "deleted"]
            return {"docs": [
                {"_index": "events", "_id": "doc-2", "found": True, "_source": {"message": "event"}},
                {"_index": "events", "_id": "deleted", "found": False},
            ]}

    entries = importer.source_entries(Client(), row)
    assert len(entries) == 3
    missing = importer.transform(row, entries[2])[1]
    assert missing["source_document"]["found"] is False
    assert "atomic" not in missing
    assert "document" not in missing


def test_pagination_queries_all_detectors():
    class Client:
        def request(self, method, path):
            params = parse_qs(urlsplit(path).query)
            assert "detector_id" not in params
            offset = int(params["startIndex"][0])
            assert offset in (0, 1)
            return {"total_findings": 2, "findings": [finding(f"detector-{offset}")]}

    pages = list(importer.finding_pages(Client(), 1))
    assert len(pages) == 2
    assert pages[1][0]["detectorId"] == "detector-1"


@pytest.mark.parametrize("rows", [[], [finding()]])
def test_pagination_rejects_truncation_or_repeated_pages(rows):
    class Client:
        calls = 0

        def request(self, method, path):
            self.calls += 1
            return {"total_findings": 3, "findings": [finding()] if self.calls == 1 else rows}

    with pytest.raises(importer.ImportFailure):
        list(importer.finding_pages(Client(), 1))


def test_bulk_item_failure_is_not_success():
    class Client:
        def request(self, method, path, body, ndjson):
            assert ndjson and body.endswith("\n")
            return {"errors": True, "items": [{"index": {"status": 400}}]}

    with pytest.raises(importer.ImportFailure, match="Bulk indexing incomplete"):
        importer.write_batch(Client(), [("id", {"message": "event"})])


def test_full_import_rerun_updates_without_duplicates():
    class Client:
        def __init__(self):
            self.records = {}
            self.created_index = False

        def request(self, method, path, body=None, ndjson=False):
            if path.startswith("_index_template/") or path.endswith("/_mapping"):
                assert body
                return {"acknowledged": True}
            if method == "GET" and path.startswith(importer.INDEX):
                return {importer.INDEX: {}} if self.created_index else {}
            if method == "PUT" and path == importer.INDEX:
                self.created_index = True
                return {"acknowledged": True}
            if path.startswith("_plugins/"):
                row = finding()
                row["document_list"].append({**row["document_list"][0], "id": "doc-2"})
                return {"total_findings": 1, "findings": [row]}
            if path == "_bulk":
                lines = [json.loads(line) for line in body.splitlines()]
                items = []
                for action, source in zip(lines[::2], lines[1::2]):
                    key = action["index"]["_id"]
                    exists = key in self.records
                    self.records[key] = source
                    items.append({"index": {"status": 200 if exists else 201,
                                             "result": "updated" if exists else "created"}})
                return {"errors": False, "items": items}
            assert path.endswith("/_refresh")
            return {"_shards": {"failed": 0}}

    client = Client()
    importer.run(client, 1000)
    assert len(client.records) == 2
    original = dict(client.records)
    importer.run(client, 1000)
    assert client.records == original
