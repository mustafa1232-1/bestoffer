from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_GROUPS = {
    "backend_src": ROOT / "backend" / "src",
    "flutter_lib": ROOT / "lib",
    "backend_sql": ROOT / "backend" / "sql",
}

EXTENSIONS = {
    ".js": ["/**", "Purpose:", "Maintenance notes:"],
    ".dart": ["///", "Purpose:"],
    ".sql": ["-- Purpose:"],
}


def iter_files(base: Path):
    for path in base.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in EXTENSIONS:
            continue
        yield path


def has_documentation_markers(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="ignore")
    markers = EXTENSIONS.get(path.suffix.lower(), [])
    return any(marker in text for marker in markers)


def summarize_group(name: str, base: Path) -> str:
    files = list(iter_files(base))
    documented = [path for path in files if has_documentation_markers(path)]
    percent = 0.0 if not files else (len(documented) / len(files)) * 100
    return (
        f"{name}: total={len(files)} documented={len(documented)} "
        f"coverage={percent:.1f}%"
    )


def main() -> None:
    print("Documentation audit")
    print("===================")
    for name, base in SCAN_GROUPS.items():
        print(summarize_group(name, base))


if __name__ == "__main__":
    main()
