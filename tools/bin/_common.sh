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
