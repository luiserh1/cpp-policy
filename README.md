# cpp-policy

Shared, versioned C++ policy: a restricted modern C++23 subset enforced by
Clang warnings, clang-tidy, a suppression audit and a format check.
The rules are in [POLICY.md](POLICY.md).

## Use in a project

```cmake
include(FetchContent)
FetchContent_Declare(cpp_policy
    GIT_REPOSITORY https://github.com/luiserh1/cpp-policy.git
    GIT_TAG        v0.1.0)
FetchContent_MakeAvailable(cpp_policy)

add_executable(app src/main.cpp)
cpp_policy_apply(app)       # every target you own
cpp_policy_add_checks()     # once: policy-audit, policy-format-check, policy-format-fix
```

Copy `.clang-tidy` and `.clang-format` into the project root unchanged (for
editors). The audit fails if they differ from this repository's copies.

## Options (set by presets)

| Option | Default | Meaning |
|---|---|---|
| `CPP_POLICY_SANITIZERS` | `OFF` | ASan + UBSan (ASan only on Windows) |
| `CPP_POLICY_CLANG_TIDY` | `OFF` | Run clang-tidy during the build |
| `CPP_POLICY_HARDENING` | `fast` | Standard library hardening: `none`, `fast`, `debug` |
| `CPP_POLICY_EXCEPTIONS` | `ON` | Exceptions and RTTI |
| `CPP_POLICY_CONFINED_DIRS` | `src/lowlevel` | Where suppressions are allowed |
| `CPP_POLICY_EXCLUDED_DIRS` | `build;out;.git;third_party;external;vcpkg_installed` | Skipped by audit/format |

## Requirements

LLVM Clang 23.x (`clang++`, or `clang-cl` on Windows) with clang-tidy and
clang-format next to it, CMake ≥ 3.29, Ninja. On macOS, Homebrew LLVM must be
first in `PATH` (Apple Clang is rejected).

## Self-test

```
cmake --workflow --preset check        # macOS / Linux
cmake --workflow --preset win-check    # Windows
```

The self-test builds known-good code with every check enabled, confirms each
sample in `tests/bad/` is rejected by the expected check, and runs the audit
against the fixtures in `tests/audit/`.
