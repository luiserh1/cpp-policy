# cpp-policy

Shared, versioned C++ policy: a restricted modern C++23 subset enforced by
Clang warnings, clang-tidy, a suppression audit and a format check.
The rules are in [POLICY.md](POLICY.md).

## Starting a new project

From a clone of cpp-policy checked out at the release you want:

```
git -C cpp-policy checkout v0.33.0
sh cpp-policy/tools/new-project.sh ~/code/MyTool MyTool            # VCPKG_ROOT must be set
cd ~/code/MyTool && sh tools/hooks/gate
git add --all && git commit
```

The project is pinned to that release, in `CMakeLists.txt` and its CI
workflow, and has the release's policy files, `AGENTS.md`, agent settings and
git hooks (enabled), with a small program that shows the layers: `main.cpp`,
an `app` module returning `std::expected`, a confined `lowlevel` module, and
their doctest tests (POLICY.md 13). `ROADMAP.md` and `CHANGELOG.md` are ready for its first version
(POLICY.md 11.5). It passes the gate as generated; replace the program with your own. The
steps below say what each part is, for adding the policy to an existing
project by hand.

*Why a generator and not a GitHub template repository:* a template repository
is a second copy of the policy files and pins, and it would have to be
upgraded after every cpp-policy release, or new projects would start behind.
The generator lives in cpp-policy and produces each project from the release
it is run from, so there is nothing to keep in sync. The self-test generates
a project and runs its gate on every push (`tests/new_project`), so a release
can't ship a template that fails its own policy.

## Use in a project

```cmake
include(FetchContent)
FetchContent_Declare(cpp_policy
    GIT_REPOSITORY https://github.com/luiserh1/cpp-policy.git
    GIT_TAG        <commit>)   # v0.33.0, the latest release; see CHANGELOG.md
FetchContent_MakeAvailable(cpp_policy)

add_library(app_core STATIC src/model/board.cpp)
target_include_directories(app_core PUBLIC src)
cpp_policy_apply(app_core)  # every target you own (configuration fails otherwise)
add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE app_core)
cpp_policy_apply(app)

cpp_policy_size_budget(app MACOS 109568 LINUX 93184 WINDOWS 285696)  # stripped bytes (POLICY.md 13.5)

enable_testing()            # doctest programs; each test case becomes a CTest test (POLICY.md 13)
cpp_policy_add_tests(unit model SOURCES tests/test_board.cpp LIBRARIES app_core)

cpp_policy_layers(          # the modules under src/, from the lowest layer up (POLICY.md 11.1)
    LAYER lowlevel
    LAYER model
    LAYER ui)
cpp_policy_confine_includes(nlohmann/ TO model)   # a dependency stays in its module (POLICY.md 11.6)
# Another policy project's library, fetched at a release and built here (POLICY.md 11.7):
# cpp_policy_use_library(shapes GIT_REPOSITORY <url> GIT_TAG <commit>)   # v1.2.0
cpp_policy_add_checks()     # once: policy-audit, policy-format-check, policy-format-fix
```

Tests use doctest, from vcpkg: add it to `vcpkg.json` (POLICY.md 1.1).
`cmake --workflow --preset unit` (`win-unit` on Windows) builds without
clang-tidy, at `-O1`, and runs only the unit tests, for a quick check while
working. Speed benchmarks use nanobench: add it to `vcpkg.json` and
`cpp_policy_add_tests(benchmark …)` links it (POLICY.md 14.2).

Pin the commit a release tag points to, with the tag in a comment, rather
than the tag itself: a tag can be moved to other code later, a commit can't,
and this repository's CMake code runs on every machine that configures the
project (POLICY.md 10). The commit is the line ending in `^{}`:

```
git ls-remote https://github.com/luiserh1/cpp-policy 'refs/tags/v0.33.0*'
```

Don't add `GIT_SHALLOW`: it only works with branch and tag names.

### Upgrading

From the project's root, with a clean working folder:

```
sh build/check/_deps/cpp_policy-src/tools/upgrade.sh v0.33.0
```

