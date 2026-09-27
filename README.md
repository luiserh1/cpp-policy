# cpp-policy

Shared, versioned C++ policy: a restricted modern C++23 subset enforced by
Clang warnings, clang-tidy, a suppression audit and a format check.
The rules are in [POLICY.md](POLICY.md).

## Use in a project

```cmake
include(FetchContent)
FetchContent_Declare(cpp_policy
    GIT_REPOSITORY https://github.com/luiserh1/cpp-policy.git
    GIT_TAG        <commit>)   # v0.10.2, the latest release; see CHANGELOG.md
FetchContent_MakeAvailable(cpp_policy)

add_executable(app src/main.cpp)
cpp_policy_apply(app)       # every target you own (configuration fails otherwise)
cpp_policy_layers(          # the modules under src/, from the lowest layer up (POLICY.md 11.1)
    LAYER lowlevel
    LAYER model
    LAYER ui)
cpp_policy_add_checks()     # once: policy-audit, policy-format-check, policy-format-fix
```

Pin the commit a release tag points to, with the tag in a comment, rather
than the tag itself: a tag can be moved to other code later, a commit can't,
and this repository's CMake code runs on every machine that configures the
project (POLICY.md 10). The commit is the line ending in `^{}`:

```
git ls-remote https://github.com/luiserh1/cpp-policy 'refs/tags/v0.10.2*'
```

Don't add `GIT_SHALLOW`: it only works with branch and tag names.

### Upgrading

From the project's root, with a clean working folder:

```
sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.10.2
```

Any copy of this repository's `tools/upgrade.sh` works (from v0.10.1 on): it
fetches the release from the project's `GIT_REPOSITORY` and hands over to the
release's own `upgrade.sh`, which knows what that release changed. It moves the `GIT_TAG` pin and the
CI gate pins to the release's commit (with the tag in the comment), copies
`.clang-tidy`, `.clang-format`, `CMakePresets.json` and `tools/hooks/`, checks
every change, shows
the diff and the release's CHANGELOG entry (follow its "Upgrading a project"
steps), and runs the gate. It commits nothing. `--no-gate` skips the gate.
These are policy files, so in a project that follows `AGENTS.md` the owner
runs it, not an agent.

Copy `.clang-tidy` and `.clang-format` into the project root unchanged. The
copies are for editors: clangd and IDEs look for these files next to the
sources, so they show the same warnings and formatting while you type. The
build never reads them; it always uses this repository's copies. The audit
fails if the copies differ, so the editor and the build can't disagree.

Copy `CMakePresets.json` unchanged too; it defines the presets and workflows
the gate and CI run. A project that uses vcpkg loads vcpkg's toolchain in its
`CMakeLists.txt` instead of in the presets (POLICY.md 1.1). The audit fails if
the presets differ from this repository's.

Start the project's `.gitignore` and `.gitattributes` from this repository's
copies. Projects may add lines, but the audit fails if any of these are
missing (POLICY.md 6.1).

Copy `tools/hooks/` unchanged as well, and enable the hooks once per clone:

```
git config core.hooksPath tools/hooks
```

`pre-commit` runs the suppression audit and format check; `commit-msg` checks
the message (Conventional Commits with a body that says why, POLICY.md 8.2);
`pre-push` runs the full gate and refuses to start while there are
uncommitted changes, so it tests exactly what is pushed. The audit fails if the hooks differ from these,
and configuration warns while a clone hasn't enabled them.

### Continuous integration (GitHub Actions)

This repository's `gate.yml` runs the `check`, `tsan` and `release` workflows
on Linux, Windows and macOS (no `tsan` on Windows), installing LLVM 23 on each
runner. A project calls it from `.github/workflows/ci.yml`, pinned to the same
commit as `GIT_TAG`:

```yaml
name: CI
on:
  push:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  gate:
    uses: luiserh1/cpp-policy/.github/workflows/gate.yml@<commit> # v0.10.2
    with:
      systems: '["linux", "windows", "macos"]'
      vcpkg: true          # if the project has a vcpkg.json
```

The audit fails if the two pins differ, so CI always runs the policy the
build uses. Move both in the same commit when upgrading.

`systems` picks the runners. GitHub's runners are free for public
repositories; private ones spend the account's Actions minutes, and macOS
minutes count ten times as much as Linux ones (Windows twice). A private
project whose developers work on a Mac, where the `pre-push` hook already runs
the gate, can leave macOS out.

## Options (set by presets)

| Option | Default | Meaning |
|---|---|---|
| `CPP_POLICY_SANITIZERS` | `OFF` | ASan + UBSan (ASan only on Windows) |
| `CPP_POLICY_THREAD_SANITIZER` | `OFF` | ThreadSanitizer (not with the option above; not on Windows) |
| `CPP_POLICY_CLANG_TIDY` | `OFF` | Run clang-tidy during the build |
| `CPP_POLICY_HARDENING` | `fast` | Standard library hardening: `none`, `fast`, `debug` |
| `CPP_POLICY_EXCEPTIONS` | `ON` | Exceptions and RTTI |
| `CPP_POLICY_CONFINED_DIRS` | `src/lowlevel` | Where suppressions are allowed |
| `CPP_POLICY_EXCLUDED_DIRS` | `build;out;.git;third_party;external;vcpkg_installed` | Skipped by audit/format |

