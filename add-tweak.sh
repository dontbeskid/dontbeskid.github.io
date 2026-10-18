#!/usr/bin/env bash
# add-tweak.sh - добавить .deb в репо
#   bash add-tweak.sh файл.deb [ещё.deb | ссылка] [--push]
set -euo pipefail

PUSH=0; FILES=(); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for a in "$@"; do
  case $a in
    --push) PUSH=1 ;;
    http*)  f="$T/$(basename "${a%%\?*}")"; curl -fL -o "$f" "$a"; FILES+=("$f") ;;
    *)      [ -f "$a" ] || { echo "нет файла: $a"; exit 1; }; FILES+=("$(realpath "$a")") ;;
  esac
done
[ ${#FILES[@]} -gt 0 ] || { echo "использование: bash add-tweak.sh файл.deb [--push]"; exit 1; }

cd "$(dirname "$(realpath "$0")")"
[ -f build.sh ] || { echo "нет build.sh. Верни: git checkout \$(git rev-list -n1 HEAD -- build.sh)^ -- build.sh"; exit 1; }
chmod +x ./*.sh 2>/dev/null || true
mkdir -p debs

N=0
for f in "${FILES[@]}"; do
  dpkg-deb -I "$f" >/dev/null 2>&1 || { echo "не .deb: $f"; continue; }
  d="debs/$(dpkg-deb -f "$f" Package)_$(dpkg-deb -f "$f" Version)_$(dpkg-deb -f "$f" Architecture).deb"
  cp -f "$f" "$d"; echo "+ $d"; N=$((N+1))
done
[ "$N" -gt 0 ] || exit 1

bash ./build.sh

git add -A
git config user.email >/dev/null 2>&1 || { git config user.name "${USER:-user}"; git config user.email "${USER:-user}@users.noreply.github.com"; }
git commit -q -m "add tweak" || echo "нечего коммитить"
if [ "$PUSH" = 1 ]; then git push; else echo "теперь: git push"; fi