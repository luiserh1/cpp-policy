# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects; no
version is in progress.

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## Later

### Libraries, after their first use

Releases A and B (0.30.0, 0.32.0) are out. Open:

- [ ] The token in a real CI run: Alfar's, once the owner has created it.
- [ ] What Alfar finds awkward in using ToneMatcher's library.
- [ ] A project that is only a library, and a library that uses a library:
      when a project needs one.

### From Alfar's report, not yet designed

- [ ] **Budgets and "ask the owner" in unattended runs:** a way for the
      owner to grant a standing rule (the size budget at a release commit),
      and a first CI run that has no number for a system yet.
- [ ] **A file the policy names for rules that could not be met,** listed by
      the audit.
- [ ] **Smaller:** the padding check's threshold; the message when a build
      runs without its preset; a shipped local-time function (W2); the
      hook's clang-tidy after a gate that passed on the same tree.
- [ ] **Alfar's gate time before and after 0.29.0,** asked of Alfar: the
      measurement that release was made on is of a generated project.

### Trials running

- **Instruction counts** (ToneMatcher, since 2026-10-08): whether a budget
  rule is worth writing, once the counts have been seen over real commits.

### Open, the owner's

- **MPL-2.0** (Eigen, Ceres): left open until a project needs it
  (2026-10-08).

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).
