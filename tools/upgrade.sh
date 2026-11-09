#!/bin/sh
# Upgrades a project to another cpp-policy release (POLICY.md 10). Run it from the project's
# root with the release tag:
#
#   sh <cpp-policy>/tools/upgrade.sh v0.7.0 [--no-gate]
#   sh <cpp-policy>/tools/upgrade.sh --library <name> v1.2.0 [--no-gate]
#
# The second form moves the pin of a library the project uses (cpp_policy_use_library,
# POLICY.md 11.7) to that release of the library: its commit, with the tag in a comment.
#
# <cpp-policy> can be any copy of cpp-policy, such as the one the build fetched
# (build/check/_deps/cpp_policy-src). The release itself is fetched from the project's
# GIT_REPOSITORY. The script changes only what a release defines, and checks every change:
#   - the GIT_TAG pin in CMakeLists.txt: the release's commit, with the tag in a comment;
#   - the pins of cpp-policy's CI gate in .github/workflows/, if there are any;
#   - the copies of .clang-tidy, .clang-format, CMakePresets.json, .claude/settings.json and
#     tools/hooks/;
#   - with a vcpkg.json, the copies of tools/vcpkg/;
#   - in AGENTS.md, everything above "## This project", which becomes the release's; what is
#     under that heading is the project's and is left alone;
#   - in CHANGELOG.md, the line "Policy: cpp-policy v<version>." (POLICY.md 11.5).
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
    echo "       sh upgrade.sh --library <name> <tag> [--no-gate]" >&2
    exit 2
}

