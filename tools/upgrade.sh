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
#   - the copies of .clang-tidy, .clang-format and tools/hooks/.
# It then shows the diff and the release's CHANGELOG entry and runs the gate. It commits
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

# The release, fetched into a temporary folder that is removed on exit.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone --quiet --depth 1 --branch "$tag" "$url" "$work/policy" 2>"$work/clone.log" ||
    fail "can't fetch $tag from $url: $(cat "$work/clone.log")"
commit=$(git -C "$work/policy" rev-parse HEAD)
policy="$work/policy"

# Rewrites a file through a temporary copy (sed -i differs between macOS and Linux); cat keeps
# the file's permissions.
rewrite() {
    file=$1
    shift
    sed "$@" "$file" >"$work/rewrite"
    cat "$work/rewrite" >"$file"
}

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
for name in .clang-tidy .clang-format; do
    cp "$policy/$name" "$name"
done
mkdir -p tools/hooks
for hook in "$policy"/tools/hooks/*; do
    cp "$hook" "tools/hooks/$(basename "$hook")"
    chmod 755 "tools/hooks/$(basename "$hook")"
done
for name in .clang-tidy .clang-format; do
    cmp -s "$policy/$name" "$name" || fail "$name doesn't match $tag's copy after copying"
done
for hook in "$policy"/tools/hooks/*; do
    name="tools/hooks/$(basename "$hook")"
    cmp -s "$hook" "$name" || fail "$name doesn't match $tag's copy after copying"
done

# 4. What changed, and what the release asks of projects.
echo "cpp-policy $tag is commit $commit. Changes:"
git --no-pager diff --stat
git --no-pager diff -- CMakeLists.txt .github
version=${tag#v}
echo
echo "--- CHANGELOG entry for $tag (read its 'Upgrading a project' steps) ---"
awk -v heading="## $version " 'index($0, heading) == 1 { show = 1; print; next }
    show && /^## / { exit }
    show { print }' "$policy/CHANGELOG.md"
echo "---"
echo "The .gitignore and .gitattributes lines the release requires are checked by the audit."

# 5. The gate, with the preset for this system (as the git hooks choose it).
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