## Requirements

- LLVM **23.x**: `clang++` (macOS/Linux) or `clang-cl` (Windows), with
  `clang-tidy` and `clang-format` from the same installation
- CMake ≥ 3.29
- Ninja

## Setup per platform

The presets look for LLVM in the standard install locations first, so on most
machines no configuration is needed:

| Platform | Install | Location searched by the presets |
|---|---|---|
| macOS (Apple Silicon) | `brew install llvm ninja` | `/opt/homebrew/opt/llvm/bin` |
| macOS (Intel) | `brew install llvm ninja` | `/usr/local/opt/llvm/bin` |
| Debian / Ubuntu | [apt.llvm.org](https://apt.llvm.org) packages for LLVM 23, plus `ninja-build` | `/usr/lib/llvm-23/bin` |
| Other Linux (e.g. Arch, CachyOS) | The official LLVM 23 release tarball (`LLVM-23.x.y-Linux-X64.tar.xz` from GitHub; check its SHA-256), extracted with `--strip-components=1` into `/usr/lib/llvm-23`, plus Ninja | `/usr/lib/llvm-23/bin` |
| Windows | Official LLVM installer (default path), Ninja, and Visual Studio or Build Tools with the "C++ AddressSanitizer" component (for the Windows SDK, the runtime and `stl_asan.lib`) | `C:\Program Files\LLVM\bin` |

Things to know:

- **macOS:** Xcode puts Apple Clang in `/usr/bin`, and Homebrew does not put
  its LLVM ahead of it. That's why the presets search the Homebrew location
  explicitly. Apple Clang is always rejected: it has its own version numbering
  and ships without clang-tidy.
- **Linux:** distributions often ship an older LLVM, or install it only under
  versioned names (`clang++-23`). The unversioned binaries in
  `/usr/lib/llvm-23/bin` are what the presets use.
- **Windows:** the LLVM that comes with Visual Studio may be older than 23.
  Use the official installer.
- **Windows:** the `win-dev` and `win-check` presets build with AddressSanitizer,
  and the MSVC standard library then links `stl_asan.lib`. It comes with the
  Visual Studio component "C++ AddressSanitizer"
  (`Microsoft.VisualStudio.Component.VC.ASAN`); without it the link fails with
  `could not open 'stl_asan.lib'`.

**Non-standard install locations:** put that LLVM's `bin` directory first in
`PATH` before running CMake. Do not edit `CMakePresets.json`.

If the compiler check fails, the error message names the compiler that was
found. Fix the installation or `PATH`; the check itself is intentional.

## Debugging

Debuggers are not restricted. Use the `debug` preset (`win-debug` on
Windows): a plain Debug build without sanitizers, so stepping follows the
source line by line. `dev` also works on macOS and Linux, but sanitizers slow
the program down; on Windows `win-dev` is optimized and hard to step through.

```
cmake --preset debug
cmake --build --preset debug
lldb build/debug/<program>        # or gdb on Linux
```

Any editor that reads `CMakePresets.json` (Visual Studio, VS Code, CLion, Qt
Creator) can pick the preset and launch its own debugger. Launch settings are
editor-specific, so none are committed (POLICY.md 6.1).

**Visual Studio (Windows):** open the project with *File > Open > Folder*,
not with cmake-gui or a generated `.sln`. Without a preset, CMake picks MSVC's
`cl.exe` and skips the vcpkg toolchain, so configuration fails. With Open
Folder, Visual Studio reads the presets:
- Choose "debug (Windows)" (`win-debug`) in the configuration dropdown. It
  starts on `win-dev`, which is optimized.
- Pick the program as the startup item. The Debug menu stays greyed out until
  you do.
- Program arguments go in `.vs/launch.vs.json` (`"args": [...]`). Right-click
  `CMakeLists.txt` and choose the debug and launch settings to open it. It
  stays uncommitted, since `.vs/` is ignored.
- Ctrl+C in the program's console first stops in the debugger as exception
  `0x40010005` (`DBG_CONTROL_C`). Choose Continue, and the program's own
  handler runs.

To stop in the debugger at a sanitizer error in a `dev` build, instead of
getting a report after the program exits, run with `ASAN_OPTIONS=abort_on_error=1`.

Tests run through the presets get leak detection and the policy's list of
known OS false positives. To get the same when running a `dev` program
directly on macOS, set both:
`ASAN_OPTIONS=detect_leaks=1 LSAN_OPTIONS=suppressions=build/dev/cpp_policy_lsan.supp`.

## Self-test

```
cmake --workflow --preset check        # macOS / Linux
cmake --workflow --preset win-check    # Windows
```

The self-test builds known-good code with every check enabled, confirms each
sample in `tests/bad/` is rejected by the expected check, and runs the audit
against the fixtures in `tests/audit/`.
