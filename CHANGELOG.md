# Changelog

Each entry says what changed and why. Projects read this before moving their
`GIT_TAG` to a new release. Versioning rules: POLICY.md section 10.

## Unreleased

Changes from the first full walkthrough of the repository (2026-09-25). Item
numbers refer to that review's issue list.

### Documentation

- The version now has a single source (the `project()` version) and a release
  procedure; POLICY.md explains what `0.x` versions mean. *Why:* the version
  was written in three places and two were stale (the README still said
  v0.1.0, `project()` said 0.1.0 after v0.1.1 was tagged). (#14)
- POLICY.md 2.1: the pointer-parameter row said "may be null *and* are
  required", which contradicts itself; it now says required arguments use
  references. *Why:* the rule could not be followed as written. (#3)
- POLICY.md 2.3 no longer recommends `std::start_lifetime_as`. *Why:* libc++
  23 does not provide it, so the recommendation could not compile. (#4)
- POLICY.md sections 5, 8 and 9 name the real tools: the `policy-audit` target
  and the `check` workflow instead of a `tools/` folder that never existed;
  the pre-commit hook is described as it is (audit and format check, no clang-
  tidy); the agent hook and CI are marked as planned. *Why:* the text still
  described the first draft, and agents follow it literally. (#7, #10)
- POLICY.md sections 6 and 9 drop `CLAUDE.md`. *Why:* Claude Code reads
  `AGENTS.md` directly since v2.1.277, and only when there is no `CLAUDE.md`,
  so the import file is no longer needed and a stray one would hide the
  instructions. (#17)
- POLICY.md section 6 no longer says projects may add checks locally; they may
  only tighten through the module's options. *Why:* there was no way to do it,
  since project configs must match the policy's and the build uses the
  policy's copies. May be revisited in a later version. (#8)

## 0.1.1

- `.clang-format` no longer re-wraps `NOLINT` comments. *Why:* a wrapped
  `NOLINTNEXTLINE` points at the wrong line (found in SimpleLocalServer).

## 0.1.0

- First release: policy document, CMake module, clang-tidy and clang-format
  configurations, suppression audit, presets and self-tests.
