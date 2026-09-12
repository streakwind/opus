#!/usr/bin/env bash
# Copy Swift + GTK + SQLite shared libraries and related resources into dist/linux.
set -euo pipefail
cd "$(dirname "$0")/.."
prefix="$PWD/dist/linux"
bin="$prefix/libexec/opus"
libdir="$prefix/lib"
swiftlib="$prefix/lib/swift/linux"
mkdir -p "$libdir" "$swiftlib" "$prefix/share/glib-2.0/schemas" "$prefix/lib/gdk-pixbuf-2.0/2.10.0/loaders"

is_system_skip() {
  case "$1" in
    linux-vdso.so*|ld-linux*.so*|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|libgcc_s.so*|libstdc++.so*) return 0 ;;
    *) return 1 ;;
  esac
}

copy_one() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  local base dest
  base=$(basename "$src")
  if [[ "$src" == */swift/linux/* ]]; then dest="$swiftlib/$base"; else dest="$libdir/$base"; fi
  if [[ -L "$src" ]]; then
    cp -a "$src" "$dest"
    local target
    target=$(readlink -f "$src")
    copy_one "$target"
  else
    cp -an "$src" "$dest" 2>/dev/null || cp -a "$src" "$dest"
  fi
}

queue=("$bin")
seen=()
while ((${#queue[@]})); do
  current="${queue[0]}"; queue=("${queue[@]:1}")
  [[ " ${seen[*]} " == *" $current "* ]] && continue
  seen+=("$current")
  while IFS= read -r line; do
    path=$(sed -n 's/.*=> \(.*\) (0x.*/\1/p' <<<"$line")
    [[ -z "$path" || "$path" == not\ found ]] && continue
    is_system_skip "$(basename "$path")" && continue
    copy_one "$path"
    queue+=("$path")
  done < <(ldd "$current" 2>/dev/null || true)
done

# GTK schemas and pixbuf loaders for a relocatable runtime.
if [[ -d /usr/share/glib-2.0/schemas ]]; then
  cp -a /usr/share/glib-2.0/schemas/*.xml "$prefix/share/glib-2.0/schemas/" 2>/dev/null || true
  if command -v glib-compile-schemas >/dev/null; then
    glib-compile-schemas "$prefix/share/glib-2.0/schemas"
  fi
fi
loader_dir=$(pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0 2>/dev/null || true)
if [[ -n "$loader_dir" && -d "$loader_dir" ]]; then
  mkdir -p "$prefix/lib/gdk-pixbuf-2.0/2.10.0/loaders"
  cp -a "$loader_dir"/*.so "$prefix/lib/gdk-pixbuf-2.0/2.10.0/loaders/" 2>/dev/null || true
  if command -v gdk-pixbuf-query-loaders >/dev/null; then
    (cd "$prefix" && GDK_PIXBUF_MODULEDIR="$PWD/lib/gdk-pixbuf-2.0/2.10.0/loaders" \
      gdk-pixbuf-query-loaders > lib/gdk-pixbuf-2.0/2.10.0/loaders.cache)
    # Rewrite absolute module paths to relocatable $prefix-relative ones later via launcher env.
    sed -i "s|$PWD/lib|@PREFIX@/lib|g" "$prefix/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" || true
  fi
fi

# Ensure Observation is present (canary for Swift runtime).
if [[ ! -e "$swiftlib/libswiftObservation.so" && ! -e "$libdir/libswiftObservation.so" ]]; then
  toolchain=$(dirname "$(dirname "$(readlink -f "$(command -v swift)")")")
  find "$toolchain" /usr/lib/swift -name 'libswiftObservation.so*' 2>/dev/null | while read -r so; do
    copy_one "$so"
  done
fi

printf 'Bundled runtime libraries into %s\n' "$prefix/lib"
