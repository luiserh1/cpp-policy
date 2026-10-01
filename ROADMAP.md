# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects; no
version is in progress, so everything is under "Later".

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## Later

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).
