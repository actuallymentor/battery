"""Build-tool isolation tests using fake Apple tools. No macOS APIs are used.
These verify selection/arguments/environment, NOT Apple linking compatibility.
"""
from pathlib import Path
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ToolchainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="battery tools ")
        self.base = Path(self.tmp.name)
        self.dev = self.base / "Apple Developer"
        self.tools = self.dev / "usr/bin"
        self.tools.mkdir(parents=True)
        self.sdk = self.dev / "SDKs/MacOSX.sdk"
        self.sdk.mkdir(parents=True)
        self.cc, self.ld = self.tools / "clang", self.tools / "ld"
        self.log = self.base / "compile.json"
        self.xlog = self.base / "xcrun.jsonl"
        self.fail = self.base / "fail-link"
        self.version = self.base / "version"
        self.version.write_text("Apple clang version MOCK")
        python = shlex.quote(sys.executable)
        cc_py = self.base / "cc.py"
        cc_py.write_text(
            "import os, sys, json\nfrom pathlib import Path\n"
            f"version = Path({str(self.version)!r})\n"
            "if '--version' in sys.argv:\n print(version.read_text()); sys.exit(0)\n"
            f"Path({str(self.log)!r}).write_text(json.dumps({{'args':sys.argv[1:],'env':dict(os.environ)}}))\n"
            f"sys.exit(7 if Path({str(self.fail)!r}).exists() else 0)\n"
        )
        self.cc.write_text(f"#!/bin/bash\nexec {python} {shlex.quote(str(cc_py))} \"$@\"\n")
        self.cc.chmod(0o755)
        self.ld.write_text("#!/bin/bash\nexit 0\n"); self.ld.chmod(0o755)
        xrun_py = self.base / "xcrun.py"
        xrun_py.write_text(
            "import os, sys, json\n"
            f"with open({str(self.xlog)!r},'a') as f: f.write(json.dumps(dict(os.environ))+'\\n')\n"
            f"values = {{'clang':{str(self.cc)!r},'ld':{str(self.ld)!r},'sdk':{str(self.sdk)!r}}}\n"
            "key = 'sdk' if '--show-sdk-path' in sys.argv else sys.argv[-1]\n"
            "print(values[key])\n"
        )
        xrun = self.base / "xcrun"
        xrun.write_text(f"#!/bin/bash\nexec {python} {shlex.quote(str(xrun_py))} \"$@\"\n")
        xrun.chmod(0o755)
        select = self.base / "xcode-select"
        select.write_text(f"#!/bin/bash\nprintf '%s\\n' {shlex.quote(str(self.dev))}\n")
        select.chmod(0o755)
        # Only tools resolving macOS developer locations are replaced. env -i
        # and the actual shell argument/environment handling execute unchanged.
        self.helper = self.base / "apple-toolchain.sh"
        text = (ROOT / "scripts/apple-toolchain.sh").read_text()
        text = text.replace('/usr/bin/xcrun', shlex.quote(str(xrun)))
        text = text.replace('/usr/bin/xcode-select', shlex.quote(str(select)))
        self.helper.write_text(text)
        self.environment = dict(os.environ, HOME=str(self.base),
            PATH='/nonexistent-conda:/usr/bin:/bin',
            SDKROOT='/wrong/sdk', TOOLCHAINS='wrong', CC='/wrong/cc', LD='/wrong/ld',
            CFLAGS='-bad', LDFLAGS='-bad', LIBRARY_PATH='/wrong/libs',
            CPATH='/wrong/includes', COMPILER_PATH='/wrong/tools',
            CONDA_PREFIX='/wrong/conda', MACOSX_DEPLOYMENT_TARGET='invalid')
        self.environment.pop('DEVELOPER_DIR', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, tail='b27_apple_clang -arch arm64 input.c -o output', **env):
        command = f"source {shlex.quote(str(self.helper))}; b27_select_apple_toolchain; {tail}"
        return subprocess.run(['/bin/bash', '-eu', '-o', 'pipefail', '-c', command],
            env={**self.environment, **env}, capture_output=True, text=True, timeout=10)

    def test_cleans_compiler_environment(self):
        r=self.run_helper(); self.assertEqual(r.returncode, 0, r.stderr)
        entry=json.loads(self.log.read_text())
        self.assertEqual(entry['env']['SDKROOT'], str(self.sdk))
        self.assertEqual(entry['env']['PATH'], '/usr/bin:/bin:/usr/sbin:/sbin')
        for key in ['TOOLCHAINS','CC','LD','CFLAGS','LDFLAGS','LIBRARY_PATH',
                    'CPATH','COMPILER_PATH','CONDA_PREFIX','MACOSX_DEPLOYMENT_TARGET']:
            self.assertNotIn(key, entry['env'])

    def test_sdk_and_linker_prefix_explicit_even_with_spaces(self):
        r=self.run_helper(); self.assertEqual(r.returncode, 0, r.stderr)
        args=json.loads(self.log.read_text())['args']
        self.assertEqual(args[:4], ['-isysroot', str(self.sdk), '-B', str(self.tools)+'/'])
        self.assertEqual(args[4:], ['-arch', 'arm64', 'input.c', '-o', 'output'])

    def test_xcrun_also_uses_clean_environment(self):
        self.assertEqual(self.run_helper().returncode, 0)
        for raw in self.xlog.read_text().splitlines():
            e=json.loads(raw)
            self.assertNotIn('SDKROOT', e); self.assertNotIn('TOOLCHAINS',e)
            self.assertEqual(e['DEVELOPER_DIR'], str(self.dev))

    def test_honors_explicit_developer_directory(self):
        r=self.run_helper(DEVELOPER_DIR='/custom/Xcode.app/Contents/Developer')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(json.loads(self.log.read_text())['env']['DEVELOPER_DIR'],
                         '/custom/Xcode.app/Contents/Developer')

    def test_rejects_non_apple_compiler(self):
        self.version.write_text('clang version MOCK from third party')
        r=self.run_helper(); self.assertNotEqual(r.returncode,0)
        self.assertIn('not Apple clang',r.stderr); self.assertFalse(self.log.exists())

    def test_rejects_missing_sdk(self):
        self.sdk.rmdir()
        r=self.run_helper(); self.assertNotEqual(r.returncode,0)
        self.assertIn('SDK path is unavailable',r.stderr); self.assertFalse(self.log.exists())

    def test_preflight_does_not_execute_output(self):
        # Mock clang does not create output at all. A test that attempted to
        # execute it would fail; compile-only preflight must succeed.
        r=self.run_helper('b27_toolchain_preflight '+shlex.quote(str(self.base)))
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('not executed',r.stdout)

    def test_preflight_stops_on_linker_error(self):
        self.fail.touch()
        r=self.run_helper('b27_toolchain_preflight '+shlex.quote(str(self.base)))
        self.assertNotEqual(r.returncode,0)
        self.assertIn('no installation or battery-setting change',r.stderr)

    def test_verbose_is_compiler_flag(self):
        r=self.run_helper(B27_BUILD_VERBOSE='1'); self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('-v',json.loads(self.log.read_text())['args'])

    def test_installer_preflight_precedes_privileges(self):
        s=(ROOT/'install.command').read_text()
        self.assertLess(s.index('b27_toolchain_preflight'),s.index('/usr/bin/sudo -v'))
        self.assertIn('b27_apple_clang -arch arm64',s)

    def test_test_runner_uses_helper_on_mac(self):
        s=(ROOT/'tests/run-tests.sh').read_text()
        darwin=s.split('if [[ $(uname -s) == Darwin ]]; then',1)[1].split('\nelse\n',1)[0]
        self.assertNotIn('\ncc ',darwin)
        self.assertIn('b27_apple_clang -arch arm64',darwin)

if __name__ == '__main__':
    unittest.main()
