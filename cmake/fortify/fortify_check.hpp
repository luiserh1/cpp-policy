// Forced into every compile of a project's own targets outside Debug, where the policy
// defines _FORTIFY_SOURCE at 3 (POLICY.md 6, 7). The command line's definitions and
// undefinitions are all applied before a forced include, in whatever spelling they came (a
// flag variable, -Wp,, a response file), so this sees the level the build really has. It
// fails wherever fortify is off, so cpp-policy's own checks skip its folder.
#pragma once
#if !defined(_FORTIFY_SOURCE) || _FORTIFY_SOURCE < 3
#error "cpp-policy: _FORTIFY_SOURCE is not 3 here; an option turned it off (POLICY.md 6)"
#endif
