"""Collect actual Godot results; never infer success from test process exit alone."""
import hashlib
import json
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"


def result_from_log(name):
    text = (EVIDENCE / f"{name}_validation.log").read_text(encoding="utf-8-sig")
    if "SCRIPT ERROR:" in text or "\nERROR:" in text or "ObjectDB instances leaked" in text:
        raise RuntimeError(f"{name}: engine errors in log")
    if name == "editor":
        import re
        match = re.search(r"EDITOR_TESTS: (\d+) checks, (\d+) failures", text)
        if not match or int(match[2]):
            raise RuntimeError("editor: missing/failed result")
        return {"checks": int(match[1]), "failures": []}

    # Native debug lines may contain dictionaries before the result marker.
    marker = {"release": "RELEASE_SELF_CHECK ", "assets": "ASSET_RESULT "}.get(name, f"{name.upper()}_RESULT ")
    marker_at = text.find(marker)
    if marker_at < 0 and name not in ("core", "workspace"):
        raise RuntimeError(f"{name}: missing result marker")
    start = text.find("{", max(marker_at, 0))
    if start < 0:
        raise RuntimeError(f"{name}: missing structured result")
    result, _ = json.JSONDecoder().raw_decode(text[start:])
    if result.get("failures") != []:
        raise RuntimeError(f"{name}: failed result")
    return result


def main():
    summary_path = EVIDENCE / "validation_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8-sig")) if summary_path.exists() else {}
    jobs = ("core", "parameters", "replay", "workspace", "editor", "editor_workbench", "recovery", "profile", "assets", "transition", "flow", "hud_footer")
    results = {name: result_from_log(name) for name in jobs}
    counts = {name: result["checks"] for name, result in results.items()}
    native_path = EVIDENCE / "native_editor_validation.log"
    if native_path.exists():
        native = result_from_log("native_editor")
        counts["native_editor"] = native["checks"]
        summary["native_editor"] = native
    summary.update(date=date.today().isoformat(), automated_checks=counts, total_checks=sum(counts.values()), failures=[], campaign=results["core"]["campaign"], ui_flow=results["flow"])
    release_path = ROOT / "builds/windows/KuroBox.exe"
    if release_path.exists() and (EVIDENCE / "release_validation.log").exists():
        release = result_from_log("release")
        with release_path.open("rb") as binary:
            digest = hashlib.sha256()
            for chunk in iter(lambda: binary.read(1024 * 1024), b""):
                digest.update(chunk)
            binary_hash = digest.hexdigest()
        summary["windows_release"] = {"path": "builds/windows/KuroBox.exe", "bytes": release_path.stat().st_size, "sha256": binary_hash, "self_check": release, "clean_exit": True}
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {summary['total_checks']} passing checks in evidence/validation_summary.json")


if __name__ == "__main__":
    main()
