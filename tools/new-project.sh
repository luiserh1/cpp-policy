#!/bin/sh
# Creates a new project that follows cpp-policy, from the release this copy of cpp-policy is:
#
#   sh <cpp-policy>/tools/new-project.sh <folder> <Name>
#
# <cpp-policy> is a clone checked out at a release tag (git checkout v0.14.0). The project is
# pinned to that commit, in CMakeLists.txt and in its CI workflow, and gets that release's
# policy files, agent instructions and settings, and a small program that shows each layer,
# with its tests. It uses vcpkg, at least for doctest: vcpkg.json gets the baseline your
# VCPKG_ROOT is checked out at. (--vcpkg, needed before v0.19.0, is still accepted.) The
# folder becomes a git repository with the hooks enabled; nothing is committed.
set -eu

usage() {
    echo "usage: sh new-project.sh <folder> <Name>" >&2
    exit 2
}
[ $# -ge 2 ] && [ $# -le 3 ] || usage
[ $# -eq 2 ] || [ "$3" = --vcpkg ] || usage
dest=$1
name=$2
[ -n "${VCPKG_ROOT:-}" ] || {
    echo "new-project: set VCPKG_ROOT to your vcpkg folder (every project uses vcpkg)" >&2
    exit 1
}
baseline=$(git -C "$VCPKG_ROOT" rev-parse HEAD)

policy=$(cd "$(dirname "$0")/.." && pwd)
commit=$(git -C "$policy" rev-parse HEAD)
# Pin a release: an untagged commit may never be published.
tag=$(git -C "$policy" describe --tags --exact-match HEAD 2>/dev/null) || {
    echo "new-project: $policy is at $commit, which is no release tag;" >&2
    echo "  check out a release first (git -C $policy checkout v<version>)" >&2
    exit 1
}
if [ -n "$(git -C "$policy" status --porcelain)" ]; then
    echo "new-project: $policy has uncommitted changes; the project would pin other files" >&2
    exit 1
fi
repository=https://github.com/luiserh1/cpp-policy.git

mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
cmake "-DPOLICY_ROOT=$policy" "-DDEST=$dest" "-DNAME=$name" "-DCOMMIT=$commit" "-DTAG=$tag" \
    "-DREPOSITORY=$repository" "-DVCPKG_BASELINE=$baseline" -P "$policy/cmake/scripts/new_project.cmake"

git -C "$dest" init --quiet
git -C "$dest" config core.hooksPath tools/hooks
echo
echo "Next, in $dest:"
echo "  sh tools/hooks/gate                 (the gate: cmake --workflow --preset check)"
echo "  git add --all && git commit         (the hooks check the first commit too)"
echo "The size budget in CMakeLists.txt is the sample program's: the first real program is"
echo "larger, and its budget is yours to approve (POLICY.md 13.5)."
echo "Then describe the project in README.md and its first version in ROADMAP.md, and"
echo "publish it (a private repository needs a decision about macOS in CI:"
echo ".github/workflows/ci.yml says what)."