Any copy of this repository's `tools/upgrade.sh` works (from v0.10.1 on): it
fetches the release from the project's `GIT_REPOSITORY` and hands over to the
release's own `upgrade.sh`, which knows what that release changed. It moves the `GIT_TAG` pin and the
CI gate pins to the release's commit (with the tag in the comment), copies
`.clang-tidy`, `.clang-format`, `CMakePresets.json`, `tools/hooks/` and, in a
project with a `vcpkg.json`, `tools/vcpkg/`, checks every change, shows
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
the gate and CI run. The audit fails if the presets differ from this
repository's.

A project that uses vcpkg copies `tools/vcpkg/` unchanged and loads it in its
`CMakeLists.txt`, before `project()`:

```cmake
include("${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake")
```

It makes vcpkg build the dependencies with the same LLVM, sanitizer and
hardening as the project, instead of with the system's compiler
(POLICY.md 1.1). The audit fails if the copies differ from this repository's.

Start the project's `.gitignore` and `.gitattributes` from this repository's
copies. Projects may add lines, but the audit fails if any of these are
missing (POLICY.md 6.1).

Copy `tools/hooks/` unchanged as well, and enable the hooks once per clone:

```
git config core.hooksPath tools/hooks
```

`pre-commit` runs the suppression audit, the format check and clang-tidy on the
staged C++ files; `commit-msg` checks
the message (Conventional Commits with a body that says why, POLICY.md 8.2);
`pre-push` runs the full gate and refuses to start while there are
uncommitted changes, so it tests exactly what is pushed. The audit fails if the hooks differ from these,
and configuration warns while a clone hasn't enabled them.

`tools/hooks/tidy-files` isn't a git hook but a command: `sh
tools/hooks/tidy-files <file>...` runs clang-tidy on just those files, a few
seconds each. Agents and people run it after editing C++ files (say so in
`AGENTS.md`); `pre-commit` runs it on the staged ones.

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
    uses: luiserh1/cpp-policy/.github/workflows/gate.yml@<commit> # v0.33.0
    with:
      systems: '["linux", "windows", "macos"]'
      vcpkg: true          # if the project has a vcpkg.json
```

The audit fails if the two pins differ, so CI always runs the policy the
build uses. Move both in the same commit when upgrading.

`systems` picks the systems. GitHub's runners are free for public
repositories; private ones spend the account's Actions minutes, and a macOS
minute costs about ten Linux ones (Windows about two).

**A library in a private repository** (POLICY.md 11.7). The gate can't fetch
it without a token. The owner does this once, in the browser:

1. On GitHub, *Settings > Developer settings > Fine-grained tokens*: a token
   for the library's repository only, with "Contents: Read-only".
2. In the repository of the project that **uses** the library,
   *Settings > Secrets and variables > Actions*: a secret named
   `LIBRARY_TOKEN` with that token.
3. In that project's CI workflow, under each call to cpp-policy:

   ```yaml
       secrets:
         library_token: ${{ secrets.LIBRARY_TOKEN }}
   ```

The gate gives the token to git for the job only, as a header sent to the
libraries' addresses and to no other; nothing is written to the runner. A
fine-grained token expires: the job then fails to fetch, and the fix is a
new token in the same secret.

A newer push makes an older run of the same branch obsolete, and the gate
cancels it: on a branch the older run is stopped; on the default branch the
run in progress finishes and only runs still waiting behind it are dropped.
A tag's run is never cancelled. Projects need nothing in their own workflow
for this.

### Your own machine as a runner

`self_hosted: '["macos"]'` runs the macOS jobs on your own Mac instead
(`"linux"` and `"windows"` work the same way). Its minutes are free. While
the machine is off or asleep, its jobs wait; GitHub fails a job that waits
more than 24 hours (re-run it from the Actions page). The gate installs and
resets nothing there: it uses the machine's LLVM 23, CMake and Ninja, and
keeps a vcpkg copy of its own in the runner's folder.

