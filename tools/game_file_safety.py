#!/usr/bin/env python3
"""Keep copy-on-write safety copies of completed local Steam Windows games."""

import ctypes
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

STEAMAPPS = Path.home() / "Library/Application Support/Steam/steamapps"
SAFETY = Path.home() / "Library/Application Support/NotProton Game File Safety"
MIN_FREE = 15 * 1024 ** 3


def field(text, key):
    match = re.search(r'"' + re.escape(key) + r'"\s*"((?:[^"\\]|\\.)*)"', text)
    if not match:
        return None
    try:
        return json.loads('"' + match.group(1) + '"')
    except ValueError:
        return None


def game_info(manifest, steamapps):
    raw = manifest.read_bytes()
    text = raw.decode("utf-8", errors="strict")
    appid = field(text, "appid")
    folder = field(text, "installdir")
    size = field(text, "SizeOnDisk")
    if (not appid or not appid.isdecimal() or manifest.name != "appmanifest_" + appid + ".acf"
            or not folder or folder in (".", "..") or "/" in folder or "\\" in folder
            or field(text, "StateFlags") != "4" or not size or not size.isdecimal()
            or int(size) == 0):
        return None
    source = steamapps / "common" / folder
    if source.is_symlink() or not source.is_dir():
        return None
    return {"appid": appid, "name": field(text, "name") or folder,
            "folder": folder, "size_on_disk": int(size), "manifest": raw,
            "source": source}


def tree_info(root):
    digest = hashlib.sha256()
    total = 0
    has_exe = False
    def fail(error):
        raise error

    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=fail):
        dirs.sort()
        files.sort()
        for name in sorted(dirs + files):
            path = Path(directory) / name
            info = path.lstat()
            relative = str(path.relative_to(root))
            if stat.S_ISLNK(info.st_mode):
                kind = "link:" + os.readlink(path)
                if name in dirs:
                    dirs.remove(name)
            elif stat.S_ISDIR(info.st_mode):
                kind = "dir"
            elif stat.S_ISREG(info.st_mode):
                kind = "file"
                total += info.st_size
                has_exe |= path.suffix.lower() == ".exe"
            else:
                raise OSError("Unsupported file type: " + str(path))
            digest.update(json.dumps([relative, kind, stat.S_IMODE(info.st_mode),
                                      info.st_size if kind == "file" else 0,
                                      info.st_mtime_ns], ensure_ascii=True).encode())
            digest.update(b"\n")
    return digest.hexdigest(), total, has_exe


def clone_file(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    clone = libc.clonefile
    clone.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    clone.restype = ctypes.c_int
    if clone(os.fsencode(source), os.fsencode(destination), 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), source)
    return destination


