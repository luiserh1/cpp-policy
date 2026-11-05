# Roadmap

Open work on cpp-policy itself: what comes next, and why. What's done is in
`CHANGELOG.md`, with the reasons; items are removed from here in the commit
that resolves them. The layout is the one POLICY.md 11.5 gives projects.

## Next release (in progress): one release, then the policy is frozen

The owner's plan (2026-11-05): one more release takes in the whole queue;
then the policy is frozen until every project has upgraded, top-down
(libraries, then programs). Its notes must work from v0.38.0
(ToneMatcher, SimpleLocalServer and GalleryOrganizer are on it;
cli-cpparser on v0.39.0; Alfar on v0.40.0). Decided with the owner on
2026-11-05, from Alfar's reports of 10-24 and 11-04 and the experiments
report of 10-26:

- [ ] 4. A stage's branch is pushed, and its CI is green, before it joins
      `main` (POLICY.md 8, `AGENTS.md`). Alfar's 190 commits were gated on
      macOS only, and `main` held a red release for 22 hours.
- [ ] 2. POLICY.md 13.4: a scratch folder's lock records its process and is
      free once that process is gone. ToneMatcher fixes
      `lib/tonematcher/testing/scratch_folder.hpp` after the release (the
      retry after a timeout always failed on the killed run's lock).
- [ ] 3. The tidy cache (`cmake/scripts/tidy_cache.cmake`; prototype on the
      local branch `tidy-cache`): both holes closed (program identity:
      done in the prototype; path placeholders and the header filter),
      Linux and Windows (clang-cl has no `-M`), self-tests, quiet timings.
- [ ] 5. `gate.yml` input `timeout_minutes`, default 45; README: a runner
      that shares a machine with local work needs more.
- [ ] 6. `readability-qualified-auto` `AllowedTypes` for `std::array`'s
      iterators, if it works; else a line in 2.10. A line in 2.10 on
      `bugprone-optional-value-conversion` (libstdc++ only). No libstdc++
      pass on the Mac.
- [ ] 7. pre-commit audits and formats the staged version of staged files
      only; long checks print the number of files first and findings as
      they come; 13.5 and `AGENTS.md` say how to try a memory test in the
      release build.
- [ ] 8. The gate's audit and format check skip files git doesn't track,
      unless a target compiles them.
- [ ] 9. The release workflow runs test cases in a random order, the seed
      printed at configure and in failures, reproducible by configuring
      with it. **Can make existing code fail.**
- [ ] 10. 13.5: a memory budget per unit of input (S, then 5S; growth at
      most 4S × the budget), no default, the owner approves each.
- [ ] 11. `cpp_policy_tool(<target> "<reason>")`: a development program,
      built and checked, no size budget, reason printed at configure.
- [ ] 12. Linking a library or framework is a dependency (ask the owner);
      link options are flags (never). POLICY.md 6, `AGENTS.md`.
- [ ] 13. POLICY.md 11.7: the real path of `upgrade.sh --library`.
- [ ] 14. POLICY.md 8: the gate's lock is machine-wide by design;
      `CPP_POLICY_GATE_LOCK`; CI jobs don't take it.
- [ ] 15. Section 15: what something is comes from measurement or data,
      not names; machine-dependent figures shown to users are measured or
      not shown; one way per problem; a fix for the data at hand says so.
- [ ] 16. 11.5: no code for old formats until someone outside the project
      depends on the format.
- [ ] 17. 11.4: accuracy covers every document and user-visible text, with
      a search for the old wording; changelog entries name the options
      rejected; a glossary optional; few, short current-state documents;
      where a reason goes (code or commit message).
- [ ] 18. Real data by hand, never in the gate; generated data at real
      size. Declined: no test twice on one machine (CI's clean checkout
      stays).
- [ ] 19 to 21. A section "Working for the owner" in `AGENTS.md`, inside
      the part `upgrade.sh` replaces: the project's rules over an agent's
      habits; done only after checking; build, don't operate; decisions to
      the changelog and a "Now" section in `ROADMAP.md`; nothing waits on a
      prompt; delegated work in its own copy, a commit per step, stop at
      what the brief doesn't cover, a test changed only when wrong, the
      report's contents; one writer per set of files; experiments with
      limits; a build under the owner's test is frozen; nothing joins
      `main` without the owner's word. 13.4: tests show nothing on screen.
- [ ] POLICY.md 7: the retry's "Why" corrected (the window hang was
      Alfar's second `glfwInit`, fixed in its 0.8.0).
- [ ] After the night's timings: B (test jobs from the cores), C (tsan on
      the Mac only for Mac-only tests; leaning no), D (the Mac's release
      job only when releasing; recommended no).

Until 2026-09-28 these lived in SimpleLocalServer's `PENDING.md`, the
project that piloted the policy. Numbers like #38 refer to the issues found
in the walkthroughs of that time.

## Later

### Libraries, after their first use

Releases A and B (0.30.0, 0.32.0) are out. Open:

- [x] The token in a real CI run: Alfar's Linux and Windows jobs fetched
      ToneMatcher's library with it (2026-10-12).
- [x] `cpp_policy_parallel_tests()` in real projects (0.33.0): ToneMatcher
      41 s to 14 s; Alfar 756 s to 217 s, no program `ALONE`.
