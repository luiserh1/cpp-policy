# cpp-policy

Shared, versioned C++ policy: a restricted modern C++23 subset enforced by
Clang warnings, clang-tidy, a suppression audit and a format check.
The rules are in [POLICY.md](POLICY.md).

## Use in a project

```cmake
include(FetchContent)
FetchContent_Declare(cpp_policy
    GIT_REPOSITORY https://github.com/luiserh1/cpp-policy.git
    GIT_TAG        <commit>)   # v0.3.0, the latest release; see CHANGELOG.md
FetchContent_MakeAvailable(cpp_policy)

add_executable(app src/main.cpp)
cpp_policy_apply(app)       # every target you own (configuration fails otherwise)
cpp_policy_add_checks()     # once: policy-audit, policy-format-check, policy-format-fix
```

Pin the commit a release tag points to, with the tag in a comment, rather
than the tag itself: a tag can be moved to other code later, a commit can't,
and this repository's CMake code runs on every machine that configures the
project (POLICY.md 10). The commit is the line ending in `^{}`:

```
git ls-remote https://github.com/luiserh1/cpp-policy 'refs/tags/v0.3.0*'
```

Don't add `GIT_SHALLOW`: it only works with branch and tag names.

Copy `.clang-tidy` and `.clang-format` into the project root unchanged. The
copies are for editors: clangd and IDEs look for these files next to the
sources, so they show the same warnings and formatting while you type. The
build never reads them; it always uses this repository's copies. The audit
fails if the copies differ, so the editor and the build can't disagree.

Start the project's `.gitignore` and `.gitattributes` from this repository's
copies. Projects may add lines, but the audit fails if any of these are
missing (POLICY.md 6.1).

Copy `tools/hooks/` unchanged as well, and enable the hooks once per clone:

```
git config core.hooksPath tools/hooks
```

`pre-commit` runs the suppression audit and format check; `pre-push` runs the
full gate and refuses to start while there are uncommitted changes, so it
tests exactly what is pushed. The audit fails if the hooks differ from these,
and configuration warns while a clone hasn't enabled them.

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
| Windows | Official LLVM installer (default path), Ninja, and Visual Studio or Build Tools (for the Windows SDK and runtime) | `C:\Program Files\LLVM\bin` |

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

To stop in the debugger at a sanitizer error in a `dev` build, instead of
getting a report after the program exits, run with `ASAN_OPTIONS=abort_on_error=1`.

## Self-test

```
cmake --workflow --preset check        # macOS / Linux
cmake --workflow --preset win-check    # Windows
```

The self-test builds known-good code with every check enabled, confirms each
sample in `tests/bad/` is rejected by the expected check, and runs the audit
against the fixtures in `tests/audit/`.
