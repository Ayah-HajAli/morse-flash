#!/usr/bin/env python3
"""
One-shot setup: run this AFTER `flutter create --org com.example morse_flash_app`,
pointing it at that generated project folder. It will:

  1. Copy this repo's lib/ and pubspec.yaml into the target project
     (replacing the default counter-app files).
  2. Add the camera + flashlight permission lines to
     AndroidManifest.xml and Info.plist (only if not already present).
  3. Run `flutter pub get` in the target project.

Usage (from inside the extracted morse_flash/ folder):
    python3 scripts/setup.py /path/to/morse_flash_app

Or, if morse_flash_app is a sibling folder next to morse_flash/:
    python3 scripts/setup.py ../morse_flash_app
"""
import shutil
import subprocess
import sys
from pathlib import Path

ANDROID_PERMISSIONS = [
    '    <uses-permission android:name="android.permission.CAMERA"/>\n',
    '    <uses-permission android:name="android.permission.FLASHLIGHT"/>\n',
]

IOS_PERMISSION_KEY = "NSCameraUsageDescription"
IOS_PERMISSION_BLOCK = (
    "\t<key>NSCameraUsageDescription</key>\n"
    "\t<string>Camera access is needed to receive Morse flashes from another phone.</string>\n"
)


def fail(msg: str):
    print(f"\n\u2717 {msg}")
    sys.exit(1)


def copy_source(repo_root: Path, target: Path):
    src_lib = repo_root / "lib"
    src_pubspec = repo_root / "pubspec.yaml"
    if not src_lib.is_dir() or not src_pubspec.is_file():
        fail(f"Couldn't find lib/ and pubspec.yaml next to this script (looked in {repo_root}).")

    dst_lib = target / "lib"
    if dst_lib.exists():
        shutil.rmtree(dst_lib)
    shutil.copytree(src_lib, dst_lib)
    shutil.copy2(src_pubspec, target / "pubspec.yaml")
    print(f"\u2713 Copied lib/ and pubspec.yaml into {target}")


def patch_android_manifest(target: Path):
    manifest = target / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        print(f"! Skipped Android manifest patch — not found at {manifest} "
              f"(run `flutter create .` inside the project if you need Android support).")
        return

    text = manifest.read_text()
    if "android.permission.CAMERA" in text:
        print("\u2713 AndroidManifest.xml already has the camera permission — left as-is.")
        return

    lines = text.splitlines(keepends=True)
    insert_at = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("<manifest") and stripped.endswith(">"):
            insert_at = i + 1
            break
    if insert_at is None:
        fail("Couldn't find the <manifest ...> opening tag in AndroidManifest.xml — add the "
             "permission lines manually (see README).")

    lines[insert_at:insert_at] = ANDROID_PERMISSIONS
    manifest.write_text("".join(lines))
    print("\u2713 Added camera + flashlight permissions to AndroidManifest.xml")


def patch_ios_plist(target: Path):
    plist = target / "ios" / "Runner" / "Info.plist"
    if not plist.is_file():
        print(f"! Skipped iOS Info.plist patch — not found at {plist} "
              f"(run `flutter create .` inside the project if you need iOS support).")
        return

    text = plist.read_text()
    if IOS_PERMISSION_KEY in text:
        print("\u2713 Info.plist already has the camera usage description — left as-is.")
        return

    idx = text.rfind("</dict>")
    if idx == -1:
        fail("Couldn't find a closing </dict> in Info.plist — add the permission key manually "
             "(see README).")

    patched = text[:idx] + IOS_PERMISSION_BLOCK + text[idx:]
    plist.write_text(patched)
    print("\u2713 Added NSCameraUsageDescription to Info.plist")


def run_pub_get(target: Path):
    print("\nRunning `flutter pub get`\u2026")
    result = subprocess.run(["flutter", "pub", "get"], cwd=target)
    if result.returncode != 0:
        fail("`flutter pub get` failed — scroll up for the error.")
    print("\u2713 Dependencies fetched.")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)

    target = Path(sys.argv[1]).expanduser().resolve()
    repo_root = Path(__file__).resolve().parent.parent

    if not target.is_dir():
        fail(f"{target} doesn't exist. Run `flutter create --org com.example morse_flash_app` first.")
    if not (target / "pubspec.yaml").is_file():
        fail(f"{target} doesn't look like a Flutter project (no pubspec.yaml found).")

    copy_source(repo_root, target)
    patch_android_manifest(target)
    patch_ios_plist(target)
    run_pub_get(target)

    print(f"\nAll set. Next:\n  cd {target}\n  flutter devices   # confirm a real phone is connected\n  flutter run")


if __name__ == "__main__":
    main()
