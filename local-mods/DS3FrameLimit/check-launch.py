from pathlib import Path
import configparser
import os
import re
import subprocess
import sys

plugins = Path.home() / "Library/Application Support/notproton/plugins"
config = configparser.ConfigParser(interpolation=None)
config.read(plugins / "ds3-45fps.conf")
key, value = config["NOTPROTON_DS3_45FPS"]["env"].split("=", 1)
assert (key, value) == ("DS3_FRAME_LIMIT_FPS", "40")

launcher = Path(__file__).resolve().parents[2] / "dylib/feats/compat_run.sh"
reserved = re.search(r"np_env_reserved\(\) \{.*?\n\}", launcher.read_text(), re.S).group()
for name, expected in [("NOTPROTON_DS3_FPS", 0), (key, 1)]:
    result = subprocess.run(["/bin/sh", "-c", reserved + '\nnp_env_reserved "$1"', "sh", name])
    assert result.returncode == expected, name

env = os.environ.copy()
env.update(NOTPROTON_DS3_45FPS="1", SteamAppId="374320")
env[key] = value
result = subprocess.run(
    [sys.executable, "-c", "import ctypes, sys; ctypes.CDLL(sys.argv[1])",
     str(plugins / "ds3-frame-limit.dylib")],
    env=env, capture_output=True, text=True, check=True,
)
assert "enabled 40 FPS pacing" in result.stderr, result.stderr
print("Installed descriptor, launcher environment policy and 40 FPS library loading passed.")

config.read(plugins / "sekiro-40fps.conf")
assert config["NOTPROTON_SEKIRO_40FPS"]["requires"] == config["NOTPROTON_DS3_45FPS"]["requires"]
sekiro_key, sekiro_value = config["NOTPROTON_SEKIRO_40FPS"]["env"].split("=", 1)
assert (sekiro_key, sekiro_value) == ("SEKIRO_FRAME_LIMIT_FPS", "40")
result = subprocess.run(["/bin/sh", "-c", reserved + '\nnp_env_reserved "$1"', "sh", sekiro_key])
assert result.returncode == 1
env[sekiro_key] = sekiro_value
for app, ds3, sekiro, expected in [
    ("814380", "0", "1", "enabled 40 FPS pacing for Sekiro"),
    ("814380", "1", "0", ""),
    ("374320", "0", "1", ""),
    ("632360", "1", "1", ""),
    ("374320", "1", "1", "enabled 40 FPS pacing for Dark Souls III"),
]:
    env.update(SteamAppId=app, NOTPROTON_DS3_45FPS=ds3, NOTPROTON_SEKIRO_40FPS=sekiro)
    result = subprocess.run(
        [sys.executable, "-c", "import ctypes, sys; ctypes.CDLL(sys.argv[1])",
         str(plugins / "ds3-frame-limit.dylib")],
        env=env, capture_output=True, text=True, check=True,
    )
    assert expected in result.stderr if expected else "enabled" not in result.stderr, result.stderr
print("Sekiro 40 FPS loading, launcher environment policy, disabled flags and cross-game isolation passed.")
