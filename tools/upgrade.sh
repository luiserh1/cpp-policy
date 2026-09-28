#!/bin/sh
# Upgrades a project to another cpp-policy release (POLICY.md 10). Run it from the project's
# root with the release tag:
#
#   sh <cpp-policy>/tools/upgrade.sh v0.7.0 [--no-gate]
#
# <cpp-policy> can be any copy of cpp-policy, such as the one the build fetched
# (build/check/_deps/cpp_policy-src). The release itself is fetched from the project's
# GIT_REPOSITORY. The script changes only what a release defines, and checks every change:
#   - the GIT_TAG pin in CMakeLists.txt: the release's commit, with the tag in a comment;
#   - the pins of cpp-policy's CI gate in .github/workflows/, if there are any;
#   - the copies of .clang-tidy, .clang-format, CMakePresets.json and tools/hooks/;
#   - with a vcpkg.json, the copies of tools/vcpkg/, and the lines in CMakeLists.txt that load
#     vcpkg (the ones releases before v0.15.0 gave become an include of tools/vcpkg/setup.cmake).
# An older copy hands over to the release's own upgrade.sh, which knows what the release
# changed. It then shows the diff and the release's CHANGELOG entry and runs the gate. It commits
# nothing, and it refuses to start while the working folder has uncommitted changes, so the
# diff afterwards is exactly the upgrade.
set -eu

fail() {
    echo "upgrade: $*" >&2
    exit 1
}
usage() {
    echo "usage: sh upgrade.sh <tag, e.g. v0.7.0> [--no-gate]" >&2
    exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
tag=$1
gate=yes
if [ $# -eq 2 ]; then
    [ "$2" = --no-gate ] || usage
    gate=no
fi
case $tag in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) usage ;;
esac

[ -f CMakeLists.txt ] || fail "run it from the project's root (there is no CMakeLists.txt here)"
[ -z "$(git status --porcelain)" ] || fail "the working folder has uncommitted changes; commit or stash them first"

# The pin: the first GIT_TAG after the GIT_REPOSITORY that names cpp-policy.
repo_line=$(grep -n 'GIT_REPOSITORY.*cpp-policy' CMakeLists.txt | head -n 1 | cut -d: -f1)
[ -n "$repo_line" ] || fail "CMakeLists.txt has no GIT_REPOSITORY for cpp-policy"
url=$(sed -n "${repo_line}s/.*GIT_REPOSITORY[[:space:]]*\([^[:space:])]*\).*/\1/p" CMakeLists.txt)
pin_line=$(awk -v start="$repo_line" 'NR >= start && /GIT_TAG/ { print NR; exit }' CMakeLists.txt)
[ -n "$pin_line" ] || fail "CMakeLists.txt has no GIT_TAG after cpp-policy's GIT_REPOSITORY"
sed -n "${pin_line}p" CMakeLists.txt | grep -q 'GIT_TAG[[:space:]]*[0-9a-f]\{40\}' ||
    fail "CMakeLists.txt line $pin_line must pin cpp-policy by commit (POLICY.md 10), not by tag"

# The release, fetched into a temporary folder that is removed on exit. When an older
# upgrade.sh has handed over (below), the release is already fetched there.
if [ -n "${CPP_POLICY_UPGRADE_FETCHED:-}" ]; then
    work=$CPP_POLICY_UPGRADE_FETCHED
    trap 'rm -rf "$work"' EXIT
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    git clone --quiet --depth 1 --branch "$tag" "$url" "$work/policy" 2>"$work/clone.log" ||
        fail "can't fetch $tag from $url: $(cat "$work/clone.log")"
fi
commit=$(git -C "$work/policy" rev-parse HEAD)
policy="$work/policy"

# The release decides what an upgrade to it involves (a release can add policy files), so
# this copy hands over to the release's own upgrade.sh when that one differs.
if [ -z "${CPP_POLICY_UPGRADE_FETCHED:-}" ] && [ -f "$policy/tools/upgrade.sh" ] &&
    ! cmp -s "$policy/tools/upgrade.sh" "$0"; then
    echo "upgrade: handing over to $tag's own upgrade.sh"
    trap - EXIT
    CPP_POLICY_UPGRADE_FETCHED=$work exec sh "$policy/tools/upgrade.sh" "$@"
fi

# Rewrites a file through a temporary copy (sed -i differs between macOS and Linux); cat keeps
# the file's permissions.
rewrite() {
    file=$1
    shift
    sed "$@" "$file" >"$work/rewrite"
    cat "$work/rewrite" >"$file"
}

# vcpkg is loaded through the policy's tools/vcpkg/setup.cmake (POLICY.md 1.1). Projects from
# before v0.15.0 load it with these lines instead; they are replaced in step 4. Checked before
# anything changes, so a project that loads vcpkg some other way is left as it was.
vcpkg_include='include("${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake")'
cat >"$work/vcpkg-old" <<'EOF'
# vcpkg's toolchain is loaded here, before project(), so CMakePresets.json stays cpp-policy's
# unchanged copy. Without VCPKG_ROOT its path would be broken, and CMake's own error doesn't say
# why (cpp-policy POLICY.md 1.1).
if(NOT DEFINED ENV{VCPKG_ROOT})
    message(FATAL_ERROR "VCPKG_ROOT is not set: set it to the vcpkg directory (README: Building).")
endif()
set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE FILEPATH
    "vcpkg's toolchain (the presets are cpp-policy's unchanged copy)")
