#!/usr/bin/env bash
# The Linux build (tools/bin/export-linux's out/builds/linux) as one AppImage
# (owner's request, 2026-10-15): an AppDir - the executable and the audio
# library in usr/bin, AppRun a link to the executable, the desktop entry, an
# icon drawn from the project's logo, the build's texts and the AppImage
# runtime's licence in usr/share/doc - packed by the pinned appimagetool with
# the pinned type 2 runtime (tools/versions.env; fetched on first use). The
# game finds its ROM next to the AppImage file (MwRom.game_dir: the runtime's
# APPIMAGE variable).
#   tools/build/appimage.sh BUILD_DIR OUT.AppImage
source "$(dirname "${BASH_SOURCE[0]}")/../bin/_common.sh"
set -euo pipefail
build="$1" dest="$2"
here="$MW_TOOLS/build/appimage"
kit="$MW_TOOLS/appimage"
[[ -x "$kit/appimagetool" && -f "$kit/runtime-x86_64" ]] || "$MW_TOOLS/setup/fetch_tools.sh" appimage
app="$(dirname "$dest")/AppDir-linux"
rm -rf "$app"
mkdir -p "$app/usr/bin" "$app/usr/share/doc/mightyweenie" "$app/usr/share/applications" \
  "$app/usr/share/icons/hicolor/256x256/apps"
cp "$build/mightyweenie.x86_64" "$build"/libmw_audio.linux.*.so "$app/usr/bin/"
cp "$build/README.txt" "$build/LICENSE.txt" "$build/THIRD_PARTY_NOTICES.txt" "$app/usr/share/doc/mightyweenie/"
cp "$kit/RUNTIME_LICENSE.txt" "$app/usr/share/doc/mightyweenie/APPIMAGE_RUNTIME_LICENSE.txt"
ln -s usr/bin/mightyweenie.x86_64 "$app/AppRun"
cp "$here/mightyweenie.desktop" "$app/"
cp "$here/mightyweenie.desktop" "$app/usr/share/applications/"
bin="$(mw_godot_headless)" || exit 1
"$bin" --headless --path "$MW_ROOT/game" -s "$here/make_icon.gd" -- \
  "$MW_ROOT/game/assets/logo/mightyweenie_logo.png" "$app/mightyweenie.png" > "$(dirname "$dest")/appimage-icon.log" 2>&1
[[ -s "$app/mightyweenie.png" ]] || { echo "appimage: no icon (see appimage-icon.log)" >&2; exit 1; }
cp "$app/mightyweenie.png" "$app/usr/share/icons/hicolor/256x256/apps/"
ln -s mightyweenie.png "$app/.DirIcon"
rm -f "$dest"
# (appimagetool is an AppImage itself: extracted and run, no FUSE needed to build)
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$kit/appimagetool" --no-appstream --runtime-file "$kit/runtime-x86_64" \
  "$app" "$dest" > "$(dirname "$dest")/appimagetool.log" 2>&1 \
  || { tail -20 "$(dirname "$dest")/appimagetool.log"; exit 1; }
chmod +x "$dest"
ls -l "$dest"
