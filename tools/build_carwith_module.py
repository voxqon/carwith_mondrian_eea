"""Build verified install and source archives without modifying a device."""

import argparse
import hashlib
import json
import lzma
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path
from prepare_carlife_payload import CARLIFE_SHA, CARLIFE_TARGET, MODULE, ROOT, SOURCE as CARLIFE_SOURCE, prepare

COMPONENTS = ROOT / "payloads"
OUT_DIR = ROOT / "dist"
VERSION = dict(line.split("=", 1) for line in (MODULE / "module.prop").read_text().splitlines())["version"]
STEM = f"CarWith_mondrian_EEA_OS3.0.2.0_v{VERSION}"
PAYLOADS = {
    "system/product/app/CarWith/CarWith.apk": (
        COMPONENTS / "CarWith_3.7.3-20251021.apk",
        "081ac798b3a114f14e602b2cb1c5c691ff2cb47009c1a6ba4eebbb4e87caeb2f",
    ),
    "system/system_ext/framework/miui.car.server.jar": (
        COMPONENTS / "miui.car.server.jar",
        "292e38490c907831a0cfde59db383418da34b32d0d102a52ca6ce98e190285f3",
    ),
    CARLIFE_TARGET: (CARLIFE_SOURCE, CARLIFE_SHA),
}
CORE_HASHES = {
    "/system/framework/framework.jar": "6e961ac72a73285005fc68c87e714a18b910a5cb6bbfc13d6bc120ad350de5d7",
    "/system/framework/services.jar": "5fea9ffbfcd324a11dca6b5cdb15730d5c33dcd98e3e70ce85d7ca031d4bfd1a",
    "/system_ext/framework/miui-framework.jar": "b69066e56a7f428effaba2ac36e2a0246c8fe2f48e87df705ab0e42562196422",
    "/system_ext/framework/miui-services.jar": "101ab36c77214b7b451828b4a53d7ac0a6590c98183f05e3426bf3f490b47cf1",
}
PINNED_SOURCES = {
    "META-INF/com/google/android/update-binary": "bcf4b1d9913f3af17755569c853e0b5a75b8005f6a18eb3f86dadcc0e968c29d",
    "licenses/Magisk-GPL-3.0.txt": "589ed823e9a84c56feb95ac58e7cf384626b9cbf4fda2a907bc36e103de1bad2",
    "licenses/Lucide-ISC.txt": "1e7290b35280a048667bbf0ebabac1c7fd52a75300e8b2946ac165715997f2bc",
}
# Explicit lists keep local notes, device scripts and temporary files out of releases.
RUNTIME_FILES = (
    "action.sh", "boot-guard.sh", "control.sh", "customize.sh", "lib.sh",
    "module.prop", "post-mount.sh", "skip_mount", "uninstall.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "carlife-native.sha256", "LICENSE", "THIRD_PARTY_NOTICES.md",
    "licenses/Magisk-GPL-3.0.txt", "licenses/Lucide-ISC.txt",
    "webroot/app.js", "webroot/config.json", "webroot/index.html",
    "webroot/style.css", "webroot/assets/carwith.png", "webroot/assets/icons.svg",
)
BUILD_FILES = (
    "build_carwith_module.py", "build_carwith_overlay.py", "prepare_carlife_payload.py",
    "test_carwith_module.sh", "test_carwith_backend.sh", "test_carwith_install.sh", "test_carwith_webui.cjs",
    "README_carwith.md",
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def copy_verified(source, dest, expected):
    data = source.read_bytes()
    if digest(data) != expected:
        raise ValueError(f"Input hash mismatch: {source}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists() or dest.read_bytes() != data:
        shutil.copyfile(source, dest)
    if digest(dest.read_bytes()) != expected:
        raise ValueError(f"Copied payload mismatch: {dest}")


def normalized(path):
    data = path.read_bytes()
    if path.suffix in (".sh", ".md", ".txt", ".json", ".html", ".css", ".js", ".cjs", ".py", ".prop", ".svg", ".sha256") or path.name in ("updater-script", "update-binary", "skip_mount", ".gitignore", ".gitattributes"):
        data = data.replace(b"\r\n", b"\n")
        assert not data.startswith(b"\xef\xbb\xbf"), f"Unexpected BOM: {path}"
    return data


def pack_payload(image):
    path = MODULE / "carwith-layer.img.xz"
    if path.exists():
        try:
            if lzma.decompress(path.read_bytes(), format=lzma.FORMAT_XZ, memlimit=65 * 1024 * 1024) != image:
                raise ValueError("Cached image mismatch")
            return path.read_bytes()
        except (OSError, ValueError, lzma.LZMAError):
            pass
    # Both managers' BusyBox decoders cap the dictionary at 64 MiB.
    filters = [{"id": lzma.FILTER_LZMA2, "preset": 6, "dict_size": 64 * 1024 * 1024}]
    path.write_bytes(lzma.compress(image, check=lzma.CHECK_CRC32, filters=filters))
    assert lzma.decompress(path.read_bytes()) == image
    return path.read_bytes()


def payload_extent_map(contents):
    image = contents["carwith-layer.img"]
    lines = []
    for name, data in sorted(contents.items()):
        if name == "carwith-layer.img":
            continue
        # This fixed, uncompressed EROFS layout has a block-aligned body and
        # an optional inline tail. Locate and verify both before shipping offsets.
        blocks, tail_size = divmod(len(data), 4096)
        body = data[:blocks * 4096]
        tail = data[blocks * 4096:]
        body_offset = image.find(body) if body else 0
        tail_offset = image.find(tail) if tail else 0
        if body_offset < 0 or body_offset % 4096 or tail_offset < 0:
            raise ValueError(f"Unsupported image layout: {name}")
        if image[body_offset:body_offset + len(body)] + image[tail_offset:tail_offset + tail_size] != data:
            raise ValueError(f"Image extent mismatch: {name}")
        lines.append(f"{body_offset // 4096} {blocks} {tail_offset} {tail_size} {name}\n")
    return "".join(lines).encode("ascii")


def write_archive(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 30, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if name.endswith(".sh") or name.endswith("/update-binary") else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_STORED if name.endswith(".xz") else zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compresslevel=9)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(set(archive.namelist())) == len(contents)
        for name, data in contents.items():
            assert archive.read(name) == data, f"Archive mismatch: {name}"
        if "SHA256SUMS.txt" in contents:
            for line in archive.read("SHA256SUMS.txt").decode().splitlines():
                expected, name = line.split("  ", 1)
                assert digest(archive.read(name)) == expected
    sha = digest(path.read_bytes())
    path.with_suffix(".zip.sha256").write_text(f"{sha}  {path.name}\n", encoding="ascii", newline="\n")
    return {"zip": path.name, "size": path.stat().st_size, "sha256": sha, "entries": len(contents)}


def build_source():
    names = (*RUNTIME_FILES, "README.md", ".gitignore", ".gitattributes")
    contents = {name: normalized(MODULE / name) for name in names}
    contents.update({f"tools/{name}": normalized(ROOT / "tools" / name) for name in BUILD_FILES})
    for source, expected in PAYLOADS.values():
        data = source.read_bytes()
        if digest(data) != expected:
            raise ValueError(f"Source package input hash mismatch: {source}")
        contents[f"payloads/{source.name}"] = data
    return write_archive(OUT_DIR / f"{STEM}_source.zip", contents)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true", help="Package source and original APK/JAR inputs without EROFS tools")
    args = parser.parse_args()
    for name, expected in PINNED_SOURCES.items():
        if digest(normalized(MODULE / name)) != expected:
            raise ValueError(f"Upstream file hash mismatch: {name}")
    missing = [str(source) for source, _ in PAYLOADS.values() if not source.is_file()]
    if missing:
        parser.error("Missing original inputs (see tools/README_carwith.md):\n" + "\n".join(missing))
    if args.source_only:
        print(json.dumps(build_source(), indent=2))
        return
    for target, (source, sha) in PAYLOADS.items():
        copy_verified(source, MODULE / target, sha)
    native, carlife = prepare()
    subprocess.run([sys.executable, str(ROOT / "tools/build_carwith_overlay.py")], check=True)
    payload_contents = {
        name: (MODULE / name).read_bytes()
        for name in ("carwith-layer.img", *PAYLOADS, *native)
    }
    for name, (_, sha) in PAYLOADS.items():
        assert digest(payload_contents[name]) == sha
    for name, sha in native.items():
        assert digest(payload_contents[name]) == sha
    packed = pack_payload(payload_contents["carwith-layer.img"])
    extent_map = payload_extent_map(payload_contents)
    packed_sha = digest(packed)
    packed_checksum = (
        f"{packed_sha}  carwith-layer.img.xz\n"
        f"{digest(extent_map)}  payload.map\n"
    ).encode("ascii")
    (MODULE / "payload.sha256").write_bytes(packed_checksum)
    (MODULE / "payload.map").write_bytes(extent_map)
    manifest = {
        "module_id": "carwith_mondrian_eea",
        "module_version": VERSION,
        "created": "2026-10-30",
        "default_deployment": "off",
        "modified_or_resigned": False,
        "apatch_mount": "Read-only EROFS and OverlayFS with relative lower paths; staging mount detached after setup; skip_mount always set.",
        "layer_sha256": digest((MODULE / "carwith-layer.img").read_bytes()),
        "packaging": {
            "format": "xz-image-with-verified-extents",
            "dictionary_bytes": 64 * 1024 * 1024,
            "sha256": packed_sha,
            "extent_map_sha256": digest(extent_map),
            "unpacked_bytes": sum(map(len, payload_contents.values())),
            "unpacked_files": len(payload_contents),
        },
        "source_rom": "mondrian_images_OS3.0.8.0.VMNCNXM_20260601.0000.00_15.0_cn_dd8b3061a3.tgz",
        "source_rom_sha256": "bdf0e0889fb4722f15862eaedf1e6e15a4bb84a4cdaf029ebedc3a512922c668",
        "target_rom": "mondrian_eea_global_images_OS3.0.2.0.VMNEUXM_20260319.0000.00_15.0_eea_b3e48db574.tgz",
        "target_rom_sha256": "43f6b6c97db407304ee711d116f231435e65c3aaef92e2bd91f63fdc7964050d",
        "target_core_sha256": CORE_HASHES,
        "carlife": carlife,
        "files": [
            {"path": path, "sha256": sha, "size": (MODULE / path).stat().st_size}
            for path, (_, sha) in PAYLOADS.items()
        ],
        "native_files": [
            {"path": path, "sha256": sha, "size": (MODULE / path).stat().st_size}
            for path, sha in native.items()
        ],
        "validation_scope": "Host checks only for this release; device and head-unit validation pending.",
    }
    (MODULE / "payload-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    contents = {
        name: normalized(MODULE / name)
        for name in (*RUNTIME_FILES, "payload-manifest.json")
    }
    contents["carwith-layer.img.xz"] = packed
    contents["payload.map"] = extent_map
    contents["payload.sha256"] = packed_checksum
    contents["SHA256SUMS.txt"] = "".join(
        f"{digest(data)}  {name}\n" for name, data in sorted(contents.items())
    ).encode("ascii")
    (MODULE / "SHA256SUMS.txt").write_bytes(contents["SHA256SUMS.txt"])
    install = write_archive(OUT_DIR / f"{STEM}_Magisk_APatch_WebUI.zip", contents)
    source = build_source()
    shutil.copyfile(MODULE / "README.md", OUT_DIR / "CarWith_Module_使用说明.md")
    report = {
        "install": install, "source": source,
        "payloads_verified": True, "carlife_native_entries_verified": len(native),
        "packed_payload_files_verified": len(payload_contents),
        "archive_checksums_verified": True, "default_deployment": "off", "device_tested": False,
    }
    (OUT_DIR / f"{STEM}_verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