EOF
cat >"$work/vcpkg-new" <<'EOF'
# vcpkg is loaded before project(), where it installs the dependencies, through cpp-policy's
# files in tools/vcpkg/: they build the dependencies like the project (cpp-policy POLICY.md 1.1).
include("${CMAKE_CURRENT_SOURCE_DIR}/tools/vcpkg/setup.cmake")
EOF
# Writes CMakeLists.txt with the old lines replaced to $work/CMakeLists.txt, or fails unless
# they appear exactly once.
replace_vcpkg_lines() {
    awk 'FILENAME == ARGV[1] { old[++n] = $0; next }
         FILENAME == ARGV[2] { new[++m] = $0; next }
         { line[++count] = $0 }
         END {
             found = 0
             for (i = 1; i <= count - n + 1; i++) {
                 same = 1
                 for (j = 1; j <= n && same; j++) same = (line[i + j - 1] == old[j])
                 if (same) { found++; at = i }
             }
             if (found != 1) exit 1
             for (i = 1; i <= count; i++) {
                 if (i == at) { for (j = 1; j <= m; j++) print new[j]; i += n - 1; continue }
                 print line[i]
             }
         }' "$work/vcpkg-old" "$work/vcpkg-new" CMakeLists.txt >"$work/CMakeLists.txt"
}
vcpkg_lines=no
if [ -f vcpkg.json ] && ! grep -qF "$vcpkg_include" CMakeLists.txt; then
    replace_vcpkg_lines ||
        fail "CMakeLists.txt doesn't load vcpkg with the lines releases before v0.15.0 gave, so it
can't be changed automatically. Load vcpkg before project() with this line instead, then run
the upgrade again:
  $vcpkg_include"
    vcpkg_lines=yes
fi

# 1. The GIT_TAG pin, and its "# <tag>" comment (added if missing).
rewrite CMakeLists.txt -e "${pin_line}s/[0-9a-f]\{40\}/$commit/"
if sed -n "${pin_line}p" CMakeLists.txt | grep -q '#[[:space:]]*v[0-9]'; then
    rewrite CMakeLists.txt -e "${pin_line}s/#[[:space:]]*v[0-9][0-9.]*/# $tag/"
else
    rewrite CMakeLists.txt -e "${pin_line}s/\$/ # $tag/"
