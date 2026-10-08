#!/usr/bin/env bash
# Download and install the pinned toolchain into tools/ (and Godot addons into
# game/addons/). Idempotent: each component writes a .version stamp and is
# skipped when the stamp already matches tools/versions.env.
#
# Usage: tools/setup/fetch_tools.sh [godot] [jdk] [ghidra] [blastem] [addons] [templates] [audio] [zig]
#        (no arguments = everything but the export templates, 1.3 GB download,
#        and the audio extension's build dependencies, which tools/bin/build-audio
#        fetches on first use: audio = godot-cpp + ymfm sources, zig = the
#        Windows cross-compiler)
#
# Everything lands inside the repository, so every machine that shares the
# folder (a desktop and a VM, say) uses the same toolchain.
set -euo pipefail
command -v unzip >/dev/null || { echo "fetch_tools: please install 'unzip'" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$ROOT/tools"
# Archives are cached outside the repo (large and reproducible).
DL="${MW_DOWNLOAD_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mightyweenie/downloads}"
# shellcheck source=../versions.env
source "$TOOLS/versions.env"
mkdir -p "$DL"

log() { printf '[fetch] %s\n' "$*"; }

# fetch URL DEST [ALGO HASH]  - download (resumable) and verify a checksum.
fetch() {
  local url="$1" dest="$2" algo="${3:-}" want="${4:-}"
  if [[ ! -s "$dest" ]]; then
    log "downloading $(basename "$dest")"
    curl -fL --retry 5 --retry-delay 3 -C - -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  if [[ -n "$algo" && -n "$want" ]]; then
    local got
    got="$("${algo}sum" "$dest" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
      log "CHECKSUM MISMATCH for $dest"; log " want $want"; log " got  $got"
      rm -f "$dest"; exit 1
    fi
    log "checksum ok: $(basename "$dest")"
  else
    log "no pinned checksum for $(basename "$dest"): $(sha256sum "$dest" | cut -d' ' -f1)"
  fi
}

# stamped NAME DIR VERSION - true when DIR/.version already equals VERSION
stamped() { [[ -f "$2/.version" && "$(cat "$2/.version")" == "$3" ]]; }

# unpack ARCHIVE DIR - extract, stripping the single top-level directory
unpack() {
  local archive="$1" dir="$2" tmp
  tmp="$(mktemp -d "$DL/x.XXXX")"
  case "$archive" in
    # unzip keeps the executable bits (Ghidra's launchers and native decompiler
    # need them); Python's zipfile does not.
    *.zip) unzip -q "$archive" -d "$tmp" ;;
    *) tar -xf "$archive" -C "$tmp" ;;
  esac
  rm -rf "$dir"; mkdir -p "$(dirname "$dir")"
  local entries=("$tmp"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then mv "${entries[0]}" "$dir"; else mv "$tmp" "$dir"; fi
  rm -rf "$tmp"
}

do_godot() {
  local dir="$TOOLS/godot"
  stamped godot "$dir" "$GODOT_VERSION" && { log "godot $GODOT_VERSION already installed"; return; }
  fetch "$GODOT_URL" "$DL/$(basename "$GODOT_URL")" sha512 "$GODOT_SHA512"
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -q "$DL/$(basename "$GODOT_URL")" -d "$dir"
  mv "$dir"/Godot_v*_linux.x86_64 "$dir/godot"
  chmod +x "$dir/godot"
  # Self-contained mode: editor settings/cache live in tools/godot/editor_data
  # instead of the shared ~/.config/godot, so this editor never touches the
  # settings of other Godot editors running on the machine.
  touch "$dir/._sc_"
  echo "$GODOT_VERSION" > "$dir/.version"
  log "godot $GODOT_VERSION -> tools/godot (self-contained)"
}

# Windows x86_64 export templates for tools/godot (and, through a link made by
# tools/bin/export-windows, the headless copy). The .tpz holds every platform's
# templates; only the Windows x86_64 ones (and their console wrappers) and version.txt
# are extracted.
do_templates() {
  local dir="$TOOLS/godot/editor_data/export_templates/$GODOT_VERSION.stable"
  stamped templates "$dir" "$GODOT_VERSION+windows+linux" && { log "export templates $GODOT_VERSION already installed"; return; }
  fetch "$GODOT_TEMPLATES_URL" "$DL/$(basename "$GODOT_TEMPLATES_URL")" sha512 "$GODOT_TEMPLATES_SHA512"
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -q -j "$DL/$(basename "$GODOT_TEMPLATES_URL")" \
    templates/version.txt "templates/windows_*_x86_64*.exe" "templates/linux_*.x86_64" -d "$dir"
  echo "$GODOT_VERSION+windows+linux" > "$dir/.version"
  log "export templates $GODOT_VERSION (windows and linux x86_64) -> $dir"
}

