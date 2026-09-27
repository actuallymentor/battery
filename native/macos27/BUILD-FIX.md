# Build-only correction: macOS 27 SDK / linker mismatch

## Observed failure

The user ran `bash tests/run-tests.sh && bash install.command` with `(base)`
in the prompt. The first compilation failed with:

```
ld: tapi error: malformed file
libSystem.B.tbd: error: unknown architecture
arm64e.x1-macos, arm64e.x1-maccatalyst
```

The test script uses `set -e` and started with `cc`. The failure therefore
prevented the command after `&&` from executing: that attempt did NOT replace
the working 0.1.0 installation. The identical retry with `install.command -v`
never reached the installer either; that installer has no `-v` option.

The error is an SDK-stub parser/linker incompatibility, not a battery-runtime
failure. Conda selecting an older compiler or linker is plausible, but the
provided output does not identify the executable path. A mismatched Apple
Xcode/Command Line Tools installation can produce the same class of failure.
The new helper reports its exact selected paths rather than assuming a cause.

## Correction

- Build the portable C tests with Apple clang on macOS, not bare PATH-resolved cc.
- Resolve compiler, ld and SDK from one selected Apple developer directory.
- Apply the resolved SDK with `-isysroot` and prioritize that ld directory with
  `-B`; build children do not inherit Conda/toolchain/library/SDK overrides.
- Preserve an explicit `DEVELOPER_DIR` or use the globally selected Apple tools.
  No global `xcode-select --switch` operation is performed.
- Keep the invoking shell's Python and GitHub CLI available.
- Add a compile/link-only smoke check before any privileged installation work.
- Share the build logic between tests and installer, including the PR payload.
- Add a read-only/build-only diagnostics entry point. No Battery helper executes.

An already incompatible/incomplete Apple developer installation is not repaired
by this code. Update its Command Line Tools/Xcode together or explicitly select
an existing matched installation. Do not delete/edit the SDK `.tbd` files, switch
off OS protections, strip architecture entries, or skip compilation checks.

Examples, run separately and stop on failure:

```bash
bash scripts/check-toolchain.command
bash tests/run-tests.sh
# Quit Battery first; this next command DOES install the backend:
bash install.command
```

For detailed compiler/linker output:

```bash
B27_BUILD_VERBOSE=1 bash scripts/check-toolchain.command
```

To select an existing Apple CLT installation for THIS process only:

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools bash tests/run-tests.sh
```

If using this override, pass the same DEVELOPER_DIR to installation/publication.
Its tools must be compatible with its own SDK; the override is not a substitute
for updating an incomplete or outdated installation.

## Contribution packaging

`contribution/upstream.patch` includes these corrected scripts and tests. The
publisher uses a fresh local workspace `~/Developer/battery-fixed-ceiling-buildfix1`
to avoid retaining the broken runner from a previous prepare-only attempt.
The upstream branch name and draft-only behaviour are unchanged; no force-push
is added. If a branch with divergent commits is already published, a normal
push will fail rather than overwrite those commits. Reconcile it manually.
No fork, push, or pull request has been performed in this build correction.

## References checked September 17, 2026

- Apple: Building from the Command Line with Xcode FAQ (tool selection/SDK):
  https://developer.apple.com/library/archive/technotes/tn2339/_index.html
- Apple: Installing the command-line tools:
  https://developer.apple.com/documentation/xcode/installing-the-command-line-tools
- Clang command-line reference (-B, -isysroot):
  https://clang.llvm.org/docs/ClangCommandLineReference.html
- Flutter's upstream September 12, 2026 toolchain fix documents the same new
  arm64e.x1 SDK-stub parser issue; it is not proof the user's linker is Flutter's:
  https://chromium.googlesource.com/external/github.com/flutter/flutter/+/2553f89be1efa62eeb7b3aeea68fc9f80336ee54