fi
sed -n "${pin_line}p" CMakeLists.txt | grep -q "$commit.*# $tag" ||
    fail "the GIT_TAG pin didn't change as expected (CMakeLists.txt line $pin_line)"

# 2. The CI gate pins: every call to cpp-policy's gate.yml moves to the same commit.
gate_ref='cpp-policy/\.github/workflows/gate\.ya*ml@'
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$workflow" ] || continue
    grep -q "$gate_ref" "$workflow" || continue
    # "|" as the delimiter: the pattern contains slashes.
    rewrite "$workflow" \
        -e "\\|$gate_ref|s|\\(gate\\.ya*ml@\\)[^[:space:]]*|\\1$commit|" \
        -e "\\|$gate_ref|s|#[[:space:]]*v[0-9][0-9.]*|# $tag|"
    if grep "$gate_ref" "$workflow" | grep -qv "@$commit"; then
        fail "$workflow still calls the gate at another commit"
    fi
done

# 3. The files projects copy unchanged. The hooks must stay executable.
for name in .clang-tidy .clang-format CMakePresets.json; do
    cp "$policy/$name" "$name"
done
mkdir -p tools/hooks
for hook in "$policy"/tools/hooks/*; do
    cp "$hook" "tools/hooks/$(basename "$hook")"
    chmod 755 "tools/hooks/$(basename "$hook")"
done
for name in .clang-tidy .clang-format CMakePresets.json; do
    cmp -s "$policy/$name" "$name" || fail "$name doesn't match $tag's copy after copying"
done
for hook in "$policy"/tools/hooks/*; do
    name="tools/hooks/$(basename "$hook")"
    cmp -s "$hook" "$name" || fail "$name doesn't match $tag's copy after copying"
done

# 4. A project with dependencies loads vcpkg through the release's tools/vcpkg/ (POLICY.md 1.1).
if [ -f vcpkg.json ]; then
    vcpkg_files="setup.cmake llvm.cmake triplets/cpp-policy-asan.cmake
        triplets/cpp-policy-tsan.cmake triplets/cpp-policy-nosan.cmake"
    mkdir -p tools/vcpkg/triplets
    for name in $vcpkg_files; do
        cp "$policy/tools/vcpkg/$name" "tools/vcpkg/$name"
        cmp -s "$policy/tools/vcpkg/$name" "tools/vcpkg/$name" ||
            fail "tools/vcpkg/$name doesn't match $tag's copy after copying"
    done
    if [ "$vcpkg_lines" = yes ]; then
        # Again, on the file as step 1 left it (the pin isn't in the replaced lines).
        replace_vcpkg_lines || fail "the lines that load vcpkg changed during the upgrade"
        cat "$work/CMakeLists.txt" >CMakeLists.txt
        grep -qF "$vcpkg_include" CMakeLists.txt ||
            fail "CMakeLists.txt doesn't include tools/vcpkg/setup.cmake after the change"
    fi
fi

# 5. What changed, and what the release asks of projects.
echo "cpp-policy $tag is commit $commit. Changed and new files:"
# status, not diff --stat: a file the release adds (a new hook) is untracked until committed.
git status --short
git --no-pager diff -- CMakeLists.txt .github
version=${tag#v}
echo
echo "--- CHANGELOG entry for $tag (read its 'Upgrading a project' steps) ---"
awk -v heading="## $version " 'index($0, heading) == 1 { show = 1; print; next }
    show && /^## / { exit }
    show { print }' "$policy/CHANGELOG.md"
echo "---"
echo "The .gitignore and .gitattributes lines the release requires are checked by the audit."

# 6. The gate, with the preset for this system (as the git hooks choose it).
if [ "$gate" = yes ]; then
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) preset=win-check ;;
        *) preset=check ;;
    esac
    cmake --workflow --preset "$preset"
    echo "upgrade: done, and the $preset gate passed. Review the diff, then commit it."
else
    echo "upgrade: done (gate not run). Review the diff, run the gate, then commit it."
fi
