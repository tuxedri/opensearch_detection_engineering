#!/usr/bin/env python3
"""Validate public configuration and saved-object JSON without reading local secrets."""

import json
from pathlib import Path

import yaml


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    paths = [root / "compose.yaml"]
    for directory in ("config", "tests"):
        paths.extend(path for path in (root / directory).rglob("*") if path.is_file())
    for path in sorted(paths):
        if path.suffix in {".yaml", ".yml"}:
            with path.open() as stream:
                yaml.safe_load(stream)
        elif path.suffix == ".json":
            json.loads(path.read_text())
        elif path.suffix == ".ndjson":
            for line in path.read_text().splitlines():
                if line.strip():
                    obj = json.loads(line)
                    attributes = obj.get("attributes", {})
                    for key in ("panelsJSON", "optionsJSON", "visState", "uiStateJSON"):
                        if key in attributes:
                            json.loads(attributes[key])
                    source = attributes.get("kibanaSavedObjectMeta", {}).get("searchSourceJSON")
                    if source:
                        json.loads(source)


if __name__ == "__main__":
    main()
