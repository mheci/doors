"""Unit tests for /usr/bin/doors-recipe (stdlib unittest + ruamel.yaml).

Run: python3 -m unittest discover -s tests -v
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "files/common/usr/bin/doors-recipe"


def load_tool():
    spec = importlib.util.spec_from_loader("doors_recipe", loader=None)
    module = importlib.util.module_from_spec(spec)
    exec(compile(TOOL.read_text(), str(TOOL), "exec"), module.__dict__)
    return module


class RecipeToolTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool = load_tool()

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="doors-recipe-test."))
        self.repo = self.tmp / "repo"
        self.repo.mkdir()
        for entry in ("recipes", "files", "modules"):
            shutil.copytree(ROOT / entry, self.repo / entry, symlinks=True)
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        for cmd in (["git", "init", "-q", "-b", "main"], ["git", "add", "-A"],
                    ["git", "commit", "-q", "-m", "seed"]):
            subprocess.run(cmd, cwd=self.repo, check=True, env=env)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_tool(self, *argv, expect=0):
        out = self._capture(list(argv) + ["--json", "--repo", str(self.repo)], expect)
        return json.loads(out)

    def _capture(self, argv, expect):
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = self.tool.main(argv)
        self.assertEqual(code, expect, buf.getvalue())
        return buf.getvalue()

    def git_diff(self):
        return subprocess.run(["git", "diff"], cwd=self.repo, check=True, text=True,
                              stdout=subprocess.PIPE).stdout

    def added_lines(self):
        return [l[1:].strip() for l in self.git_diff().splitlines()
                if l.startswith("+") and not l.startswith("+++")]

    def removed_lines(self):
        return [l[1:].strip() for l in self.git_diff().splitlines()
                if l.startswith("-") and not l.startswith("---")]

    # -- structural ---------------------------------------------------------
    def test_recipes_round_trip_unchanged(self):
        for recipe in (self.repo / "recipes").rglob("*.yml"):
            yaml, data = self.tool.load_yaml(recipe)
            self.tool.dump_yaml(yaml, data, recipe)
        self.assertEqual(self.git_diff(), "")

    def test_validate_passes_on_tracked_recipes(self):
        self.assertTrue(self.run_tool("validate")["valid"])

    def test_show_lists_declared_state(self):
        state = self.run_tool("show")
        self.assertIn("common", state["rpm"])
        self.assertIn("gnome", state["rpm"])
        self.assertIn("kinoite", state["rpm"])
        self.assertIn("system", state["flatpak"])
        self.assertIn("opencode", state["mise"])
        self.assertIn("doors-hermes-install.service", state["systemd"]["user"]["enabled"])

    # -- rpm ----------------------------------------------------------------
    def test_add_rpm_appends_only_the_package_line(self):
        result = self.run_tool("add", "rpm", "tmux")
        self.assertEqual(result["changed"], ["tmux"])
        self.assertEqual(self.added_lines(), ["- tmux"])
        self.assertEqual(self.removed_lines(), [])
        # idempotent
        self.assertEqual(self.run_tool("add", "rpm", "tmux")["changed"], [])

    def test_add_rpm_profile(self):
        self.run_tool("add", "rpm", "--profile", "kinoite", "htop")
        self.assertIn("recipes/modules/kinoite.yml", self.git_diff())
        self.assertEqual(self.added_lines(), ["- htop"])

    def test_remove_last_rpm_keeps_following_comments(self):
        state = self.run_tool("show")
        last = state["rpm"]["common"][-1]
        self.run_tool("remove", "rpm", last)
        self.assertEqual(self.removed_lines(), [f"- {last}"])
        self.assertEqual(self.added_lines(), [])
        self.run_tool("add", "rpm", last)
        self.assertEqual(self.git_diff(), "")

    def test_refuses_excluded_package(self):
        result = self.run_tool("add", "rpm", "firefox", expect=1)
        self.assertFalse(result["ok"])
        self.assertIn("deliberately removes", result["error"])

    def test_rejects_invalid_names(self):
        self.run_tool("add", "rpm", "bad;name", expect=2)
        self.run_tool("add", "flatpak", "notanid", expect=2)
        self.run_tool("add", "karg", "has space", expect=2)
        self.run_tool("enable", "unit", "noext", expect=2)

    def test_remove_unknown_rpm_fails_unless_ignored(self):
        self.run_tool("remove", "rpm", "definitely-not-there", expect=1)
        self.assertEqual(self.run_tool("remove", "rpm", "definitely-not-there", "--ignore-missing")["changed"], [])

    # -- flatpak / kargs / units / mise / files ------------------------------
    def test_flatpak_scopes(self):
        self.run_tool("add", "flatpak", "org.gnome.Boxes")
        self.run_tool("add", "flatpak", "--scope", "user", "org.gnome.Boxes")
        # the user scope declares no apps yet, so its install key is created
        self.assertEqual(self.added_lines(), ["- org.gnome.Boxes", "install:", "- org.gnome.Boxes"])
        self.run_tool("remove", "flatpak", "org.gnome.Boxes")
        self.run_tool("remove", "flatpak", "--scope", "user", "org.gnome.Boxes")
        self.assertEqual(self.git_diff(), "")

    def test_kargs(self):
        self.run_tool("add", "karg", "foo=bar")
        self.assertEqual(self.added_lines(), ["- foo=bar"])
        self.run_tool("remove", "karg", "foo=bar")
        self.assertEqual(self.git_diff(), "")

    def test_unit_moves_between_lists(self):
        self.run_tool("enable", "unit", "foo.service")
        result = self.run_tool("disable", "unit", "foo.service")
        self.assertEqual(result["changed"], ["-enabled:foo.service", "+disabled:foo.service"])
        state = self.run_tool("show")["systemd"]["system"]
        self.assertIn("foo.service", state["disabled"])
        self.assertNotIn("foo.service", state["enabled"])

    def test_mise_add_update_remove(self):
        self.assertEqual(self.run_tool("add", "mise", "ripgrep", "14.1.0")["changed"], ["ripgrep=14.1.0"])
        self.assertEqual(self.run_tool("add", "mise", "ripgrep", "14.1.0")["changed"], [])
        self.assertEqual(self.run_tool("add", "mise", "ripgrep")["changed"], ["ripgrep=latest"])
        self.assertEqual(self.run_tool("remove", "mise", "ripgrep")["changed"], ["-ripgrep"])
        self.assertEqual(self.git_diff(), "")

    def test_add_file_only_under_etc_or_usr(self):
        src = self.tmp / "x.conf"
        src.write_text("x\n")
        self.run_tool("add", "file", str(src), "/etc/doors/x.conf")
        self.assertTrue((self.repo / "files/common/etc/doors/x.conf").is_file())
        self.run_tool("add", "file", str(src), "/opt/x.conf", expect=2)
        self.run_tool("add", "file", str(src), "/etc/../x", expect=2)
        self.run_tool("remove", "file", "/etc/doors/x.conf")
        self.assertFalse((self.repo / "files/common/etc/doors/x.conf").exists())

    # -- ship guards --------------------------------------------------------
    def test_ship_requires_changes_and_prefix(self):
        self.run_tool("ship", expect=1)
        self.run_tool("add", "rpm", "tmux")
        result = self.run_tool("ship", "-m", "added tmux", expect=2)
        self.assertIn("commit message", result["error"])

    def test_json_flag_anywhere(self):
        out = self._capture(["--repo", str(self.repo), "show", "--json"], 0)
        self.assertTrue(json.loads(out)["ok"])

    def test_policy_check_flags_missing_source_local(self):
        recipe = self.repo / "recipes/modules/common.yml"
        text = recipe.read_text().replace("  - type: rpm-https\n    source: local\n", "  - type: rpm-https\n", 1)
        self.assertNotEqual(text, recipe.read_text())
        recipe.write_text(text)
        result = self.run_tool("validate", expect=1)
        self.assertIn("source: local", result["error"])


if __name__ == "__main__":
    unittest.main()
