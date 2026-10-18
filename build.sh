#!/usr/bin/env bash
# Пересобирает репо:
#   1) пакует папки из src/<id>/ в debs/*.deb
#   2) генерирует Packages, Packages.gz, Packages.bz2
#   3) генерирует depictions (html + sileo native json)
# Запускай после каждого изменения пакетов.
set -euo pipefail
cd "$(dirname "$0")"
URL=$(<.repo-url)
mkdir -p debs depictions/native

hash_of() { # algo file
  case "$1" in
    md5)    if command -v md5sum >/dev/null; then md5sum "$2" | cut -d' ' -f1; else openssl dgst -md5 -r "$2" | cut -d' ' -f1; fi ;;
    sha1)   if command -v sha1sum >/dev/null; then sha1sum "$2" | cut -d' ' -f1; else openssl dgst -sha1 -r "$2" | cut -d' ' -f1; fi ;;
    sha256) if command -v sha256sum >/dev/null; then sha256sum "$2" | cut -d' ' -f1; else openssl dgst -sha256 -r "$2" | cut -d' ' -f1; fi ;;
  esac
}
html_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
json_esc() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# ---- 1) pack src/* ----
for d in src/*/; do
  [ -f "${d}DEBIAN/control" ] || continue
  d=${d%/}
  id=$(grep -m1 '^Package:' "$d/DEBIAN/control" | cut -d' ' -f2- | tr -d '\r')
  ver=$(grep -m1 '^Version:' "$d/DEBIAN/control" | cut -d' ' -f2- | tr -d '\r')
  arch=$(grep -m1 '^Architecture:' "$d/DEBIAN/control" | cut -d' ' -f2- | tr -d '\r')
  out="debs/${id}_${ver}_${arch}.deb"
  find "$d" -name .DS_Store -delete 2>/dev/null || true
  chmod 755 "$d/DEBIAN" 2>/dev/null || true
  for s in preinst postinst prerm postrm; do [ -f "$d/DEBIAN/$s" ] && chmod 755 "$d/DEBIAN/$s"; done
  echo "[pack] $out"
  COPYFILE_DISABLE=1 dpkg-deb --root-owner-group -Zgzip -b "$d" "$out" >/dev/null 2>&1 \
    || COPYFILE_DISABLE=1 dpkg-deb -Zgzip -b "$d" "$out" >/dev/null
done

# ---- 2) Packages ----
: > Packages
shopt -s nullglob
count=0
for deb in debs/*.deb; do
  id=$(dpkg-deb -f "$deb" Package)
  name=$(dpkg-deb -f "$deb" Name 2>/dev/null || echo "$id")
  [ -z "$name" ] && name="$id"
  ver=$(dpkg-deb -f "$deb" Version)
  desc=$(dpkg-deb -f "$deb" Description 2>/dev/null | head -n1)
  author=$(dpkg-deb -f "$deb" Author 2>/dev/null || true)
  ctrl=$(dpkg-deb -f "$deb")

  {
    printf '%s\n' "$ctrl"
    printf '%s' "$ctrl" | grep -q '^Depiction:'       || echo "Depiction: $URL/depictions/$id.html"
    printf '%s' "$ctrl" | grep -q '^SileoDepiction:'  || echo "SileoDepiction: $URL/depictions/native/$id.json"
    echo "Filename: $deb"
    echo "Size: $(wc -c < "$deb" | tr -d ' ')"
    echo "MD5sum: $(hash_of md5 "$deb")"
    echo "SHA1: $(hash_of sha1 "$deb")"
    echo "SHA256: $(hash_of sha256 "$deb")"
    echo
  } >> Packages

  # ---- 3) depictions (не трогаем, если файл помечен как ручной) ----
  if [ ! -f "depictions/$id.html" ] || grep -q 'AUTO-GENERATED' "depictions/$id.html"; then
    cat > "depictions/$id.html" <<HTML
<!doctype html><!-- AUTO-GENERATED -->
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(printf '%s' "$name" | html_esc)</title>
<style>
body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:18px;background:#fff;color:#111}
h1{margin:0 0 4px;font-size:22px} .v{color:#888;font-size:14px;margin-bottom:14px}
p{line-height:1.45} .row{border-top:1px solid #eee;padding:10px 0;font-size:14px;display:flex;justify-content:space-between}
@media(prefers-color-scheme:dark){body{background:#000;color:#eee}.row{border-color:#222}}
</style></head><body>
<h1>$(printf '%s' "$name" | html_esc)</h1>
<div class="v">v$(printf '%s' "$ver" | html_esc)</div>
<p>$(printf '%s' "$desc" | html_esc)</p>
<div class="row"><span>Package</span><span>$(printf '%s' "$id" | html_esc)</span></div>
<div class="row"><span>Author</span><span>$(printf '%s' "${author:-unknown}" | html_esc)</span></div>
</body></html>
HTML
  fi

  if [ ! -f "depictions/native/$id.json" ] || grep -q '"_auto": true' "depictions/native/$id.json"; then
    cat > "depictions/native/$id.json" <<JSON
{
  "_auto": true,
  "minVersion": "0.1",
  "class": "DepictionTabView",
  "tintColor": "#8e8e8e",
  "tabs": [
    {
      "tabname": "Details",
      "class": "DepictionStackView",
      "views": [
        { "class": "DepictionHeaderView", "title": "$(printf '%s' "$name" | json_esc)" },
        { "class": "DepictionMarkdownView", "markdown": "$(printf '%s' "$desc" | json_esc)" },
        { "class": "DepictionSeparatorView" },
        { "class": "DepictionTableTextView", "title": "Version", "text": "$(printf '%s' "$ver" | json_esc)" },
        { "class": "DepictionTableTextView", "title": "Author", "text": "$(printf '%s' "${author:-unknown}" | json_esc)" }
      ]
    }
  ]
}
JSON
  fi

  echo "[ok]   $name $ver"
  count=$((count+1))
done

gzip  -9 -k -f Packages
bzip2 -9 -k -f Packages

echo
echo "Готово: $count пакет(ов). Теперь: git add -A && git commit -m update && git push"
