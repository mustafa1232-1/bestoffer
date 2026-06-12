from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def count_matches(base: Path, glob: str, pattern: str) -> int:
    total = 0
    regex = re.compile(pattern)
    for path in base.rglob(glob):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        total += len(regex.findall(text))
    return total


def collect_top_matches(base: Path, glob: str, pattern: str, limit: int = 20):
    regex = re.compile(pattern)
    hits: list[dict[str, object]] = []
    for path in base.rglob(glob):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        count = len(regex.findall(text))
        if count:
            hits.append({"path": str(path.relative_to(ROOT)), "count": count})
    hits.sort(key=lambda item: (-int(item["count"]), str(item["path"])))
    return hits[:limit]


def count_non_code_json_messages(base: Path) -> int:
    regex = re.compile(
        r"json\s*\(\s*\{[^\}]{0,240}?message\s*:\s*(['\"])(.*?)\1", re.S
    )
    total = 0
    for path in base.rglob("*.js"):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in regex.finditer(text):
            value = match.group(2)
            if re.fullmatch(r"[A-Z0-9_]+", value):
                continue
            total += 1
    return total


def main() -> None:
    lib = ROOT / "lib"
    backend = ROOT / "backend" / "src"
    arbs = ROOT / "lib" / "l10n"

    report = {
        "arb_keys_en": len(json.loads((arbs / "app_en.arb").read_text(encoding="utf-8"))),
        "arb_keys_ar": len(json.loads((arbs / "app_ar.arb").read_text(encoding="utf-8"))),
        "legacy_flutter_i18n": {
            "context_lt": count_matches(lib, "*.dart", r"context\.lt\("),
            "company_text": count_matches(lib, "*.dart", r"companyText\("),
            "app_strings": count_matches(lib, "*.dart", r"strings\.t\('"),
        },
        "backend_localization": {
            "notification_i18n_renderer": int(
                (backend / "modules" / "notifications" / "notification.render.js").exists()
            ),
            "notification_i18n_mapper": int(
                (backend / "modules" / "notifications" / "notification.i18n.js").exists()
            ),
            "push_locale_registration": count_matches(
                ROOT / "lib",
                "*.dart",
                r"localeCode\s*:",
            ),
            "api_human_message_literals": count_non_code_json_messages(backend),
        },
        "top_flutter_legacy_files": {
            "context_lt": collect_top_matches(lib, "*.dart", r"context\.lt\("),
            "company_text": collect_top_matches(lib, "*.dart", r"companyText\("),
            "app_strings": collect_top_matches(lib, "*.dart", r"strings\.t\('"),
        },
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
