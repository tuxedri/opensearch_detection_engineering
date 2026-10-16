"""Protect the cross-export references used by the shipped dashboards."""

import json
from pathlib import Path


OBJECTS = Path(__file__).resolve().parents[2] / "config/opensearch-dashboards/objects"


def test_saved_objects_have_unique_ids_and_resolvable_references() -> None:
    objects = {}
    for path in sorted(OBJECTS.glob("*.ndjson")):
        for line in path.read_text().splitlines():
            obj = json.loads(line)
            if "type" not in obj:
                continue
            key = (obj["type"], obj["id"])
            assert key not in objects, f"Duplicate saved object {key} in {path.name}"
            objects[key] = obj

    assert objects, "No saved objects found"
    for key, obj in objects.items():
        references = obj.get("references", [])
        for ref in references:
            assert (ref["type"], ref["id"]) in objects, f"Unresolved reference from {key}: {ref}"
        if obj["type"] == "dashboard":
            names = {ref["name"] for ref in references}
            for panel in json.loads(obj["attributes"]["panelsJSON"]):
                assert panel["panelRefName"] in names


def test_audit_and_findings_tables_use_distinct_data_sources() -> None:
    expected = {
        "dashboard_auditbeat.ndjson": ("095d8c90-ccb7-11ec-8e2e-df6c4b380c8e", "panel_5", "auditbeat_local"),
        "dashboard_findings.ndjson": ("6f351cf0-c4e6-11f1-85f2-956dab675d54", "panel_6", "41666320-c4e5-11f1-85f2-956dab675d54"),
    }
    for filename, (dashboard_id, panel_name, index_id) in expected.items():
        objects = [json.loads(line) for line in (OBJECTS / filename).read_text().splitlines()]
        dashboard = next(obj for obj in objects if obj.get("id") == dashboard_id)
        search_id = next(ref["id"] for ref in dashboard["references"] if ref["name"] == panel_name)
        search = next(obj for obj in objects if obj.get("id") == search_id)
        assert search["type"] == "search"
        assert any(ref["type"] == "index-pattern" and ref["id"] == index_id for ref in search["references"])
