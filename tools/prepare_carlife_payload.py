"""Prepare the pinned, signed Xiaomi CarLife APK and its preinstalled libraries."""

import hashlib
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT
SOURCE = ROOT / "payloads/CarLife_xiaomi_8.8.4_273.apk"
CARLIFE_SHA = "00df4aaacbbc5837f3a0ef17fc55dfabf038596dd27b652cfb23c9722770a994"
CARLIFE_CERT = "509e03e376b676b25adc41c3dbda6dfa5d0ff12dba1c8c0ca32ad110eea78667"
CARLIFE_TARGET = "system/product/app/CarLife/CarLife.apk"
CARLIFE_NATIVE_SHA = "420c6de2436243a6d09889e1d6e50fae5aea6aa3224e8cd007f6c04053f1ba78"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def native_hashes():
    data = (MODULE / "carlife-native.sha256").read_bytes()
    if sha256(data) != CARLIFE_NATIVE_SHA:
        raise ValueError("CarLife native checksum manifest mismatch")
    return {
        "system/product/app/CarLife/lib/arm64/" + name: digest
        for digest, name in (line.split("  ", 1) for line in data.decode("ascii").splitlines())
    }


def prepare():
    data = SOURCE.read_bytes()
    if sha256(data) != CARLIFE_SHA:
        raise ValueError("CarLife input hash mismatch")
    target = MODULE / CARLIFE_TARGET
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or sha256(target.read_bytes()) != CARLIFE_SHA:
        shutil.copyfile(SOURCE, target)
    native = {}
    with zipfile.ZipFile(SOURCE) as archive:
        assert archive.testzip() is None
        for name in sorted(archive.namelist()):
            if not name.startswith("lib/"):
                continue
            if not re.fullmatch(r"lib/arm64-v8a/[A-Za-z0-9_.+-]+\.so", name):
                raise ValueError(f"Unexpected native entry: {name}")
            payload = archive.read(name)
            relative = "system/product/app/CarLife/lib/arm64/" + name.rsplit("/", 1)[1]
            destination = MODULE / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists() or destination.read_bytes() != payload:
                destination.write_bytes(payload)
            native[relative] = sha256(payload)
    assert len(native) == 49
    actual = {p.relative_to(MODULE).as_posix() for p in (target.parent / "lib").rglob("*") if p.is_file()}
    assert actual == set(native), "Unexpected stale native libraries in module"
    checksum = "".join(
        f"{digest}  {Path(name).name}\n" for name, digest in sorted(native.items())
    ).encode("ascii")
    assert sha256(checksum) == CARLIFE_NATIVE_SHA
    (MODULE / "carlife-native.sha256").write_bytes(checksum)
    provenance = {
        "package": "com.baidu.carlife.xiaomi",
        "app_name": "智能车载百度CarLife+组件",
        "version_name": "8.8.4",
        "version_code": 273,
        "minimum_version_code_required_by_carwith": 220,
        "sha256": CARLIFE_SHA,
        "signer_certificate_sha256": CARLIFE_CERT,
        "signature_verification": "Android apksig 8.7.3: v1 and v2 verified for SDK 23-35",
        "downloaded": "2026-10-30",
        "source_kind": "Third-party mirror; not extracted from the mondrian ROMs in this workspace",
        "source_page": "https://memeosupdates.com/apps/com.baidu.carlife.xiaomi/273",
        "source_file": "https://download.memeosupdates.com/com.baidu.carlife.xiaomi_8.8.4_MemeOSUpdates.com.apk",
        "publisher_certificate_cross_check": {
            "source_page": "https://carlife.baidu.com/carlife/carowner",
            "store_page": "https://mobile.baidu.com/item?pid=1486333&source=appbaidu",
            "apk_source": "https://gdown.baidu.com/appcenter/pkg/upload/44f05df5003ea4221a7a6697b525d4f8?prodid=2",
            "reference_package": "com.baidu.carlife",
            "reference_version": "8.9.5 (283)",
            "certificate_matches": True,
            "note": "The publisher APK is only a signing reference and is not bundled.",
        },
        "modified_or_resigned": False,
        "extract_native_libs": True,
        "native_library_entries": len(native),
        "native_checksum_sha256": sha256(checksum),
        "device_validation": "Pending",
    }
    return native, provenance


if __name__ == "__main__":
    native, provenance = prepare()
    print(json.dumps({
        "apk_sha256": CARLIFE_SHA,
        "native_entries": len(native),
        "native_checksum_sha256": provenance["native_checksum_sha256"],
    }, indent=2))