# --library: move the pin of a library this project uses (POLICY.md 11.7), nothing else.
if [ "${1:-}" = --library ]; then
    [ $# -ge 3 ] && [ $# -le 4 ] || usage
    name=$2
    tag=$3
    gate=yes
    if [ $# -eq 4 ]; then
        [ "$4" = --no-gate ] || usage
        gate=no
    fi
    case $tag in
        v[0-9]*.[0-9]*.[0-9]*) ;;
        *) usage ;;
    esac
    [ -f CMakeLists.txt ] || fail "run it from the project's root (there is no CMakeLists.txt here)"
    [ -z "$(git status --porcelain)" ] || fail "the working folder has uncommitted changes; commit or stash them first"
    # The call, then the first GIT_REPOSITORY and GIT_TAG from it on.
    use_line=$(awk -v name="$name" '
        {
            line = $0
            if (sub(/^.*cpp_policy_use_library[ \t]*\([ \t]*/, "", line)) {
                split(line, words, /[ \t)]/)
                if (words[1] == name) { print NR; exit }
            }
        }' CMakeLists.txt)
    [ -n "$use_line" ] || fail "CMakeLists.txt has no cpp_policy_use_library($name ...)"
    repo_line=$(awk -v start="$use_line" 'NR >= start && /GIT_REPOSITORY/ { print NR; exit }' CMakeLists.txt)
    pin_line=$(awk -v start="$use_line" 'NR >= start && /GIT_TAG/ { print NR; exit }' CMakeLists.txt)
    [ -n "$repo_line" ] && [ -n "$pin_line" ] ||
        fail "cpp_policy_use_library($name ...) has no GIT_REPOSITORY and GIT_TAG"
    url=$(sed -n "${repo_line}s/.*GIT_REPOSITORY[[:space:]]*\([^[:space:])]*\).*/\1/p" CMakeLists.txt)
    sed -n "${pin_line}p" CMakeLists.txt | grep -q 'GIT_TAG[[:space:]]*[0-9a-f]\{40\}' ||
        fail "CMakeLists.txt line $pin_line must pin the library by commit (POLICY.md 11.7), not by tag"
    # A release is a tag; an annotated tag's commit is its "^{}" line.
    refs=$(git ls-remote "$url" "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null) ||
        fail "can't reach $url"
    commit=$(printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ { print $1; found = 1 } END { if (!found) exit 1 }') ||
        commit=$(printf '%s\n' "$refs" | awk 'NF { print $1; exit }')
    [ -n "$commit" ] || fail "$url has no release $tag"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    sed -e "${pin_line}s/[0-9a-f]\{40\}/$commit/" CMakeLists.txt >"$work/CMakeLists.txt"
    if sed -n "${pin_line}p" "$work/CMakeLists.txt" | grep -q '#[[:space:]]*v[0-9]'; then
        sed -e "${pin_line}s/#[[:space:]]*v[0-9][0-9.]*/# $tag/" "$work/CMakeLists.txt" >"$work/second"
    else
        sed -e "${pin_line}s/\$/ # $tag/" "$work/CMakeLists.txt" >"$work/second"
    fi
    # cat keeps the file's permissions.
    cat "$work/second" >CMakeLists.txt
    sed -n "${pin_line}p" CMakeLists.txt | grep -q "$commit.*# $tag" ||
        fail "the library's pin didn't change as expected (CMakeLists.txt line $pin_line)"
    echo "library $name: $tag is commit $commit."
    git --no-pager diff -- CMakeLists.txt
    echo "Read the library's CHANGELOG for $tag: a change that alters a result is said there first."
    echo "Its code counts in this project's size and memory budgets (POLICY.md 11.7, 13.5)."
    if [ "$gate" = yes ]; then
        sh tools/hooks/gate
    fi
    exit 0
fi

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

# 1. The GIT_TAG pin, and its "# <tag>" comment (added if missing).
rewrite CMakeLists.txt -e "${pin_line}s/[0-9a-f]\{40\}/$commit/"
if sed -n "${pin_line}p" CMakeLists.txt | grep -q '#[[:space:]]*v[0-9]'; then
    rewrite CMakeLists.txt -e "${pin_line}s/#[[:space:]]*v[0-9][0-9.]*/# $tag/"
else
    rewrite CMakeLists.txt -e "${pin_line}s/\$/ # $tag/"
fi
sed -n "${pin_line}p" CMakeLists.txt | grep -q "$commit.*# $tag" ||
    fail "the GIT_TAG pin didn't change as expected (CMakeLists.txt line $pin_line)"

# 2. The CI pins: every call to one of cpp-policy's workflows (gate.yml, benchmark.yml) moves
# to the same commit.
gate_ref='cpp-policy/\.github/workflows/[a-z_-]*\.ya*ml@'
ci_note=
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$workflow" ] || continue
    grep -q "$gate_ref" "$workflow" || continue
    # "|" as the delimiter: the pattern contains slashes.
    rewrite "$workflow" \
        -e "\\|$gate_ref|s|\\(\\.ya*ml@\\)[^[:space:]]*|\\1$commit|" \
        -e "\\|$gate_ref|s|#[[:space:]]*v[0-9][0-9.]*|# $tag|"
    if grep "$gate_ref" "$workflow" | grep -qv "@$commit"; then
        fail "$workflow still calls a cpp-policy workflow at another commit"
    fi
    # A tag push starts no run: a release is tagged on a commit whose run was green
    # (POLICY.md 8). A bare "push:" gets the branch filter; one with filters of its own is left
    # as it is, and said so.
    if grep -q '^  push:$' "$workflow"; then
        awk -v filter="    branches: ['**']" '
            pending && $0 !~ /^    / { print filter }
            { pending = 0; print }
            /^  push:$/ { pending = 1 }
            END { if (pending) print filter }' "$workflow" >"$work/rewrite"
        cat "$work/rewrite" >"$workflow"
    fi
    if grep -q '^  push:$' "$workflow" && ! grep -q "^    branches: \['\*\*'\]$" "$workflow"; then
        ci_note="$ci_note $workflow runs on push with filters of its own: check that a tag push starts no run (POLICY.md 8)."
    fi
done

# 3. The files projects copy unchanged. The hooks must stay executable. The agent settings are
# the template's, which the release keeps under template/.
mkdir -p .claude
for name in .clang-tidy .clang-format CMakePresets.json; do
    cp "$policy/$name" "$name"
done
cp "$policy/template/.claude/settings.json" .claude/settings.json
mkdir -p tools/hooks
for hook in "$policy"/tools/hooks/*; do
    cp "$hook" "tools/hooks/$(basename "$hook")"
    chmod 755 "tools/hooks/$(basename "$hook")"
done
for name in .clang-tidy .clang-format CMakePresets.json; do
    cmp -s "$policy/$name" "$name" || fail "$name doesn't match $tag's copy after copying"
done
cmp -s "$policy/template/.claude/settings.json" .claude/settings.json ||
    fail ".claude/settings.json doesn't match $tag's template/.claude/settings.json after copying"
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
fi

# 5. AGENTS.md: everything above "## This project" is the policy's, and becomes the release's;
# what is under that heading is the project's and is kept. A file without the heading gets the
# release's part, the heading, and then its whole old content under a comment, for the project
# to prune by hand once. A file with the heading twice is left alone, and said so.
agents_note=
template=$policy/template/AGENTS.md.in
heading='^## This project$'
if [ -f AGENTS.md ] && [ -f "$template" ] && [ "$(grep -c "$heading" "$template")" = 1 ]; then
    count=$(grep -c "$heading" AGENTS.md || true)
    if [ "$count" -le 1 ]; then
        awk -v heading="$heading" '{ print } $0 ~ heading { exit }' "$template" >"$work/AGENTS.md"
        if [ "$count" = 1 ]; then
            awk -v heading="$heading" 'found { print } $0 ~ heading { found = 1 }' AGENTS.md \
                >>"$work/AGENTS.md"
        else
            {
                echo
                echo "<!-- AGENTS.md as it was before cpp-policy $tag, which put the policy's part"
                echo "above. Keep what is this project's own, delete the rest, and remove this"
                echo "comment. -->"
                echo
                cat AGENTS.md
            } >>"$work/AGENTS.md"
            agents_note="AGENTS.md had no \"## This project\" heading: the release's part is now above it, and the old file below it, under a comment. Keep what is this project's own there and delete the rest, once."
        fi
        cat "$work/AGENTS.md" >AGENTS.md
    else
        agents_note="AGENTS.md has \"## This project\" more than once: left as it was. Compare it with the release's template/AGENTS.md.in by hand."
    fi
fi

# 6. The changelog's line that names the policy's release (POLICY.md 11.5).
policy_line='^Policy: cpp-policy v[0-9][0-9.]*\.$'
changelog_note="In CHANGELOG.md, update the line \"Policy: cpp-policy $tag.\" (POLICY.md 11.5)."
if [ -f CHANGELOG.md ] && [ "$(grep -c "$policy_line" CHANGELOG.md)" = 1 ]; then
    rewrite CHANGELOG.md -e "s/$policy_line/Policy: cpp-policy $tag./"
    changelog_note=
fi

# 7. What changed, and what the release asks of projects.
echo "cpp-policy $tag is commit $commit. Changed and new files:"
# status, not diff --stat: a file the release adds (a new hook) is untracked until committed.
git status --short
git --no-pager diff -- CMakeLists.txt .github AGENTS.md CHANGELOG.md
version=${tag#v}
echo
echo "--- CHANGELOG entry for $tag (read its 'Upgrading a project' steps) ---"
awk -v heading="## $version " 'index($0, heading) == 1 { show = 1; print; next }
    show && /^## / { exit }
    show { print }' "$policy/CHANGELOG.md"
echo "---"
echo "The .gitignore and .gitattributes lines the release requires are checked by the audit."
[ -z "$changelog_note" ] || echo "$changelog_note"
[ -z "$agents_note" ] || echo "$agents_note"
[ -z "$ci_note" ] || echo "${ci_note# }"

# 8. The local gate, through its launcher (POLICY.md 8), which picks the preset for this
# system.
if [ "$gate" = yes ]; then
    sh tools/hooks/gate
    echo "upgrade: done, and the gate passed. Review the diff, then commit it."
else
    echo "upgrade: done (gate not run). Review the diff, run the gate, then commit it."
fi
