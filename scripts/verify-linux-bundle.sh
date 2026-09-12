#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bin=dist/linux/libexec/opus
[[ -x "$bin" ]] || { echo "missing $bin" >&2; exit 1; }

export LD_LIBRARY_PATH="$PWD/dist/linux/lib/swift/linux:$PWD/dist/linux/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if ldd "$bin" | grep -F 'not found'; then
  echo 'Unresolved shared libraries in Linux bundle' >&2
  ldd "$bin"
  exit 1
fi

if [[ ! -e dist/linux/lib/swift/linux/libswiftObservation.so && ! -e dist/linux/lib/libswiftObservation.so ]]; then
  if ! ls dist/linux/lib/swift/linux/libswiftObservation.so* >/dev/null 2>&1 && ! ls dist/linux/lib/libswiftObservation.so* >/dev/null 2>&1; then
    echo 'libswiftObservation.so missing from bundle' >&2
    exit 1
  fi
fi

if ! ls dist/linux/lib/libgtk-4.so* >/dev/null 2>&1; then
  echo 'libgtk-4 missing from bundle' >&2
  exit 1
fi

if ! ls dist/linux/lib/libsqlite3.so* >/dev/null 2>&1; then
  echo 'libsqlite3 missing from bundle' >&2
  exit 1
fi

if [[ ! -f dist/linux/share/opus/opus.css ]]; then
  echo 'opus.css missing from bundle share/opus' >&2
  exit 1
fi

echo 'Linux bundle verification passed.'
