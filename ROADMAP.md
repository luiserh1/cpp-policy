# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects; no
version is in progress, so everything is under "Later".

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## Later

- [ ] **Moving the toolchain pins:** a protocol for moving `MSVC_TOOLSET`
      (and `LLVM_VERSION`) to newer versions from time to time. For
      example: when to move, trying the new version on cpp-policy's own
      CI and the server before a release, and the order of the messages to
      the server and project conversations. The owner wants to move to
      newer toolsets now and then (2026-09-30).

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).

### Last: how we test, measure and design

Deliberately left for after everything else (owner's decision). They are one
topic and will likely become new POLICY.md sections.

- [ ] **Testing section (#38):** test kinds with their own rules: unit (one
      module, no I/O, fast), integration (real sockets, files, threads;
      ephemeral ports; timeouts), regression (a label on a test added with a
      bug fix, written first), benchmark (see below). Suites as CTest labels,
      names `<kind>/<module>/<case>`, a fast `unit` test preset. Framework: a
      short spike porting one SimpleLocalServer test file to doctest and to
      gtest (the one the owner knows), run through our clang-tidy, before
      choosing (doctest favored: header-only, lightweight). The framework
      stays optional for small projects.
      The choice must keep the filtering the Carreritas runner had (by suite
      and name, list only, stop at first failure, quiet), which CTest mostly
      provides. Includes the working rule adopted during the walkthrough:
      fixes that change what passes or fails come with a test (#26).
- [ ] **Testing rules (#63):** framework-independent habits for POLICY.md:
      REQUIRE/ASSERT only for preconditions and CHECK/EXPECT for checks,
      comparisons that print both values, one behavior per test named after
      it, no shared state (shuffle), test through public interfaces, fakes
      over mocks, no sleeps, table-driven cases, no disabled tests without an
      open item. Motivating case: `sanitize(x).error()` in SimpleLocalServer's
      test_sanitize is undefined behavior if `sanitize` wrongly succeeds.
- [ ] **Budgets (#52):** binary size of the `release` build (per platform,
      fail on unexplained growth; bloaty to explain it) and memory under a
      stress test (peak memory stays flat as load grows). The `benchmark`
      label, run in CI. Baseline: SimpleLocalServer's release binary is
      840,096 bytes on macOS arm64 (1,734,016 before brotli was removed) and
      757,760 bytes on Windows x64 (clang-cl with Control Flow Guard,
      cpp-policy v0.4.0; 751,616 before CFG).
- [ ] **Performance (#13):** a POLICY.md section with the cost of each safety
      feature, defaults (contiguous containers, no needless copies), "measure
      first", and how to speed up a proven hot spot. Benchmarks: a library
      via vcpkg, a `bench` preset (Release, no sanitizers), results saved per
      version and compared on the same machine.
- [ ] **Design approach (#27):** data-oriented design first (plain data +
      free functions, contiguous containers, `enum class`/`std::variant` for
      closed sets); classes only to protect an invariant or own a resource;
      inheritance only for open runtime polymorphism; TDD where behavior is
      clear up front, not for every function. Parallel computation (parallel
      algorithms, pools) belongs here too, once libc++ provides them (W3 in
      POLICY.md 12).
