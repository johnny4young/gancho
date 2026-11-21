#!/usr/bin/env bash
# Stage the GitHub Pages site: the signed appcast plus a stub that forwards the
# old site root to gancho.app.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <appcast.xml> <output-dir>" >&2
  exit 2
fi
appcast="$1"
out="$2"

if [ ! -s "${appcast}" ] || ! grep -q '<enclosure ' "${appcast}"; then
  echo "error: ${appcast} is missing, empty, or has no release enclosure" >&2
  exit 1
fi

mkdir -p "${out}"
cp "${appcast}" "${out}/appcast.xml"
printf '%s\n' \
  '<!doctype html>' \
  '<meta charset="utf-8">' \
  '<title>Gancho</title>' \
  '<link rel="canonical" href="https://gancho.app/">' \
  '<meta name="robots" content="noindex">' \
  '<meta http-equiv="refresh" content="0; url=https://gancho.app/">' \
  '<script>location.replace("https://gancho.app/" + location.hash)</script>' \
  '<p>Gancho has moved to <a href="https://gancho.app/">gancho.app</a>.</p>' \
  > "${out}/index.html"