Only for private repositories that only you push to: in a public one, a
pull request from anyone could run code on your machine. (Public ones get
GitHub's runners free anyway.)

Setting up a Mac, once per repository (a personal account's runner serves
one repository):

1. On GitHub: the repository, Settings, Actions, Runners, **New self-hosted
   runner**, macOS, ARM64. It shows the commands to download the runner and
   configure it with a one-time token.
2. Run them in a folder of its own, such as
   `~/actions-runners/<repository>`, from a terminal where `clang++ --version`
   shows LLVM 23 and `cmake` and `ninja` work: the runner keeps that
   terminal's `PATH`. Accept the default name and labels.
3. Instead of `./run.sh`, install it as a background service that starts at
   login: `./svc.sh install` and `./svc.sh start`.

The repository's Settings, Actions, Runners then shows it as Idle. To remove
it: `./svc.sh uninstall`, then `./config.sh remove` with the token GitHub shows.

## Options (set by presets)

| Option | Default | Meaning |
|---|---|---|
| `CPP_POLICY_SANITIZERS` | `OFF` | ASan + UBSan (ASan only on Windows) |
| `CPP_POLICY_THREAD_SANITIZER` | `OFF` | ThreadSanitizer (not with the option above; not on Windows) |
| `CPP_POLICY_CLANG_TIDY` | `OFF` | Run clang-tidy during the build |
| `CPP_POLICY_HARDENING` | `fast` | Standard library hardening: `fast` or `debug` |
| `CPP_POLICY_EXCEPTIONS` | `ON` | Exceptions and RTTI |
| `CPP_POLICY_CONFINED_DIRS` | `src/lowlevel` | Where suppressions are allowed |
| `CPP_POLICY_EXCLUDED_DIRS` | `build;out;.git;third_party;external;vcpkg_installed` | Skipped by audit/format |

## Requirements

- LLVM **23.x**: `clang++` (macOS/Linux) or `clang-cl` (Windows), with
  `clang-tidy`, `clang-format`, `llvm-strip` and `llvm-size` from the same
  installation (the last two check size budgets, POLICY.md 13.5)
- CMake ≥ 3.29
- Ninja

## Setup per platform

The presets look for LLVM in the standard install locations first, so on most
machines no configuration is needed:

| Platform | Install | Location searched by the presets |
|---|---|---|
| macOS (Apple Silicon) | `brew install llvm ninja`, or `llvm@23` once Homebrew's `llvm` is a newer major | `/opt/homebrew/opt/llvm@23/bin`, then `/opt/homebrew/opt/llvm/bin` |
| macOS (Intel) | `brew install llvm ninja`, or `llvm@23` as above | `/usr/local/opt/llvm@23/bin`, then `/usr/local/opt/llvm/bin` |
| Debian / Ubuntu | [apt.llvm.org](https://apt.llvm.org) packages for LLVM 23 (`clang-23`, `clang-tidy-23`, `clang-format-23`, `libclang-rt-23-dev` and `llvm-23`), plus `ninja-build` | `/usr/lib/llvm-23/bin` |
| Other Linux (e.g. Arch, CachyOS) | The official LLVM 23 release tarball (`LLVM-23.x.y-Linux-X64.tar.xz` from GitHub; check its SHA-256), extracted with `--strip-components=1` into `/usr/lib/llvm-23`, plus Ninja | `/usr/lib/llvm-23/bin` |
| Windows | Official LLVM installer (default path), Ninja, and Visual Studio 2022 17.14 (MSVC 14.44) or later, or its Build Tools, with the "C++ AddressSanitizer" component (for the Windows SDK, the runtime and `stl_asan.lib`) | `C:\Program Files\LLVM\bin` |

Things to know:

- **macOS:** Xcode puts Apple Clang in `/usr/bin`, and Homebrew does not put
  its LLVM ahead of it. That's why the presets search the Homebrew location
  explicitly. Apple Clang is always rejected: it has its own version numbering
  and ships without clang-tidy.
- **macOS:** Homebrew's `llvm` moves to each new LLVM major within days of
  its release, before the policy does (POLICY.md 10.1). The configure check
  then reports the wrong major: `brew install llvm@23` fixes it, and the
  presets find it first.
- **Linux:** distributions often ship an older LLVM, or install it only under
  versioned names (`clang++-23`). The unversioned binaries in
  `/usr/lib/llvm-23/bin` are what the presets use.
- **Windows:** the LLVM that comes with Visual Studio may be older than 23.
  Use the official installer.
- **Windows, self-hosted CI runners:** exactly the Microsoft toolset the gate
  pins (`MSVC_TOOLSET` in `gate.yml`, POLICY.md 1), and no other.
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
against the fixtures in `tests/audit/`. With `VCPKG_ROOT` set (always in CI),
it also builds dependencies with the policy's triplets and a project from the
template, doctest tests included.
