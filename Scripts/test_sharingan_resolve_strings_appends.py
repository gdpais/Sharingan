#!/usr/bin/env python3
"""Exercise the Sharingan strings-conflict resolver on synthetic diff3 conflicts."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parent / "sharingan_resolve_strings_appends.py"


def conflict(ours: str, base: str, theirs: str) -> str:
    return f"<<<<<<< HEAD\n{ours}||||||| base\n{base}=======\n{theirs}>>>>>>> upstream\n"


class ResolveStringsAppendsTests(unittest.TestCase):
    def run_resolver(self, text: str, *flags: str) -> tuple[int, str, str]:
        with tempfile.TemporaryDirectory(prefix="sharingan-strings-") as directory:
            path = Path(directory) / "Localizable.strings"
            path.write_text(text, encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), *flags, str(path)], capture_output=True, text=True, check=False)
            return result.returncode, path.read_text(encoding="utf-8"), result.stderr

    def test_both_sides_appended_keeps_ours_then_theirs(self):
        text = '"a" = "A";\n' + conflict('"ours" = "Ours";\n', "", '"theirs" = "Theirs";\n')
        code, out, _ = self.run_resolver(text)
        self.assertEqual(code, 0)
        self.assertEqual(out, '"a" = "A";\n"ours" = "Ours";\n"theirs" = "Theirs";\n')

    def test_rebrand_changes_only_upstream_values(self):
        theirs = '/* OpenDesign */\n"Refresh Sharingan" = "Sign in, then refresh Sharingan. Run sharingan.";\n'
        ours = '"Sharingan ours" = "Keep Sharingan here";\n'
        code, out, _ = self.run_resolver(conflict(ours, "", theirs), "--rebrand")
        self.assertEqual(code, 0)
        self.assertIn('"Sharingan ours" = "Keep Sharingan here";\n', out)
        self.assertIn('/* OpenDesign */\n', out)
        self.assertIn('"Refresh Sharingan" = "Sign in, then refresh Sharingan. Run sharingan.";\n', out)

    def test_without_rebrand_upstream_values_are_untouched(self):
        code, out, _ = self.run_resolver(conflict("", "", '"k" = "Sharingan";\n'))
        self.assertEqual(code, 0)
        self.assertEqual(out, '"k" = "Sharingan";\n')

    def test_edited_line_conflict_is_left_for_a_human(self):
        text = conflict('"k" = "Sharingan";\n', '"k" = "Sharingan";\n', '"k" = "Sharingan!";\n')
        code, out, stderr = self.run_resolver(text, "--rebrand")
        self.assertEqual(code, 1)
        self.assertEqual(out, text)
        self.assertIn("need a human", stderr)
        self.assertNotIn("duplicate key", stderr)

    def test_duplicate_key_after_resolution_fails(self):
        code, _, stderr = self.run_resolver(conflict('"k" = "A";\n', "", '"k" = "B";\n'))
        self.assertEqual(code, 1)
        self.assertIn("duplicate key after merge: k", stderr)

    def test_conflict_free_file_is_unchanged(self):
        code, out, _ = self.run_resolver('"a" = "A";\n')
        self.assertEqual(code, 0)
        self.assertEqual(out, '"a" = "A";\n')


if __name__ == "__main__":
    unittest.main()
