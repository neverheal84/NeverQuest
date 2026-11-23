#!/usr/bin/env bash
# Builds NeverQuest-<version>.zip from this folder.
#
# Every build that leaves here gets its own version number. This refuses to build a version
# that has been built before, so a changed addon can never go out under an old number:
#   tools/package.sh --bump    raise the last number (1.21.1 -> 1.21.2) in both TOCs, then build
#   tools/package.sh           build the version the TOCs already carry, if it is new
# The test suite runs on the packaged copy before the zip is kept.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${OUT_DIR:-$here/..}"
harness="${HARNESS:-$here/../test/harness.lua}"
lua="${LUA:-/tmp/luabuild/lua51/lua51}"
cd "$here"

version() { sed -n 's/^## Version: *\([0-9.]*\).*/\1/p' NeverQuest.toc | head -1; }

if [ "${1:-}" = "--bump" ]; then
	old="$(version)"
	new="$(echo "$old" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')"
	sed -i "s/^## Version: *$old/## Version: $new/" NeverQuest.toc NeverQuest_Camelot.toc
	echo "version $old -> $new"
fi

v="$(version)"
camelot="$(sed -n 's/^## Version: *\([0-9.]*\).*/\1/p' NeverQuest_Camelot.toc | head -1)"
[ "$v" = "$camelot" ] || { echo "the two TOCs disagree: $v and $camelot" >&2; exit 1; }
zip="$out/NeverQuest-$v.zip"
[ ! -e "$zip" ] || { echo "NeverQuest-$v.zip was built before. Run with --bump for a new number." >&2; exit 1; }
grep -q "\"$v\"" Help.lua || { echo "/nq news has no entry for $v (Help.lua)" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -r "$here" "$stage/NeverQuest"
rm -rf "$stage/NeverQuest/tools"
(cd "$stage" && zip -qr "$stage/NeverQuest.zip" NeverQuest)
mkdir "$stage/check" && (cd "$stage/check" && unzip -q "$stage/NeverQuest.zip")
result="$(cd "$(dirname "$harness")" && "$lua" "$(basename "$harness")" "$stage/check/NeverQuest/" | tail -1)"
[ "$result" = "ALL CHECKS PASSED" ] || { echo "tests failed on the packaged copy: $result" >&2; exit 1; }
mv "$stage/NeverQuest.zip" "$zip"
echo "built $zip"