- [ ] Alfar on Windows and Linux: it has its remote and CI since
      2026-10-12, and both systems are being made green (its own code's
      findings; a full list is promised). libjpeg-turbo and parallel tests
      are proven on macOS only until then.
- [ ] A project that is only a library, and a library that uses a library:
      when a project needs one. cli-cpparser (v0.1.0, public) is a library
      with a small example program in `src/`, and nothing in 11.7 got in
      its way.
- [x] A project that offers a library and uses another: ToneMatcher v0.6.0
      uses cli-cpparser, at the first configure and green on three systems;
      the library was on a newer cpp-policy than its user, as the floor
      allows. Its program got smaller (macOS 15,024 bytes, Linux 8,120).
- [x] Two libraries in one project: Alfar, with ToneMatcher's and
      cli-cpparser (2026-10-13). Still untried: `upgrade.sh --library` with
      two libraries present, and two libraries that share a vcpkg package.

### From Alfar's report, not yet designed

- [ ] **Budgets and "ask the owner" in unattended runs:** a way for the
      owner to grant a standing rule (the size budget at a release commit).
      (A first CI run with no number for a system: done in 0.34.0.)
- [ ] **A file the policy names for rules that could not be met,** listed by
      the audit.
- [ ] **Smaller:** the padding check's threshold; the message when a build
      runs without its preset; a shipped local-time function (W2); the
      hook's clang-tidy after a gate that passed on the same tree.
- [ ] **From its report of 2026-10-10:** a build after a `CMakeLists.txt`
      changes runs clang-tidy on the whole tree again (13 to 30 minutes);
      the size budget is tested only in the release workflow, and on macOS
      moves 16 KiB at a time; `tidy-files` says "OK (0 files)" for a path
      that doesn't exist; its trial of one full gate per stage, with the
      hook and the touched modules' tests between commits.

- [ ] **From its report of 2026-10-13:** `tidy-files` took over ten
      minutes for one widely included header (`src/app/record.hpp`): not
      understood, its output is asked for. The commit hook rebuilding for
      10 to 25 minutes before a commit of a document is understood: the
      hook builds the audit through CMake, a stale build folder configures
      again, and vcpkg rebuilds the dependencies when the compiler was
      updated (seen in SimpleLocalServer, two seconds there). Open:
      whether the hook should configure at all for a commit with no code.
- [ ] **Asked and not given (2026-10-13):** a way for a project to choose
      which test programs the tsan workflow runs. Measured after the
      upgrade: Alfar's Mac job is 23 minutes with a whole first build, its
      tests 982 s; the gate by hand 20.5 minutes. To look at again if the
      owner finds that too long for the end of a stage.
- [ ] **A false positive on Windows, not reproduced here:**
      `clang-analyzer-cplusplus.NewDeleteLeaks` ("field '_Rep'") on a
      `std::make_shared` among an aggregate's designated initializers, with
      MSVC's library, reported at the function's closing brace. Giving
      that member in a statement of its own ends it; the same shape two
      functions below was never reported. No small file shows it yet, and
      one is not asked of Alfar: it would cost CI runs there. If a second
      project meets it, try one in this repository's own Windows job.

### Trials running

- **Instruction counts** (ToneMatcher, since 2026-10-08): whether a budget
  rule is worth writing, once the counts have been seen over real commits.
  - Seen so far: the same code repeats to about 3,000 instructions in
    billions; a rewrite of the PNG row filters showed as -43% on one
    benchmark; untouched benchmarks moved by 3, 413 and 788 instructions
    when a function they call gained an argument.
  - So a budget needs a small tolerance, not zero; and a count says nothing
    of the output, which a benchmark could check with a checksum in the
    same run.

### Open, the owner's

- **MPL-2.0** (Eigen, Ceres): left open until a project needs it
  (2026-10-08).
- **An owner's exception for one named package's license,** with a reason
  printed at every configure (asked by Alfar, 2026-10-11): when a license
  comes up that the owner would accept for one project but not for all.

- **Rules for optimization levels** (raised 2026-10-12, to deliberate).
  Today the presets decide and no section says why as a whole: `-O0` in
  `dev` and `debug`, `-O1` in `check`, `unit` and `tsan`, CMake's Release
  default (`-O3`) in `release`. Nothing is said on `-O2` against `-O3`,
  link-time optimization, per-target levels, or flags for the machine's
  processor.
- **A shared library of small helpers** (raised 2026-10-12, to deliberate):
  reading a whole file, canonical paths and the like, so that each project
  stops meeting the same differences between systems in CI, as Alfar did
  on Windows and Linux. Agreed so far (2026-10-12): small modules each
  named after what it does (`files`, `paths`, `text`), never `utils`, as
  11.2 asks; some modules of ToneMatcher's library (the number reader, the
  scratch folder for tests, the process launcher) may move to it; a finding
  about how to call the standard library becomes a line in 2.10, not a
  wrapper; no sorting helpers without a clear reason. Needed first: Alfar's
  full list of findings once its three systems are green, and "a library
  that uses a library" (11.7, not supported yet), because ToneMatcher's
  library would then use this one.

### Waiting

- [ ] **Modules experiment:** once CMake makes `import std` stable, convert
      one module of a project (e.g. SimpleLocalServer's `message/sanitize`)
      and check that clang-tidy and the gate still pass (POLICY.md 2.4 says
      why modules aren't used yet; W1 in POLICY.md 12).
