"""Mock/static regression checks. These do NOT prove a physical battery behaviour."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
class IntegrationTests(unittest.TestCase):
    def hook(self,active):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)
            snippet=(ROOT/'src/dispatch-snippet.sh').read_text().replace('/Library/PrivilegedHelperTools/co.palokaj.battery.macos27',tmp)
            (p/'native-charge').write_text('#!/bin/sh\nexit 99\n'); (p/'native-charge').chmod(0o755)
            if active: (p/'active').write_text('0.1.1-ceiling\n')
            (p/'battery-native.sh').write_text('#!/bin/bash\nprintf "<%s>\\n" "$@"\n')
            (p/'battery').write_text('#!/bin/bash\n'+snippet+'\necho legacy\n')
            return subprocess.run(['bash',str(p/'battery'),'maintain','55'],capture_output=True,text=True,timeout=5)
    def test_hook_dormant(self): self.assertEqual(self.hook(False).stdout,'legacy\n')
    def test_hook_arguments(self): self.assertEqual(self.hook(True).stdout,'<maintain>\n<55>\n')
    def test_no_release_bump(self):
        text=(ROOT/'scripts/install-root.sh').read_text()
        self.assertNotIn('v1.3.5',text)
        self.assertNotIn('BATTERY_CLI_VERSION=',(ROOT/'src/dispatch-snippet.sh').read_text())
    def test_no_macos_major_gate(self):
        text=(ROOT/'install.command').read_text()
        self.assertNotIn('cut -d. -f1',text); self.assertIn('"$BUILD/native-charge" probe',text)
    def test_upgrade_preserves_original_snapshot(self):
        text=(ROOT/'install.command').read_text()
        self.assertNotIn('native-charge" stop',text)
        self.assertIn('"$BUILD/native-charge" check-state',text)
    def test_target_has_no_observation_dependency(self):
        text=(ROOT/'src/native-charge.m').read_text()
        self.assertIn('b27_fixed_target([state[@"lower"] intValue], [state[@"upper"] intValue], &target)',text)
        self.assertNotIn('b27_policy_step',text); self.assertNotIn('next.hold_target',text)
    def test_no_smc_writes(self):
        text=(ROOT/'src/native-charge.m').read_text()
        for forbidden in ['CHIE','CH0I','CH0J','IOConnectCallStructMethod','smcWrite','setDischargeSleep']:
            self.assertNotIn(forbidden,text)
        self.assertIn('CFPreferencesSetValue',text)
    def test_csv_does_not_fake_discharge_measurement(self):
        text=(ROOT/'src/native-charge.m').read_text()
        self.assertNotIn(',not discharging,',text)
        self.assertIn(',unknown,%s',text)
        self.assertIn('IORegistryEntryCreateCFProperties',text)
        self.assertIn('Battery amperage: unknown',text)
    def test_restore_before_removal(self):
        text=(ROOT/'scripts/uninstall-root.sh').read_text()
        self.assertLess(text.index('"$ROOT/native-charge" stop'),text.index('launchctl bootout'))
        self.assertLess(text.index('launchctl bootout'),text.index('/bin/rm -rf "$ROOT"'))
    def test_command_validation_before_state_write(self):
        text=(ROOT/'src/native-charge.m').read_text()
        self.assertLess(text.index('argc != 3 || !b27_parse_percent'),text.index('int lock = stateLock()'))
    def test_exact_maintenance_sudo_rules_no_unrestricted_wildcard(self):
        text=(ROOT/'scripts/install-root.sh').read_text()
        self.assertNotIn('NOPASSWD: ALL',text); self.assertNotIn('NOPASSWD: /bin/bash',text)
        self.assertNotIn('NOPASSWD: $ROOT/native-charge maintain *',text)
        self.assertIn('for ((ceiling=1; ceiling<=100; ceiling++))',text)
        for old in ['native-charge charge *','native-charge discharge *','native-charge calibrate']:
            self.assertNotIn(old,text)
    def test_no_app_bundle_replacement(self):
        for file in ['install.command','scripts/install-root.sh']:
            text=(ROOT/file).read_text(); self.assertNotIn('/Applications/',text); self.assertNotIn('curl ',text)
    def test_publisher_is_draft_only(self):
        path=ROOT/'publish.command'
        if not path.exists(): self.skipTest('Publisher distributed separately from upstream source')
        text=path.read_text(); self.assertIn('--draft',text)
        self.assertNotIn('push --force',text); self.assertNotIn('pr merge',text)
        self.assertLess(text.index('bash native/macos27/tests/run-tests.sh'),text.index('push -u origin'))
    def test_range_policy_hardware_claims_excluded(self):
        text=(ROOT/'src/native-charge.m').read_text()
        self.assertIn('Saved range is unsupported',text)
        self.assertIn('PENDING / MISMATCH',text)
        self.assertNotIn('operations.h',text)
if __name__=='__main__': unittest.main()
