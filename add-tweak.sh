#!/usr/bin/env bash
# ============================================================
#  add-deb-tweak.sh - добавить готовый .deb в твой Sileo-репо
#
#  Положи этот файл в корень репо (рядом с build.sh) и запускай:
#
#    ./add-deb-tweak.sh файл.deb
#    ./add-deb-tweak.sh a.deb b.deb c.deb
#    ./add-deb-tweak.sh https://example.com/tweak.deb
#    ./add-deb-tweak.sh файл.deb --push     (сразу git push, без вопросов)
#    ./add-deb-tweak.sh файл.deb --no-push  (не пушить и не спрашивать)
#
#  Что делает:
#    1) проверяет, что это настоящий .deb
#    2) копирует в debs/ с правильным именем
#    3) запускает ./build.sh (Packages, Packages.gz/.bz2, depictions)
#    4) git add + commit (+ push)
# ============================================================
set -euo pipefail

command -v dpkg-deb >/dev/null || { echo "[!] Нужен dpkg-deb: sudo pacman -S dpkg"; exit 1; }

# ---------- args (пути делаем абсолютными ДО cd) ----------
FILES=()
PUSH=ask
TMPDIR_DL=""
cleanup() { if [ -n "$TMPDIR_DL" ]; then rm -rf "$TMPDIR_DL"; fi; }
trap cleanup EXIT

for a in "$@"; do
  case "$a" in
    --push)    PUSH=yes ;;
    --no-push) PUSH=no ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    http://*|https://*)
      command -v curl >/dev/null || { echo "[!] Для ссылок нужен curl"; exit 1; }
      [ -z "$TMPDIR_DL" ] && TMPDIR_DL=$(mktemp -d)
      out="$TMPDIR_DL/$(basename "${a%%\?*}")"
      echo "[dl]  $a"
      curl -fL --progress-bar -o "$out" "$a"
      FILES+=("$out") ;;
    *)
      [ -f "$a" ] || { echo "[!] Нет файла: $a"; exit 1; }
      FILES+=("$(cd "$(dirname "$a")" && pwd)/$(basename "$a")") ;;
  esac
done

[ ${#FILES[@]} -eq 0 ] && { sed -n '2,19p' "$0"; exit 1; }

cd "$(dirname "$0")"
[ -x ./build.sh ] || { echo "[!] build.sh не найден. Запусти скрипт из корня репо."; exit 1; }
mkdir -p debs

# ---------- add ----------
ADDED=()
for f in "${FILES[@]}"; do
  if ! dpkg-deb -I "$f" >/dev/null 2>&1; then
    echo "[!] Не похоже на .deb, пропускаю: $f"
    continue
  fi
  id=$(dpkg-deb -f "$f" Package)
  ver=$(dpkg-deb -f "$f" Version)
  arch=$(dpkg-deb -f "$f" Architecture)
  name=$(dpkg-deb -f "$f" Name 2>/dev/null || true); [ -z "$name" ] && name="$id"

  case "$arch" in
    iphoneos-arm|iphoneos-arm64|all) ;;
    *) echo "[?]   $id: архитектура '$arch' необычная для iOS" ;;
  esac

  dest="debs/${id}_${ver}_${arch}.deb"
  if [ -e "$dest" ]; then
    echo "[~]   $dest уже есть, заменяю"
  fi
  cp -f "$f" "$dest"
  echo "[+]   $name $ver ($arch)"
  ADDED+=("$name $ver")
done

[ ${#ADDED[@]} -eq 0 ] && { echo "[!] Ничего не добавлено."; exit 1; }

# ---------- rebuild ----------
echo
./build.sh

# ---------- git ----------
if [ -d .git ]; then
  git add -A
  if git diff --cached --quiet; then
    echo "[i] Изменений для коммита нет."
  else
    msg="Add ${ADDED[0]}"
    [ ${#ADDED[@]} -gt 1 ] && msg="Add ${#ADDED[@]} packages (${ADDED[*]})"
    GITID=()
    git config user.email >/dev/null 2>&1 || GITID=(-c user.name="${USER:-user}" -c user.email="${USER:-user}@users.noreply.github.com")
    git ${GITID[@]+"${GITID[@]}"} commit -q -m "$msg"
    echo "[git] commit: $msg"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    if [ "$PUSH" = ask ]; then
      if [ -t 0 ]; then
        read -r -p "Запушить на GitHub? [Y/n] " ans
        case "${ans:-Y}" in [nN]*) PUSH=no ;; *) PUSH=yes ;; esac
      else
        PUSH=no
      fi
    fi
    if [ "$PUSH" = yes ]; then
      git push && echo "[git] запушено. Pages обновится через 1-2 минуты."
    else
      echo "[i] Не забудь: git push"
    fi
  else
    echo "[i] remote 'origin' не настроен. Добавь:"
    echo "    git remote add origin https://github.com/ТВОЙ_НИК/ТВОЙ_НИК.github.io.git"
    echo "    git push -u origin main"
  fi
else
  echo "[i] Это не git-репо. Залей файлы на GitHub вручную."
fi