#!/usr/bin/env python3
"""Back up, restore, or import completed local Steam Windows games."""

import ctypes
import argparse
import errno
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
    identity = hashlib.sha256()
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
            # APFS clones preserve mtime and size but have their own inode and ctime.
            identity.update(f"{info.st_ino}:{info.st_ctime_ns}\n".encode())
    return digest.hexdigest(), total, has_exe, identity.hexdigest()


def clone_file(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    clone = libc.clonefile
    clone.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    clone.restype = ctypes.c_int
    if clone(os.fsencode(source), os.fsencode(destination), 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), source)
    return destination


def copy_game_file(source, destination):
    try:
        return clone_file(source, destination)
    except OSError as error:
        if error.errno not in (errno.EXDEV, errno.ENOTSUP, errno.EOPNOTSUPP):
            raise
        return shutil.copy2(source, destination)


def rename_exclusively(source, destination):
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), 4):  # RENAME_EXCL
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)


def wine_running():
    return subprocess.run(["/usr/bin/pgrep", "-x", "wineserver(-arm64|-x86)?"],
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


def import_game(appid, source, steamapps=STEAMAPPS, busy=wine_running,
                steam_open=steam_running, ready=notproton_ready):
    if not appid.isascii() or not appid.isdecimal():
        raise ValueError("The game ID must contain digits only")
    source = source.resolve(strict=True)
    steamapps = steamapps.resolve(strict=True)
    if source == steamapps:
        raise ValueError("Choose a different Steam library as the destination")
    if busy() or steam_open():
        raise RuntimeError("Quit Steam and all Windows games before importing")
    if not ready():
        raise RuntimeError("Install the GameHarbor Steam integration before importing")

    source_manifest = source / ("appmanifest_" + appid + ".acf")
    info = None if source_manifest.is_symlink() else game_info(source_manifest, source)
    if info is None:
        raise ValueError("The source does not have a completed download for this game")
    common = steamapps / "common"
    target = common / info["folder"]
    manifest = steamapps / source_manifest.name
    if target.exists() or target.is_symlink() or manifest.exists() or manifest.is_symlink():
        raise FileExistsError("The destination already has a game folder or manifest for this game")
    if common.is_symlink() or not common.is_dir():
        raise ValueError("The destination must have a real steamapps/common directory")
    original = tree_info(info["source"])
    if not original[2] or original[1] < info["size_on_disk"]:
        raise ValueError("The source game is incomplete or has no Windows executable")

    with tempfile.TemporaryDirectory(prefix=".gameharbor-import-", dir=common) as temp:
        stage = Path(temp)
        files = stage / "files"
        shutil.copytree(info["source"], files, symlinks=True, copy_function=copy_game_file)
        if (tree_info(files)[0] != original[0] or tree_info(info["source"]) != original
                or source_manifest.read_bytes() != info["manifest"]):
            raise RuntimeError("The source game changed during import")
        if busy() or steam_open():
            raise RuntimeError("Steam or a game started during import")
        stored_manifest = stage / source_manifest.name
        stored_manifest.write_bytes(info["manifest"])
        rename_exclusively(files, target)
        try:
            # Link publishes the complete manifest and fails if the name is already taken.
            os.link(stored_manifest, manifest)
        except OSError:
            target.rename(files)
            raise
    return {"game": info["name"], "imported_to": str(target)}


def backup_game(info, manifest, root, busy=wine_running):
    if busy():
        return "skipped: a Wine game is running"
    source = info["source"]
    fingerprint, size, has_exe, source_identity = tree_info(source)
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
    if (old.get("fingerprint") == fingerprint and old.get("folder") == info["folder"]
            and old.get("source_identity") == source_identity):
        return "current"
    if busy():
        return "skipped: a Wine game is running"
    stage = Path(tempfile.mkdtemp(prefix=".building-", dir=game_root))
    retired = None
    moved_current = False
    try:
        shutil.copytree(source, stage / "files", symlinks=True, copy_function=clone_file)
        copied_fingerprint, _, _, snapshot_identity = tree_info(stage / "files")
        if (busy() or manifest.read_bytes() != info["manifest"]
                or tree_info(source) != (fingerprint, size, has_exe, source_identity)
                or copied_fingerprint != fingerprint):
            raise RuntimeError("Game changed during backup; previous copy was kept")
        (stage / "appmanifest.acf").write_bytes(info["manifest"])
        metadata = {k: info[k] for k in ("appid", "name", "folder", "size_on_disk")}
        metadata.update({"fingerprint": fingerprint, "source_identity": source_identity,
                         "snapshot_identity": snapshot_identity,
                         "created": time.strftime("%Y-%m-%d %H:%M:%S")})
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
    if not (snapshot / "files").is_dir():
        raise ValueError("The saved game files changed; no restore was attempted")
    fingerprint, _, _, snapshot_identity = tree_info(snapshot / "files")
    if (fingerprint != metadata.get("fingerprint")
            or metadata.get("snapshot_identity", snapshot_identity) != snapshot_identity):
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
            target.rename(history / "failed-recovery-copy")
        if moved_old:
            (history / "game-before-restore").rename(target)
        raise
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    return {"game": metadata["name"], "restored_to": str(target),
            "previous_files_saved_at": str(history)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--restore", metavar="APPID", help="restore a saved game with Steam closed")
    action.add_argument("--import-game", metavar="APPID", help="copy a completed game without replacing existing files")
    parser.add_argument("--from-steamapps", type=Path, help="source Steam library's steamapps directory")
    parser.add_argument("--to-steamapps", type=Path, help="destination for the import (defaults to the main library)")
    args = parser.parse_args()
    if args.import_game is not None:
        if args.from_steamapps is None:
            parser.error("--import-game requires --from-steamapps")
        result = import_game(args.import_game, args.from_steamapps, args.to_steamapps or STEAMAPPS)
    elif args.from_steamapps is not None or args.to_steamapps is not None:
        parser.error("--from-steamapps and --to-steamapps require --import-game")
    else:
        result = restore(args.restore) if args.restore is not None else run()
    print(json.dumps(result, indent=2))
