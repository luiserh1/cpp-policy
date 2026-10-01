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

### Last: how we test, measure and design

Deliberately left for after everything else (owner's decision). They are one
topic and will likely become new POLICY.md sections.

- [ ] **Design approach (#27):** data-oriented design first (plain data +
      free functions, contiguous containers, `enum class`/`std::variant` for
      closed sets); classes only to protect an invariant or own a resource;
      inheritance only for open runtime polymorphism; TDD where behavior is
      clear up front, not for every function. Parallel computation (parallel
      algorithms, pools) belongs here too, once libc++ provides them (W3 in
      POLICY.md 12).
