#!/usr/bin/env python3
"""Package Spellbook Extended for release.

    python3 tools/build_release.py

Writes dist/SpellbookExtended-v<version>.zip (version from the TOC, dots as
dashes: 0.1.0 -> 0-1-0) and the same files unzipped in
dist/SpellbookExtended-v<version>/.

The zip's single root folder is SpellbookExtended/, because WoW only loads an
addon whose folder matches its TOC name; unpacking into Interface/AddOns (or
uploading to CurseForge) then works as-is.

Only the TOC, the files it lists and the licence notice ship. Blocks between
#@debug@ / #@end-debug@ (TOC) and --@debug@ / --@end-debug@ (Lua) are removed,
as are the do-not-package variants, matching CurseForge's packager markers.
"""
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ADDON = "SpellbookExtended"
ROOT = Path(__file__).resolve().parent.parent
EXTRA_FILES = ["THIRD_PARTY_NOTICES.txt"]

TOC_BLOCK = re.compile(r"^#@(debug|do-not-package)@.*?^#@end-\1@[^\n]*\n?", re.S | re.M)
LUA_BLOCK = re.compile(r"--@(debug|do-not-package)@.*?--@end-\1@[^\n]*\n?", re.S)


def fail(message):
    print("build_release: " + message, file=sys.stderr)
    sys.exit(1)


def strip_toc(text):
    return TOC_BLOCK.sub("", text)


def listed_files(toc_text):
    files = []
    for line in toc_text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def version_of(toc_text):
    match = re.search(r"^## Version:\s*(\S+)", toc_text, re.M)
    if not match:
        fail("no '## Version:' line in the TOC")
    return match.group(1)


def main():
    toc_path = ROOT / f"{ADDON}.toc"
    toc = strip_toc(toc_path.read_text(encoding="utf-8"))
    version = version_of(toc)
    release = f"{ADDON}-v{version.replace('.', '-')}"

    dist = ROOT / "dist"
    staging = dist / release
    target = staging / ADDON
    if staging.exists():
        shutil.rmtree(staging)
    target.mkdir(parents=True)

    (target / toc_path.name).write_text(toc, encoding="utf-8")
    shipped = [toc_path.name]

    for name in listed_files(toc) + EXTRA_FILES:
        source = ROOT / name
        if not source.is_file():
            fail(f"{name} is listed but missing")
        text = source.read_text(encoding="utf-8")
        if source.suffix == ".lua":
            text = LUA_BLOCK.sub("", text)
        if "@debug@" in text or "@do-not-package@" in text:
            fail(f"{name} has an unmatched debug marker")
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding="utf-8")
        shipped.append(name)

    luac = shutil.which("luac5.1") or shutil.which("luac")
    if luac:
        lua_files = [str(target / name) for name in shipped if name.endswith(".lua")]
        result = subprocess.run([luac, "-p", *lua_files], capture_output=True, text=True, cwd=staging)
        if result.returncode != 0:
            fail("syntax error:\n" + result.stderr)
        (staging / "luac.out").unlink(missing_ok=True)

    archive = dist / f"{release}.zip"
    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        folders = sorted({f"{ADDON}/"} | {f"{ADDON}/{Path(n).parent.as_posix()}/" for n in shipped if "/" in n})
        for folder in folders:
            zf.writestr(folder, "")
        for name in sorted(shipped):
            zf.write(target / name, f"{ADDON}/{name}")

    print(f"{archive.relative_to(ROOT)}: {len(shipped)} files, version {version}"
          + ("" if luac else " (luac not found, syntax not checked)"))


if __name__ == "__main__":
    main()
