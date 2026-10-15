# Shared helpers for tools/bin wrappers. Source, don't execute.
# Resolves the repo root from the wrapper's own location so the same scripts
# work wherever the folder is mounted (a desktop and a VM sharing it, say).
MW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../versions.env
source "$MW_ROOT/tools/versions.env"
MW_TOOLS="$MW_ROOT/tools"
MW_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mightyweenie"

mw_require() {  # mw_require <path> <component>
  [[ -e "$1" ]] || { echo "missing $2 - run: tools/setup/fetch_tools.sh $2" >&2; exit 1; }
}

# The main checkout: this one, or the one whose .worktrees/ holds this one (a
# plan's worktree) - found by its path, no git needed (a VM sharing the folder
# can't run git in a worktree: its .git names the desktop's path).
mw_main_root() {
  if [[ "$MW_ROOT" == */.worktrees/* ]]; then echo "${MW_ROOT%%/.worktrees/*}"; else echo "$MW_ROOT"; fi
}
MW_MAIN="$(mw_main_root)"

# The pinned Godot for windowed runs: MW_GODOT if set, else this checkout's
# tools/godot, else the main checkout's (fetched there, never committed: a
# worktree has none), else the headless copy below.
mw_godot() {
  local b
  for b in "${MW_GODOT:-}" "$MW_TOOLS/godot/godot" "$MW_MAIN/tools/godot/godot" \
      "$MW_CACHE/godot-headless-$GODOT_VERSION/godot"; do
    [[ -n "$b" && -x "$b" ]] && { echo "$b"; return 0; }
  done
  echo "missing godot - run: tools/setup/fetch_tools.sh godot" >&2
  return 1
}

# The private headless copy (tools/bin/godot-headless): MW_GODOT if set, else
# a copy of the pinned binary in ~/.cache/mightyweenie with its own ._sc_
# marker (made from mw_godot's the first time), so headless runs never write
# the desktop editor's settings or ~/.config/godot.
mw_godot_headless() {
  if [[ -n "${MW_GODOT:-}" ]]; then echo "$MW_GODOT"; return 0; fi
  local bin_dir="$MW_CACHE/godot-headless-$GODOT_VERSION" src
  if [[ ! -x "$bin_dir/godot" ]]; then
    src="$(MW_GODOT= mw_godot)" || return 1
    mkdir -p "$bin_dir"
    cp "$src" "$bin_dir/godot.tmp" && mv "$bin_dir/godot.tmp" "$bin_dir/godot"
    touch "$bin_dir/._sc_"
  fi
  echo "$bin_dir/godot"
}

# A command on a virtual display (real frames without a screen: renders,
# captures): mw_xvfb CMD [ARGS...].
mw_xvfb() {
  xvfb-run -a -s "-screen 0 1280x1024x24" "$@"
}
