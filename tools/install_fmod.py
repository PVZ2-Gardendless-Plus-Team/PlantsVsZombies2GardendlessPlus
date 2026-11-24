#!/usr/bin/env python3
"""Installs the FMOD GDExtension (utopia-rise/fmod-gdextension) into addons/fmod.

The addon is not committed: its release bundles the FMOD Engine libraries,
which FMOD's licence lets a game ship inside a build but not be republished
in a public source repository. Everyone runs this once instead:

    python tools/install_fmod.py            # desktop libraries only
    python tools/install_fmod.py --all      # also Android and iOS

Re-running replaces the addon with the pinned release. Once it is installed,
the game's audio switches from the Godot fallback to FMOD by itself.

The pinned release carries FMOD Engine 2.03.06. Banks built with any FMOD
Studio 2.03.x (the runner uses 2.03.14) load on it; a 2.04 Studio would need
a newer addon. By downloading it you accept FMOD's EULA
(https://www.fmod.com/legal); the project must be registered with FMOD
before a release ships.
"""

import argparse
import hashlib
import io
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

VERSION = "6.1.0-4.5.0"
URL = f"https://github.com/utopia-rise/fmod-gdextension/releases/download/{VERSION}/addons.zip"
SHA256 = "8796f6cd1cb38bf7ff4da2648f8af2695244ffdb80a7ac4ab8a171ca44895713"
MOBILE = ("fmod/libs/android/", "fmod/libs/iOS/")

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "addons" / "fmod"


def fetch(source: str | None) -> bytes:
    if source:
        data = Path(source).read_bytes()
    else:
        print(f"Downloading fmod-gdextension {VERSION} ...")
        with urllib.request.urlopen(URL) as r:
            data = r.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SHA256:
        sys.exit(f"Checksum mismatch: got {digest}, expected {SHA256}")
    return data


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--all", action="store_true", help="also install the Android and iOS libraries")
    ap.add_argument("--zip", help="use an already downloaded addons.zip instead of downloading")
    args = ap.parse_args()

    archive = zipfile.ZipFile(io.BytesIO(fetch(args.zip)))
    if DEST.exists():
        shutil.rmtree(DEST)
    count = 0
    for info in archive.infolist():
        name = info.filename
        if not name.startswith("fmod/") or info.is_dir():
            continue
        if not args.all and name.startswith(MOBILE):
            continue
        target = (DEST.parent / name).resolve()
        if DEST.resolve() not in target.parents:
            sys.exit(f"Refusing to write outside addons/fmod: {name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(info))
        count += 1
    print(f"Installed {count} files to {DEST.relative_to(ROOT)}.")
    print("Open the project in Godot once (or run `godot --headless --import`); "
          "the boot log should then read backend=fmod.")


if __name__ == "__main__":
    main()
