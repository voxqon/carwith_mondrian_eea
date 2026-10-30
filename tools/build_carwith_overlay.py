"""Build a small read-only EROFS layer with original payloads and Android modes."""

import hashlib
import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from prepare_carlife_payload import CARLIFE_SHA, MODULE, native_hashes

PAYLOADS = {
    "product/app/CarWith/CarWith.apk": "081ac798b3a114f14e602b2cb1c5c691ff2cb47009c1a6ba4eebbb4e87caeb2f",
    "product/app/CarLife/CarLife.apk": CARLIFE_SHA,
    "system_ext/framework/miui.car.server.jar": "292e38490c907831a0cfde59db383418da34b32d0d102a52ca6ce98e190285f3",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=MODULE / "carwith-layer.img")
    parser.add_argument("--mkfs", default=os.environ.get("EROFS_MKFS"))
    args = parser.parse_args()
    mkfs = args.mkfs or shutil.which("mkfs.erofs")
    if not mkfs:
        parser.error("Set EROFS_MKFS to mkfs.erofs 1.8.10-gee46dd74 with Android fs-config and SELinux support")
    image = args.output.resolve()
    payloads = {**PAYLOADS, **{name.removeprefix("system/"): sha for name, sha in native_hashes().items()}}
    with tempfile.TemporaryDirectory(prefix="cw-erofs-") as temporary:
        stage = Path(temporary)
        source = stage / "source"
        source.mkdir()
        contexts = stage / "file_contexts"
        contexts.write_text("/.* u:object_r:system_file:s0\n", encoding="ascii")
        directories = {"/"}
        for name, expected in payloads.items():
            data = (MODULE / "system" / name).read_bytes()
            assert hashlib.sha256(data).hexdigest() == expected
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            directories.update(parent.as_posix() for parent in Path(name).parents if str(parent) != ".")
        config = stage / "fs_config"
        config.write_text(
            "".join(f"{name} 0 0 0755\n" for name in sorted(directories)) +
            "".join(f"{name} 0 0 0644\n" for name in sorted(payloads)),
            encoding="ascii",
        )
        subprocess.run([
            mkfs,
            "--all-root", "-T1793318400",
            "-U3ed095d0-12a6-4f9a-94b2-3eeb94a37fb7",
            f"--fs-config-file={config.as_posix()}",
            f"--file-contexts={contexts.as_posix()}",
            str(image), str(source),
        ], check=True)
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    assert digest == "ab9b57795fb1cd4bbc2b483673bab1154c7ee0ddf1ad6aefce2c9d1274a7c4a6", f"Unexpected layer SHA256: {digest}"
    print(f"Image: {image} ({image.stat().st_size} bytes)")
    print(f"SHA256: {digest}")


if __name__ == "__main__":
    main()
