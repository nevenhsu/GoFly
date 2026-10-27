#!/usr/bin/env python3
"""Write a source and declared-license inventory from the bundled wheels."""

from __future__ import annotations

import importlib.metadata
import re
import sys
from pathlib import Path


def one_line(value: str | None) -> str:
    if not value:
        return ""
    return " ".join(value.split()).replace("|", "\\|")


def package_license(distribution: importlib.metadata.Distribution) -> str:
    metadata = distribution.metadata
    expression = metadata.get("License-Expression")
    if expression:
        return one_line(expression)

    classifiers = [
        classifier.removeprefix("License :: ")
        for classifier in metadata.get_all("Classifier", [])
        if classifier.startswith("License :: ")
    ]
    legacy = one_line(metadata.get("License"))
    if legacy and len(legacy) <= 160:
        return legacy
    if classifiers:
        return one_line("; ".join(classifiers))
    return "Not declared in wheel metadata"


def license_paths(distribution: importlib.metadata.Distribution) -> str:
    paths: list[str] = []
    for file in distribution.files or ():
        parts = Path(str(file)).parts
        if "licenses" in {part.lower() for part in parts} or re.match(
            r"^(license|copying|notice)(\.|$)", parts[-1], re.IGNORECASE
        ):
            paths.append("GoFly.app/Contents/Resources/Python/python/install/" + str(file))
    return "; ".join(one_line(path) for path in sorted(paths)) or "No license file in wheel metadata"


def source_urls(distribution: importlib.metadata.Distribution) -> str:
    name = distribution.metadata.get("Name", "unknown")
    version = distribution.version
    project_urls = distribution.metadata.get_all("Project-URL", [])
    preferred: list[str] = []
    for value in project_urls:
        _, separator, url = value.partition(",")
        if separator and any(word in value.lower() for word in ("source", "repository", "homepage")):
            preferred.append(url.strip())
    pypi = f"https://pypi.org/project/{name}/{version}/"
    return "; ".join(dict.fromkeys([*preferred, pypi]))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: write-third-party-notices.py OUTPUT.md")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)

    distributions = sorted(
        importlib.metadata.distributions(),
        key=lambda distribution: distribution.metadata.get("Name", "").lower(),
    )
    rows = [
        "# GoFly for Mac V1 third-party runtime inventory",
        "",
        "Generated from the bundled wheel METADATA and RECORD files. License declarations are supplied by each package publisher and are not a legal audit. Review every entry and its bundled license text before public distribution.",
        "",
        "The Python runtime is CPython 3.14.6 arm64 from the pinned python-build-standalone 20260610 release. CPython uses the PSF License Version 2. Its upstream source and license are at https://github.com/astral-sh/python-build-standalone/releases/tag/20260610 and https://docs.python.org/3.14/license.html.",
        "",
        "The GoFly iOS project and adapted/native components retain AGPL-3.0 notices in `GoFly.app/Contents/Resources/iOSProject/Legal/`. The bundled `libidevice_ffi.a` is recorded as MIT in `GoFly.app/Contents/Resources/iOSProject/Legal/idevice-MIT.txt`; its transitive native dependency audit remains pending.",
        "",
        "| Package | Version | Declared license | Source | License files in app bundle |",
        "| --- | --- | --- | --- | --- |",
    ]
    for distribution in distributions:
        name = one_line(distribution.metadata.get("Name", "unknown"))
        version = one_line(distribution.version)
        license_value = package_license(distribution)
        source = one_line(source_urls(distribution))
        files = license_paths(distribution)
        rows.append(f"| {name} | {version} | {license_value} | {source} | {files} |")

    output.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"Wrote {len(distributions)} runtime entries to {output}")


if __name__ == "__main__":
    main()
