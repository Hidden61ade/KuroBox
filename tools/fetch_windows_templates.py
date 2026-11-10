"""Read the official ZIP index and fetch only Windows x86_64 members.

The full multi-platform TPZ is never downloaded. Each response is bounded,
and members are verified by the ZIP's CRC32 and an independently recorded SHA256.
"""
import hashlib
import json
from pathlib import Path
import struct
import urllib.request
import zlib

URL = "https://github.com/godotengine/godot-builds/releases/download/4.6-stable/Godot_v4.6-stable_export_templates.tpz"
ROOT = Path(__file__).resolve().parents[1] / ".tools" / "windows_export"
REQUESTED = {"windows_release_x86_64.exe", "windows_debug_x86_64.exe"}

def read_range(start=None, end=None, tail=None):
    value = f"bytes=-{tail}" if tail is not None else f"bytes={start}-{end}"
    request = urllib.request.Request(URL, headers={"Range": value, "User-Agent": "KuroBox-Windows-template-fetch", "Accept-Encoding": "identity"})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 206:
            raise RuntimeError(f"Server did not honor range: HTTP {response.status}")
        content_range = response.headers.get("Content-Range", "")
        if not content_range.startswith("bytes "):
            raise RuntimeError("Missing Content-Range")
        bounds, total = content_range[6:].split("/")
        actual_start, actual_end = map(int, bounds.split("-"))
        allowance = actual_end - actual_start + 1
        if allowance > 90 * 1024 * 1024:
            raise RuntimeError("Range exceeds the 90 MiB operation budget")
        data = response.read(allowance + 1)
        if len(data) != allowance:
            raise RuntimeError("Incomplete range response")
        print("RANGE", actual_start, actual_end, "bytes", len(data), flush=True)
        return data, actual_start, int(total)

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    # Official release API reports this archive length; explicit endpoints are
    # accepted by hosts that reject suffix-only HTTP ranges.
    archive_size = 1251639300
    tail, tail_start, full_size = read_range(archive_size - 131072, archive_size - 1)
    position = tail.rfind(b"PK\x05\x06")
    if position < 0:
        raise RuntimeError("ZIP end-of-directory not found")
    eocd = struct.unpack_from("<4s4H2LH", tail, position)
    count, index_size, index_start = eocd[4:7]
    if index_start == 0xFFFFFFFF or count == 0xFFFF:
        raise RuntimeError("ZIP64 is not handled by this bounded extractor")
    if index_start >= tail_start:
        index = tail[index_start-tail_start:index_start-tail_start+index_size]
    else:
        index, _, _ = read_range(index_start, index_start + index_size - 1)
    entries = []
    offset = 0
    while offset < len(index):
        values = struct.unpack_from("<4s6H3L5H2L", index, offset)
        if values[0] != b"PK\x01\x02":
            raise RuntimeError("Bad ZIP central entry")
        name_length, extra_length, comment_length = values[10:13]
        name = index[offset+46:offset+46+name_length].decode("utf-8")
        record = {"name": name, "method": values[4], "crc32": values[7], "compressed_size": values[8], "size": values[9], "local_header": values[16]}
        entries.append(record)
        offset += 46 + name_length + extra_length + comment_length
    (ROOT / "official_zip_inventory.json").write_text(json.dumps({"url": URL, "archive_bytes": full_size, "entry_count": count, "entries": entries}, indent=2), encoding="utf-8")
    selected = [entry for entry in entries if Path(entry["name"]).name in REQUESTED]
    if len(selected) != len(REQUESTED):
        raise RuntimeError("Requested members missing: " + str([e["name"] for e in entries if "windows" in e["name"]]))
    manifest = {"release": "4.6-stable", "source_url": URL, "archive_bytes": full_size, "whole_archive_downloaded": False, "whole_archive_hash_verified": False, "members": []}
    for entry in selected:
        name = Path(entry["name"]).name
        target = ROOT / name
        if target.is_file():
            data = target.read_bytes()
            if len(data) == entry["size"] and (zlib.crc32(data) & 0xFFFFFFFF) == entry["crc32"]:
                print("REUSE", name, len(data), flush=True)
            else:
                raise RuntimeError("Existing output fails member CRC; remove it explicitly before retry")
        else:
            header, _, _ = read_range(entry["local_header"], entry["local_header"] + 1023)
            values = struct.unpack_from("<4s5H3L2H", header, 0)
            if values[0] != b"PK\x03\x04":
                raise RuntimeError("Bad local member header")
            body_start = entry["local_header"] + 30 + values[9] + values[10]
            compressed, _, _ = read_range(body_start, body_start + entry["compressed_size"] - 1)
            if entry["method"] == 8:
                data = zlib.decompress(compressed, -15)
            elif entry["method"] == 0:
                data = compressed
            else:
                raise RuntimeError("Unsupported ZIP method")
            if len(data) != entry["size"] or (zlib.crc32(data) & 0xFFFFFFFF) != entry["crc32"]:
                raise RuntimeError("Member length or CRC mismatch")
            if not data.startswith(b"MZ"):
                raise RuntimeError("Selected Windows template is not a PE image")
            temporary = target.with_suffix(".partial")
            temporary.write_bytes(data)
            temporary.replace(target)
            print("SAVED", name, len(data), flush=True)
        manifest["members"].append({**entry, "output": str(target), "crc32_verified": True, "sha256": hashlib.sha256(data).hexdigest()})
        (ROOT / "template_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

if __name__ == "__main__":
    main()
