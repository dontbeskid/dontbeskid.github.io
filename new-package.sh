#!/usr/bin/env bash
# Создаёт заготовку пакета в src/<id>/
# Использование: ./new-package.sh com.you.tweak "Мой Твик" "Описание" [1.0] [iphoneos-arm64]
set -euo pipefail
cd "$(dirname "$0")"
ID="${1:-}"; NAME="${2:-}"; DESC="${3:-No description}"; VER="${4:-1.0}"; ARCH="${5:-iphoneos-arm64}"
if [ -z "$ID" ] || [ -z "$NAME" ]; then
  echo "Использование: $0 com.you.tweak \"Название\" \"Описание\" [версия] [архитектура]"
  exit 1
fi
D="src/$ID"
[ -e "$D" ] && { echo "[!] $D уже есть"; exit 1; }
mkdir -p "$D/DEBIAN"
if [ "$ARCH" = "iphoneos-arm64" ]; then
  mkdir -p "$D/var/jb/Library/MobileSubstrate/DynamicLibraries"
else
  mkdir -p "$D/Library/MobileSubstrate/DynamicLibraries"
fi
SECTION="Tweaks"
cat > "$D/DEBIAN/control" <<CTRL
Package: $ID
Name: $NAME
Version: $VER
Architecture: $ARCH
Description: $DESC
Maintainer: dontbeskid
Author: dontbeskid
Section: $SECTION
CTRL
echo "[ok] Создано $D"
echo "     Положи файлы твика внутрь $D (rootless -> $D/var/jb/...)"
echo "     Потом: ./build.sh"
