import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "pz_version_watch.py"
spec = importlib.util.spec_from_file_location("pz_version_watch", MODULE_PATH)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)


class VersionWatchTests(unittest.TestCase):
    def test_extracts_branches_only(self):
        fixture = '''
        "108600"
        {
          "buildid" "111"
          "depots"
          {
            "branches"
            {
              "public" { "buildid" "222" "timeupdated" "123" }
              "unstable"
              {
                "buildid" "333"
              }
              "legacy41" { "buildid" "444" }
            }
          }
        }
        '''
        self.assertEqual(watch.read_builds(fixture),
                         {"public": "222", "unstable": "333"})

    def test_no_valid_build_fails_closed(self):
        with self.assertRaises(ValueError):
            watch.read_builds('Login Failure: No Connection')

    def test_does_not_capture_other_sections(self):
        fixture = '"other" { "public" { "buildid" "12" } }'
        with self.assertRaises(ValueError):
            watch.read_builds(fixture)

    def test_title_deterministic(self):
        self.assertEqual(watch.issue_title("public", "123"),
                         "[PZ compatibility] public build 123")


if __name__ == "__main__":
    unittest.main()
