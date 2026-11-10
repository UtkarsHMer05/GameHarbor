import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("game_file_safety", Path(__file__).with_name("game_file_safety.py"))
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


class GameSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="notproton-safety-test-")
        self.root = Path(self.temp.name)
        self.steamapps = self.root / "steamapps"
        self.game = self.steamapps / "common" / "Example Game"
        self.game.mkdir(parents=True)
        (self.game / "game.exe").write_bytes(b"working game")
        (self.game / "data").mkdir()
        (self.game / "data" / "asset.bin").write_bytes(b"data")
        (self.game / "link").symlink_to("data/asset.bin")
        self.manifest = self.steamapps / "appmanifest_123.acf"
        self.manifest.write_text('"AppState"\n{\n "appid" "123"\n "name" "Example Game"\n'
                                 ' "StateFlags" "4"\n "installdir" "Example Game"\n'
                                 ' "SizeOnDisk" "16"\n "buildid" "1"\n}\n')
        self.backups = self.root / "safety"

    def tearDown(self):
        self.temp.cleanup()

    def scan(self):
        return safety.run(self.steamapps, self.backups, busy=lambda: False, min_free=0)

    def test_saved_copy_survives_removed_game_files(self):
        result = self.scan()
        self.assertEqual(result["games"]["123"]["result"], "saved")
        saved = self.backups / "games/123/current/files"
        (self.game / "game.exe").unlink()
        (self.game / "data" / "asset.bin").unlink()
        self.manifest.write_text(self.manifest.read_text().replace('"SizeOnDisk" "16"', '"SizeOnDisk" "0"'))
        self.scan()
        self.assertEqual((saved / "game.exe").read_bytes(), b"working game")
        self.assertEqual((saved / "data" / "asset.bin").read_bytes(), b"data")
        self.assertTrue((saved / "link").is_symlink())

    def test_incomplete_download_is_not_backed_up(self):
        self.manifest.write_text(self.manifest.read_text().replace('"StateFlags" "4"', '"StateFlags" "1030"'))
        result = self.scan()
        self.assertNotIn("123", result["games"])
        self.assertFalse((self.backups / "games/123/current").exists())

    def test_new_copy_preserves_previous_and_failed_copy_keeps_current(self):
        self.assertEqual(self.scan()["games"]["123"]["result"], "saved")
        (self.game / "game.exe").write_bytes(b"updated game")
        self.assertEqual(self.scan()["games"]["123"]["result"], "saved")
        self.assertEqual((self.backups / "games/123/previous/files/game.exe").read_bytes(), b"working game")
        self.assertEqual((self.backups / "games/123/current/files/game.exe").read_bytes(), b"updated game")
        (self.game / "game.exe").write_bytes(b"another game")
        with patch.object(safety, "clone_file", side_effect=OSError("simulated clone failure")):
            result = self.scan()
        self.assertTrue(result["errors"])
        self.assertEqual((self.backups / "games/123/current/files/game.exe").read_bytes(), b"updated game")

    def test_running_wine_defers_and_traversal_is_rejected(self):
        result = safety.run(self.steamapps, self.backups, busy=lambda: True, min_free=0)
        self.assertIn("deferred", result["status"])
        self.manifest.write_text(self.manifest.read_text().replace('"Example Game"\n "SizeOnDisk"',
                                                                  '"../elsewhere"\n "SizeOnDisk"'))
        self.assertIsNone(safety.game_info(self.manifest, self.steamapps))

    def test_restore_preserves_existing_game_and_manifest(self):
        self.scan()
        (self.game / "game.exe").unlink()
        (self.game / "new-user-file.txt").write_text("keep me")
        self.manifest.write_text(self.manifest.read_text().replace('"SizeOnDisk" "16"', '"SizeOnDisk" "0"'))
        result = safety.restore("123", self.steamapps, self.backups, busy=lambda: False,
                                steam_open=lambda: False, ready=lambda: True)
        self.assertEqual((self.game / "game.exe").read_bytes(), b"working game")
        self.assertIn('"SizeOnDisk" "16"', self.manifest.read_text())
        previous = Path(result["previous_files_saved_at"])
        self.assertEqual((previous / "game-before-restore/new-user-file.txt").read_text(), "keep me")
        self.assertIn('"SizeOnDisk" "0"', (previous / "appmanifest-before-restore.acf").read_text())

    def test_restore_refuses_when_steam_is_running(self):
        self.scan()
        with self.assertRaisesRegex(RuntimeError, "Quit Steam"):
            safety.restore("123", self.steamapps, self.backups, busy=lambda: False,
                           steam_open=lambda: True, ready=lambda: True)
        self.assertEqual((self.game / "game.exe").read_bytes(), b"working game")

    def test_restore_recovers_previous_if_current_is_missing(self):
        self.scan()
        (self.game / "game.exe").write_bytes(b"updated game")
        self.scan()
        shutil.rmtree(self.backups / "games/123/current")
        safety.restore("123", self.steamapps, self.backups, busy=lambda: False,
                       steam_open=lambda: False, ready=lambda: True)
        self.assertEqual((self.game / "game.exe").read_bytes(), b"working game")

    def test_failed_manifest_replacement_rolls_back_game_folder(self):
        self.scan()
        (self.game / "new-user-file.txt").write_text("keep me")
        previous_manifest = self.manifest.read_bytes()
        original_replace = Path.replace

        def fail_manifest_replace(path, target):
            if path.name.startswith(".notproton-restore-"):
                raise OSError("simulated manifest write failure")
            return original_replace(path, target)

        with patch.object(Path, "replace", new=fail_manifest_replace):
            with self.assertRaisesRegex(OSError, "simulated manifest"):
                safety.restore("123", self.steamapps, self.backups, busy=lambda: False,
                               steam_open=lambda: False, ready=lambda: True)
        self.assertEqual((self.game / "new-user-file.txt").read_text(), "keep me")
        self.assertEqual(self.manifest.read_bytes(), previous_manifest)

    def test_restore_refuses_changed_backup(self):
        self.scan()
        (self.backups / "games/123/current/files/game.exe").write_bytes(b"damaged")
        with self.assertRaisesRegex(ValueError, "saved game files changed"):
            safety.restore("123", self.steamapps, self.backups, busy=lambda: False,
                           steam_open=lambda: False, ready=lambda: True)
        self.assertEqual((self.game / "game.exe").read_bytes(), b"working game")


if __name__ == "__main__":
    unittest.main()