def wine_running():
    return subprocess.run(["/usr/bin/pgrep", "-x", "wineserver"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def steam_running():
    return subprocess.run(["/usr/bin/pgrep", "-x", "steam_osx"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def notproton_ready():
    app = Path("/Applications/Steam.app")
    try:
        plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        inserts = plist.get("LSEnvironment", {}).get("DYLD_INSERT_LIBRARIES", "").split(":")
        return any(Path(path).name == "notproton.dylib" and Path(path).is_file() for path in inserts)
    except (OSError, ValueError):
        return False


def backup_game(info, manifest, root, busy=wine_running):
    source = info["source"]
    fingerprint, size, has_exe = tree_info(source)
    if not has_exe or size < info["size_on_disk"]:
        return "skipped: no Windows executable or incomplete files"
    game_root = root / "games" / info["appid"]
    game_root.mkdir(parents=True, exist_ok=True)
    current = game_root / "current"
    previous = game_root / "previous"
    try:
        old = json.loads((current / "metadata.json").read_text())
    except (OSError, ValueError):
        old = {}
    if old.get("fingerprint") == fingerprint and old.get("folder") == info["folder"]:
        return "current"
    if busy():
        return "skipped: a Wine game is running"
    stage = Path(tempfile.mkdtemp(prefix=".building-", dir=game_root))
    retired = None
    moved_current = False
    try:
        shutil.copytree(source, stage / "files", symlinks=True, copy_function=clone_file)
        if (busy() or manifest.read_bytes() != info["manifest"]
                or tree_info(source)[0] != fingerprint
                or tree_info(stage / "files")[0] != fingerprint):
            raise RuntimeError("Game changed during backup; previous copy was kept")
        (stage / "appmanifest.acf").write_bytes(info["manifest"])
        metadata = {k: info[k] for k in ("appid", "name", "folder", "size_on_disk")}
        metadata.update({"fingerprint": fingerprint, "created": time.strftime("%Y-%m-%d %H:%M:%S")})
        (stage / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        if previous.exists():
            retired = game_root / (".retired-" + stage.name.removeprefix(".building-"))
            previous.rename(retired)
        if current.exists():
            current.rename(previous)
            moved_current = True
        stage.rename(current)
    except Exception:
        if moved_current and not current.exists() and previous.exists():
            previous.rename(current)
        if retired and retired.exists() and not previous.exists():
            retired.rename(previous)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    if retired:
        shutil.rmtree(retired)
    return "saved"


def run(steamapps=STEAMAPPS, root=SAFETY, busy=wine_running, min_free=MIN_FREE):
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".game-safety.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"status": "another scan is running"}
        result = {"checked": time.strftime("%Y-%m-%d %H:%M:%S"), "games": {}, "errors": []}
        if not steamapps.is_dir() or os.stat(steamapps).st_dev != os.stat(root).st_dev:
            result["errors"].append("Default Steam library and safety folder must be on the same volume")
        elif shutil.disk_usage(root).free < min_free:
            result["errors"].append("Less than 15 GiB free; no new copies made")
        elif busy():
            result["status"] = "A Wine game is running; scan deferred"
        else:
            for manifest in sorted(steamapps.glob("appmanifest_*.acf")):
                try:
                    info = game_info(manifest, steamapps)
                    if info:
                        result["games"][info["appid"]] = {"name": info["name"],
                            "result": backup_game(info, manifest, root, busy)}
                except (OSError, ValueError, RuntimeError, shutil.Error) as error:
                    result["errors"].append(manifest.name + ": " + str(error))
        temp = root / ".status.tmp"
        temp.write_text(json.dumps(result, indent=2) + "\n")
        temp.replace(root / "status.json")
        return result


def restore(appid, steamapps=STEAMAPPS, root=SAFETY, busy=wine_running,
            steam_open=steam_running, ready=notproton_ready):
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".game-safety.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A game-file safety scan is running; try again shortly")
        return restore_locked(appid, steamapps, root, busy, steam_open, ready)


def restore_locked(appid, steamapps, root, busy, steam_open, ready):
    if not appid.isdecimal():
        raise ValueError("The game ID must contain digits only")
    if busy() or steam_open():
        raise RuntimeError("Quit Steam and all Windows games before restoring")
    if not ready():
        raise RuntimeError("Install or repair NotProton before restoring; otherwise Steam may remove the files again")
    game_root = root / "games" / appid
    snapshot = game_root / "current"
    if not snapshot.exists():
        snapshot = game_root / "previous"
    metadata = json.loads((snapshot / "metadata.json").read_text())
    folder = metadata.get("folder", "")
    if (metadata.get("appid") != appid or not folder or folder in (".", "..")
            or "/" in folder or "\\" in folder or (snapshot / "files").is_symlink()):
        raise ValueError("The saved game identity is invalid")
    if not (snapshot / "files").is_dir() or tree_info(snapshot / "files")[0] != metadata.get("fingerprint"):
        raise ValueError("The saved game files changed; no restore was attempted")
    saved_manifest = (snapshot / "appmanifest.acf").read_bytes()
    text = saved_manifest.decode("utf-8", errors="strict")
    if (field(text, "appid") != appid or field(text, "installdir") != folder
            or field(text, "StateFlags") != "4"):
        raise ValueError("The saved Steam manifest does not match the game")
    common = steamapps / "common"
    target = common / folder
    manifest = steamapps / ("appmanifest_" + appid + ".acf")
    if target.is_symlink() or manifest.is_symlink() or (target.exists() and not target.is_dir()):
        raise ValueError("The current game or manifest has an unexpected file type")
    if os.stat(common).st_dev != os.stat(root).st_dev:
        raise RuntimeError("The Steam library and safety copies must be on the same volume")
    history = root / "recoveries" / (appid + "-" + time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    history.mkdir(parents=True)
    old_manifest = manifest.read_bytes() if manifest.exists() else None
    if old_manifest is not None:
        (history / "appmanifest-before-restore.acf").write_bytes(old_manifest)
    stage = Path(tempfile.mkdtemp(prefix=".notproton-recovery-", dir=common))
    moved_old = installed = manifest_replaced = False
    try:
        shutil.copytree(snapshot / "files", stage / "files", symlinks=True, copy_function=clone_file)
        if tree_info(stage / "files")[0] != metadata["fingerprint"]:
            raise RuntimeError("The recovery copy did not match the saved files")
        if busy() or steam_open():
            raise RuntimeError("Steam or a game started during recovery; nothing was replaced")
        if target.exists():
            target.rename(history / "game-before-restore")
            moved_old = True
        (stage / "files").rename(target)
        installed = True
        temp_manifest = steamapps / (".notproton-restore-" + uuid.uuid4().hex + ".acf")
        try:
            temp_manifest.write_bytes(saved_manifest)
            temp_manifest.replace(manifest)
            manifest_replaced = True
        finally:
            temp_manifest.unlink(missing_ok=True)
    except Exception:
        if manifest_replaced:
            if old_manifest is None:
                manifest.unlink(missing_ok=True)
            else:
                rollback = steamapps / (".notproton-rollback-" + uuid.uuid4().hex + ".acf")
                rollback.write_bytes(old_manifest)
                rollback.replace(manifest)
        if installed and target.exists():
            shutil.rmtree(target)
        if moved_old:
            (history / "game-before-restore").rename(target)
        raise
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    return {"game": metadata["name"], "restored_to": str(target),
            "previous_files_saved_at": str(history)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--restore", metavar="APPID", help="restore a saved game with Steam closed")
    args = parser.parse_args()
    print(json.dumps(restore(args.restore) if args.restore else run(), indent=2))
