#!/usr/bin/env python3
"""Print a dependency-first module closure from a kernel modules directory."""

from __future__ import annotations

import argparse
from pathlib import Path


def module_name(path: str) -> str:
    name = Path(path).name
    for suffix in (".zst", ".xz", ".gz"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    if name.endswith(".ko"):
        name = name[:-3]
    return name.replace("-", "_")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("modules_dir", type=Path)
    parser.add_argument("modules", nargs="+")
    args = parser.parse_args()

    dep_file = args.modules_dir / "modules.dep"
    if not dep_file.is_file():
        parser.error(f"missing {dep_file}")

    dependencies: dict[str, list[str]] = {}
    by_name: dict[str, str] = {}
    for line in dep_file.read_text().splitlines():
        path, separator, raw_dependencies = line.partition(":")
        if not separator:
            continue
        path = path.strip()
        dependencies[path] = raw_dependencies.split()
        by_name[module_name(path)] = path

    builtin_file = args.modules_dir / "modules.builtin"
    builtins = (
        {module_name(line.strip()) for line in builtin_file.read_text().splitlines()}
        if builtin_file.is_file()
        else set()
    )

    ordered: list[str] = []
    visited: set[str] = set()

    def visit(path: str) -> None:
        if path in visited:
            return
        if path not in dependencies:
            parser.error(f"module dependency path is absent: {path}")
        visited.add(path)
        for dependency in dependencies[path]:
            visit(dependency)
        ordered.append(path)

    for requested in args.modules:
        normalized = requested.removesuffix(".ko").replace("-", "_")
        path = by_name.get(normalized)
        if path is not None:
            visit(path)
        elif normalized not in builtins:
            parser.error(f"module not found: {requested}")

    print("\n".join(ordered))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
