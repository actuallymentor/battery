import os
import re
import subprocess
import unittest
from pathlib import Path
from shutil import which


ROOT = Path(__file__).resolve().parents[1]
BATTERY_SOURCE = ROOT / "battery.sh"
FUNCTION_NAME = "should_disable_charging_in_range"
FUNCTION_PATTERN = re.compile(
    rf"^function {FUNCTION_NAME}\(\) \{{\n.*?^\}}$",
    re.MULTILINE | re.DOTALL,
)
BASH_PATH = which("bash")
if os.name == "nt":
    candidates = subprocess.run(
        ["where.exe", "bash"], check=False, capture_output=True, text=True
    ).stdout.splitlines()
    BASH_PATH = next(
        (path.strip() for path in candidates if "\\git\\" in path.lower()),
        BASH_PATH,
    )
if BASH_PATH is None:
    raise RuntimeError("bash is required for the synthetic range test")


class RangeHysteresisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = BATTERY_SOURCE.read_text(encoding="utf-8")
        match = FUNCTION_PATTERN.search(source)
        if match is None:
            raise AssertionError(f"{FUNCTION_NAME} was not found in battery.sh")
        cls.function_source = match.group(0)

    def assert_range_action(
        self, expected, is_range, percentage, lower, upper, charging
    ):
        script = f'{self.function_source}\n{FUNCTION_NAME} "$@"\n'
        result = subprocess.run(
            [
                BASH_PATH,
                "-c",
                script,
                "synthetic-range-test",
                str(is_range).lower(),
                str(percentage),
                str(lower),
                str(upper),
                charging,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0 if expected else 1, result.stderr)

    def test_only_disables_while_charging_inside_an_active_range(self):
        self.assert_range_action(True, True, 52, 45, 55, "enabled")
        self.assert_range_action(True, True, 45, 45, 55, "enabled")
        self.assert_range_action(False, True, 44, 45, 55, "enabled")
        self.assert_range_action(False, True, 52, 45, 55, "disabled")
        self.assert_range_action(False, True, 55, 45, 55, "enabled")
        self.assert_range_action(False, False, 52, 45, 55, "enabled")

    def test_maintenance_loop_applies_range_action_before_reenabling(self):
        source = BATTERY_SOURCE.read_text(encoding="utf-8")
        upper_check = source.index('if [[ "$battery_percentage" -ge "$upper_bound"')
        range_check = source.index(
            f'elif {FUNCTION_NAME} "$is_range" "$battery_percentage" '
            '"$lower_bound" "$upper_bound" "$is_charging"; then',
            upper_check,
        )
        lower_check = source.index(
            'elif [[ "$battery_percentage" -lt "$lower_bound"', range_check
        )
        self.assertLess(upper_check, range_check)
        self.assertLess(range_check, lower_check)
        self.assertIn("\n\t\t\tdisable_charging\n", source[range_check:lower_check])


if __name__ == "__main__":
    unittest.main()