do_jdk() {
  local dir="$TOOLS/jdk"
  stamped jdk "$dir" "$JDK_VERSION" && { log "jdk $JDK_VERSION already installed"; return; }
  fetch "$JDK_URL" "$DL/jdk.tar.gz" sha256 "$JDK_SHA256"
  unpack "$DL/jdk.tar.gz" "$dir"
  echo "$JDK_VERSION" > "$dir/.version"
  log "jdk $JDK_VERSION -> tools/jdk"
}

do_ghidra() {
  local dir="$TOOLS/ghidra"
  stamped ghidra "$dir" "$GHIDRA_VERSION" && { log "ghidra $GHIDRA_VERSION already installed"; return; }
  fetch "$GHIDRA_URL" "$DL/$(basename "$GHIDRA_URL")" sha256 "$GHIDRA_SHA256"
  unpack "$DL/$(basename "$GHIDRA_URL")" "$dir"
  echo "$GHIDRA_VERSION" > "$dir/.version"
  log "ghidra $GHIDRA_VERSION -> tools/ghidra"
}

do_blastem() {
  local dir="$TOOLS/blastem"
  stamped blastem "$dir" "$BLASTEM_VERSION" && { log "blastem $BLASTEM_VERSION already installed"; return; }
  fetch "$BLASTEM_URL" "$DL/$(basename "$BLASTEM_URL")" sha256 "${BLASTEM_SHA256:-}"
  unpack "$DL/$(basename "$BLASTEM_URL")" "$dir"
  echo "$BLASTEM_VERSION" > "$dir/.version"
  log "blastem $BLASTEM_VERSION -> tools/blastem"
}

do_addons() {
  local addons="$ROOT/game/addons"
  mkdir -p "$addons"
  if ! stamped gut "$addons/gut" "$GUT_VERSION"; then
    fetch "$GUT_URL" "$DL/gut-$GUT_VERSION.tar.gz" sha256 "$GUT_SHA256"
    unpack "$DL/gut-$GUT_VERSION.tar.gz" "$DL/gut-src"
    rm -rf "$addons/gut"; cp -r "$DL/gut-src/addons/gut" "$addons/gut"
    cp "$DL/gut-src/LICENSE.md" "$addons/gut/LICENSE.md" 2>/dev/null || true
    rm -rf "$DL/gut-src"
    echo "$GUT_VERSION" > "$addons/gut/.version"
    log "GUT $GUT_VERSION -> game/addons/gut"
  else log "GUT $GUT_VERSION already installed"; fi
}

# Sources the audio GDExtension is built from (tools/bin/build-audio; never
# committed): godot-cpp -> tools/godot-cpp, ymfm -> tools/ymfm.
do_audio() {
  local dir="$TOOLS/godot-cpp"
  if ! stamped godot-cpp "$dir" "$GODOT_CPP_VERSION"; then
    fetch "$GODOT_CPP_URL" "$DL/godot-cpp-$GODOT_CPP_VERSION.tar.gz" sha256 "$GODOT_CPP_SHA256"
    unpack "$DL/godot-cpp-$GODOT_CPP_VERSION.tar.gz" "$dir"
    echo "$GODOT_CPP_VERSION" > "$dir/.version"
    log "godot-cpp $GODOT_CPP_VERSION -> tools/godot-cpp"
  else log "godot-cpp $GODOT_CPP_VERSION already installed"; fi
  dir="$TOOLS/ymfm"
  if ! stamped ymfm "$dir" "$YMFM_VERSION"; then
    fetch "$YMFM_URL" "$DL/ymfm-$YMFM_VERSION.tar.gz" sha256 "$YMFM_SHA256"
    unpack "$DL/ymfm-$YMFM_VERSION.tar.gz" "$dir"
    echo "$YMFM_VERSION" > "$dir/.version"
    log "ymfm $YMFM_VERSION -> tools/ymfm"
  else log "ymfm $YMFM_VERSION already installed"; fi
}

# Zig toolchain (zig c++ -target x86_64-windows-gnu) -> tools/zig
do_zig() {
  local dir="$TOOLS/zig"
  stamped zig "$dir" "$ZIG_VERSION" && { log "zig $ZIG_VERSION already installed"; return; }
  fetch "$ZIG_URL" "$DL/$(basename "$ZIG_URL")" sha256 "$ZIG_SHA256"
  unpack "$DL/$(basename "$ZIG_URL")" "$dir"
  echo "$ZIG_VERSION" > "$dir/.version"
  log "zig $ZIG_VERSION -> tools/zig"
}

targets=("$@"); [[ ${#targets[@]} -eq 0 ]] && targets=(godot jdk ghidra blastem addons)
for t in "${targets[@]}"; do "do_$t"; done
log "done: ${targets[*]}"
