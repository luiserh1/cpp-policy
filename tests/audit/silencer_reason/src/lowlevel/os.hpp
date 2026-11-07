#pragma once
// Confined: OS interop.
#pragma clang system_header // the system API below warns, and is not ours
[[clang::no_sanitize("address")]] void touch(char* page); // reads a guard page on purpose
