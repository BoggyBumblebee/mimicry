#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: xcresult-to-sonar-test-execution.py <xcresult-path> <output-xml-path>",
            file=sys.stderr,
        )
        return 1

    result_bundle = Path(sys.argv[1]).resolve()
    output_xml = Path(sys.argv[2]).resolve()
    workspace_root = Path.cwd().resolve()

    root = xcresult_json(result_bundle)
    tests_ref = (
        root.get("actions", {})
        .get("_values", [{}])[0]
        .get("actionResult", {})
        .get("testsRef", {})
        .get("id", {})
        .get("_value")
    )

    if not tests_ref:
        raise SystemExit("xcresult bundle does not contain test results.")

    test_tree = xcresult_json(result_bundle, tests_ref)
    suite_paths = discover_test_suite_paths(workspace_root / "Tests")
    grouped_cases: dict[str, list[dict[str, object]]] = {}

    collect_test_cases(test_tree, grouped_cases, suite_paths)

    output_xml.parent.mkdir(parents=True, exist_ok=True)
    write_report(output_xml, grouped_cases, workspace_root)
    return 0


def xcresult_json(result_bundle: Path, object_id: str | None = None) -> dict:
    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "object",
        "--legacy",
        "--path",
        str(result_bundle),
        "--format",
        "json",
    ]
    if object_id:
        command.extend(["--id", object_id])

    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def discover_test_suite_paths(tests_root: Path) -> dict[str, Path]:
    return {
        file_path.stem: file_path
        for file_path in tests_root.rglob("*.swift")
    }


def collect_test_cases(
    node: object,
    grouped_cases: dict[str, list[dict[str, object]]],
    suite_paths: dict[str, Path],
) -> None:
    if isinstance(node, dict):
        node_type = node.get("_type", {}).get("_name")
        if node_type == "ActionTestMetadata":
            identifier = node.get("identifier", {}).get("_value", "")
            suite_name = identifier.split("/", 1)[0]
            suite_path = suite_paths.get(suite_name)
            if suite_path is None:
                suite_path = next(iter(suite_paths.values()), None)
            if suite_path is None:
                return

            grouped_cases.setdefault(str(suite_path), []).append(
                {
                    "name": node.get("name", {}).get("_value", identifier),
                    "duration_ms": duration_milliseconds(node.get("duration", {}).get("_value", "0")),
                    "status": node.get("testStatus", {}).get("_value", "Success"),
                }
            )
            return

        for value in node.values():
            collect_test_cases(value, grouped_cases, suite_paths)
    elif isinstance(node, list):
        for item in node:
            collect_test_cases(item, grouped_cases, suite_paths)


def duration_milliseconds(raw_duration: str) -> int:
    try:
        return max(0, round(float(raw_duration) * 1000))
    except ValueError:
        return 0


def write_report(
    output_xml: Path,
    grouped_cases: dict[str, list[dict[str, object]]],
    workspace_root: Path,
) -> None:
    root = ET.Element("testExecutions", version="1")

    for suite_path in sorted(grouped_cases):
        relative_path = Path(suite_path).resolve().relative_to(workspace_root)
        file_element = ET.SubElement(root, "file", path=str(relative_path))

        for case in grouped_cases[suite_path]:
            test_case = ET.SubElement(
                file_element,
                "testCase",
                name=str(case["name"]),
                duration=str(case["duration_ms"]),
            )

            status = str(case["status"])
            if status == "Skipped":
                ET.SubElement(test_case, "skipped", message="Test skipped")
            elif status not in {"Success", "Passed"}:
                ET.SubElement(test_case, "failure", message=f"Test {status.lower()}")

    ET.indent(root)
    ET.ElementTree(root).write(output_xml, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    raise SystemExit(main())
