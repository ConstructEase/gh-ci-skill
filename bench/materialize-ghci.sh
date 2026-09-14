#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: materialize-ghci.sh SOURCE_REPO PAYLOAD_ROOT VERSION" >&2
  exit 2
fi

source_repo="$1"
payload_root="$2"
version="$3"
case "$version" in
  1.2.3) commit=3be16034aacffaefa462a61d269d8224b9a158a4 ;;
  1.2.4) commit=d70569a2fdb5662a359e1200d91a1f28514d4a30 ;;
  1.3.0) commit=cf2528060c34c16c838e247780f748fe5ab13dc3 ;;
  1.3.2) commit=9594571c ;;
  *) echo "materialize-ghci: version must be 1.2.3, 1.2.4, or 1.3.0" >&2; exit 2 ;;
esac

tag="v$version"
object_repo="$source_repo"
object_ref="$commit"
if [ "$(git -C "$source_repo" rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)" = "$commit" ]; then
  object_ref="refs/tags/$tag"
elif ! git -C "$source_repo" cat-file -e "$commit^{commit}" 2>/dev/null; then
  cache="$payload_root/git-cache"
  if [ ! -d "$cache/.git" ]; then
    mkdir -p "$cache"
    git -C "$cache" init -q
  fi
  origin_url="$(git -C "$source_repo" remote get-url origin 2>/dev/null || true)"
  [ -n "$origin_url" ] || { echo "materialize-ghci: source repository has no origin" >&2; exit 1; }
  if git -C "$cache" remote get-url origin >/dev/null 2>&1; then
    git -C "$cache" remote set-url origin "$origin_url"
  else
    git -C "$cache" remote add origin "$origin_url"
  fi
  if git -C "$cache" fetch -q --depth=1 origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null \
      && [ "$(git -C "$cache" rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)" = "$commit" ]; then
    object_ref="refs/tags/$tag"
  elif ! git -C "$cache" fetch -q --depth=1 origin "$commit"; then
    echo "materialize-ghci: cannot fetch pinned gh-ci $version commit $commit" >&2
    exit 1
  fi
  object_repo="$cache"
fi

git -C "$object_repo" cat-file -e "$object_ref^{commit}" 2>/dev/null || {
  echo "materialize-ghci: pinned gh-ci $version commit is unavailable" >&2
  exit 1
}

payload="$payload_root/$version/gh-ci"
mkdir -p "$payload/resources"
skill_tmp="$(mktemp "$payload/SKILL.md.XXXXXX")"
ci_tmp="$(mktemp "$payload/resources/ci.sh.XXXXXX")"
trap 'rm -f "$skill_tmp" "$ci_tmp"' EXIT
git -C "$object_repo" show "$object_ref:gh-ci/SKILL.md" > "$skill_tmp"
git -C "$object_repo" show "$object_ref:gh-ci/resources/ci.sh" > "$ci_tmp"
[ "$(head -n 1 "$skill_tmp")" = "---" ] || {
  echo "materialize-ghci: gh-ci/SKILL.md lacks frontmatter" >&2
  exit 1
}
case "$(head -n 1 "$ci_tmp")" in
  '#!/bin/bash'|'#!/usr/bin/env bash') ;;
  *) echo "materialize-ghci: gh-ci/resources/ci.sh lacks a Bash shebang" >&2; exit 1 ;;
esac
chmod +x "$ci_tmp"
mv "$skill_tmp" "$payload/SKILL.md"
mv "$ci_tmp" "$payload/resources/ci.sh"
trap - EXIT
