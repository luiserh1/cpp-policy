# Maintaining cpp-policy

Procedures for cpp-policy's maintainer. The rules projects follow are in
`POLICY.md`; this file holds the steps only cpp-policy itself takes.

## A toolchain window

When and why the pins move, and what a project does meanwhile, is in
`POLICY.md` 10.1. cpp-policy's own steps:

1. **Open.** Choose the target versions from their release notes: new
   clang-tidy checks, standard library changes, removed options. Write the
   release's section in `ROADMAP.md`. Tell the administrators of the
   self-hosted runners and the projects that the window is open, with the
   targets.
2. **Trial the policy.** On a branch with the new pins:
   - cpp-policy's own CI and a local gate;
   - a decision on each new clang-tidy check (enabled unless it only
     produces noise);
   - the items of POLICY.md 12 reviewed.

   Nothing is released yet.
3. **Trial the projects, before anything moves.** Each project is built
   with the candidate toolchain against the policy branch, on every system
   (`-DFETCHCONTENT_SOURCE_DIR_CPP_POLICY=<branch checkout>`).
   - On a Windows runner machine: snapshot it, pause its runners (jobs
     wait in the queue), install the candidate, run the builds, and restore
     the snapshot.
   - On Linux, the new LLVM installs next to the old one.
   - Each project fixes its findings before the switch, in code that passes
     with both toolchains. When no such code exists, the fix goes into the
     upgrade commit instead.
4. **Release** the new pins as a minor release (POLICY.md 10), and tag it.
   Tell the runner administrators the exact versions and checksums first.
5. **Switch, on one agreed day.** The runner machines change first:
   snapshot, install, and a trial build of cpp-policy at the new tag. Then
   every project that uses them upgrades right away (`tools/upgrade.sh`).
   - Until a project upgrades, its self-hosted Windows jobs stop at the
     toolset check, so this gap should be as short as possible.
   - A Windows runner machine holds one toolset at a time, so all projects
     switch together. Keeping old and new side by side would take runner
     labels per toolset and a second machine: the way out if too many
     projects share the runners to switch in one day.
6. **Roll back** if a project can't pass on the same day: the runner
   machines restore their snapshot, and the projects that upgraded revert
   their upgrade commit. The release stays; it is adopted in a later attempt.
7. **Close.** Each project's first run prints the new versions ("Show the
   toolchain"). The release commit already removed the window's section
   from `ROADMAP.md` (POLICY.md 11.5). An old LLVM major is uninstalled once
   no project uses it.
