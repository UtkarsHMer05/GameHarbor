from pathlib import Path
import subprocess
import tempfile

wrapper = Path(__file__).with_name("launch.sh")
game = "/Users/example/Library/Application Support/Steam/steamapps/common/DARK SOULS III/Game/DarkSoulsIII.exe"
with tempfile.TemporaryDirectory() as directory:
    compat = Path(directory) / "compat"
    compat.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
    compat.chmod(0o700)
    result = subprocess.check_output(
        [str(wrapper), str(compat), "waitforexitandrun", game, "argument with spaces"], text=True
    ).splitlines()
    assert result == [
        "waitforexitandrun", str(Path(game).with_name("modengine2_launcher.exe")),
        "-t", "ds3", "-p", "Z:" + game,
        "-c", "Z:" + str(Path(game).with_name("ds3-performance.toml")),
        "argument with spaces",
    ], result
    assert subprocess.run([str(wrapper)], capture_output=True).returncode == 64
    assert subprocess.run(
        [str(wrapper), str(compat), "run", "/wrong.exe"], capture_output=True
    ).returncode == 64
print("Wrapper argument, path and game restriction checks passed")
