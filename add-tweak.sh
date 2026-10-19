#!/usr/bin/env bash
# add-tweak.sh - добавить .deb в репо (с правкой названия, maintainer и иконки)
#
#   bash add-tweak.sh файл.deb [ещё.deb | ссылка] [опции]
#
# Опции:
#   --name "Visible Island"    поменять отображаемое название
#   --maintainer dontbeskid    поменять Maintainer
#   --icon картинка.jpeg       иконка (станет квадратом 180x180 в icons/<id>.png)
#   --own-depiction            убрать чужие Depiction/SileoDepiction (build.sh сделает свои)
#   --push                     после коммита сразу git push
set -euo pipefail

PUSH=0; NAME=""; MAINT=""; ICON=""; OWN=0; FILES=()
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

while [ $# -gt 0 ]; do
  case $1 in
    --push) PUSH=1 ;;
    --own-depiction) OWN=1 ;;
    --name)       NAME=${2:?нужно значение для --name}; shift ;;
    --maintainer) MAINT=${2:?нужно значение для --maintainer}; shift ;;
    --icon)       ICON=${2:?нужен файл для --icon}; [ -f "$ICON" ] || { echo "нет картинки: $ICON"; exit 1; }; ICON=$(abs "$ICON"); shift ;;
    http*)  f="$T/$(basename "${1%%\?*}")"; curl -fL -o "$f" "$1"; FILES+=("$f") ;;
    *)      [ -f "$1" ] || { echo "нет файла: $1"; exit 1; }; FILES+=("$(abs "$1")") ;;
  esac
  shift
done
[ ${#FILES[@]} -gt 0 ] || { sed -n '2,13p' "$0"; exit 1; }

cd "$(dirname "$(realpath "$0")")"
[ -f build.sh ] || { echo "нет build.sh. Верни: git checkout \$(git rev-list -n1 HEAD -- build.sh)^ -- build.sh"; exit 1; }
chmod +x ./*.sh 2>/dev/null || true
mkdir -p debs icons

# заменить поле control (или добавить, если его нет)
set_field() { # ключ значение файл
  if grep -q "^$1:" "$3"; then
    awk -v k="$1" -v v="$2" '$0 ~ "^" k ":" && !d {print k ": " v; d=1; next} {print}' "$3" > "$3.n" && mv "$3.n" "$3"
  else
    printf '%s: %s\n' "$1" "$2" >> "$3"
  fi
}

# картинка -> квадратный PNG 180x180
make_icon() { # вход выход
  if command -v magick >/dev/null; then magick "$1" -resize 180x180^ -gravity center -extent 180x180 "$2"
  elif command -v convert >/dev/null; then convert "$1" -resize 180x180^ -gravity center -extent 180x180 "$2"
  elif python3 -c "import PIL" 2>/dev/null; then
    python3 -c "from PIL import Image,ImageOps;ImageOps.fit(Image.open('$1').convert('RGBA'),(180,180),Image.LANCZOS).save('$2')"
  else echo "для иконки нужен imagemagick или python-pillow"; exit 1; fi
}

# перепаковать .deb с новыми полями
edit_deb() { # вход -> печатает путь к новому файлу
  local w="$T/w$RANDOM" out="$T/e_$RANDOM.deb" c id
  dpkg-deb -R "$1" "$w"
  c="$w/DEBIAN/control"; sed -i 's/\r$//' "$c"; sed -i -e '$a\' "$c"
  [ -n "$NAME" ]  && set_field Name "$NAME" "$c"
  [ -n "$MAINT" ] && set_field Maintainer "$MAINT" "$c"
  [ "$OWN" = 1 ]  && sed -i '/^Depiction:/d;/^SileoDepiction:/d' "$c"
  if [ -n "$ICON" ]; then
    [ -s .repo-url ] || { echo "нет файла .repo-url, не знаю URL для иконки" >&2; exit 1; }
    id=$(grep -m1 '^Package:' "$c" | cut -d' ' -f2- | tr -d ' ')
    make_icon "$ICON" "icons/$id.png"
    set_field Icon "$(cat .repo-url)/icons/$id.png" "$c"
  fi
  dpkg-deb --root-owner-group -Zgzip -b "$w" "$out" >/dev/null 2>&1 || dpkg-deb -Zgzip -b "$w" "$out" >/dev/null
  echo "$out"
}

N=0; LAST=""
for f in "${FILES[@]}"; do
  dpkg-deb -I "$f" >/dev/null 2>&1 || { echo "не .deb: $f"; continue; }
  if [ -n "$NAME$MAINT$ICON" ] || [ "$OWN" = 1 ]; then f=$(edit_deb "$f"); fi
  d="debs/$(dpkg-deb -f "$f" Package)_$(dpkg-deb -f "$f" Version)_$(dpkg-deb -f "$f" Architecture).deb"
  cp -f "$f" "$d"; echo "+ $d  [$(dpkg-deb -f "$f" Name 2>/dev/null)]"
  LAST=$(dpkg-deb -f "$f" Name 2>/dev/null || true); N=$((N+1))
done
[ "$N" -gt 0 ] || exit 1

bash ./build.sh

git add -A
git config user.email >/dev/null 2>&1 || { git config user.name "${USER:-user}"; git config user.email "${USER:-user}@users.noreply.github.com"; }
git commit -q -m "add ${LAST:-tweak}" || echo "нечего коммитить"
if [ "$PUSH" = 1 ]; then git push; else echo "теперь: git push"; fi
