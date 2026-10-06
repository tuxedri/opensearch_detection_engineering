#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_tests(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as config_file:
        config = yaml.safe_load(config_file)
    tests = config.get("tests", []) if isinstance(config, dict) else []
    if not isinstance(tests, list):
        raise ValueError("tests must be a list")
    return [test for test in tests if test.get("enabled", True)]


def run_test(test: dict[str, Any], run_id: str) -> dict[str, Any]:
    started_at = utc_now()
    timeout = int(test.get("timeout_seconds", 30))
    try:
        completed = subprocess.run(
            ["/bin/bash", "-c", str(test["command"])],
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
        exit_code = completed.returncode
        stdout = completed.stdout
        stderr = completed.stderr
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        exit_code = None
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        timed_out = True

    cleanup_exit_code = None
    cleanup_command = test.get("cleanup")
    if cleanup_command:
        cleanup = subprocess.run(
            ["/bin/bash", "-c", str(cleanup_command)],
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
        cleanup_exit_code = cleanup.returncode

    return {
        "run_id": run_id,
        "technique": test["technique"],
        "atomic_guid": test["atomic_guid"],
        "name": test["name"],
        "expected_rule": bool(test.get("expected_rule", False)),
        "expected_sigma_rule": test.get("expected_sigma_rule"),
        "telemetry_query": test.get("telemetry", {}),
        "started_at": started_at,
        "ended_at": utc_now(),
        "exit_code": exit_code,
        "timed_out": timed_out,
        "executed": exit_code == 0,
        "cleanup_exit_code": cleanup_exit_code,
        "stdout": stdout,
        "stderr": stderr,
        "telemetry_observed": None,
        "sigma_rule_exists": None,
        "finding_observed": None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run curated Atomic tests")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    run_id = str(uuid.uuid4())
    results = [run_test(test, run_id) for test in load_tests(args.config)]
    manifest = {"run_id": run_id, "generated_at": utc_now(), "tests": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for result in results:
        state = "PASS" if result["executed"] else "FAIL"
        print(f'[{result["technique"]}] {result["name"]}: {state}')
    return 0 if all(result["executed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
