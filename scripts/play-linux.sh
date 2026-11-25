#!/usr/bin/env bash
# Runs the Windows runtime built by scripts/build-linux.sh under Proton,
# umu-run or plain Wine, with the environment vkd3d-proton needs.
#
# `--dry-run` prints the environment and the command it would run, with the
# paths that came from victory.toml shown as variables: nothing here ever
# echoes your game folder. The script never lists or reads that folder; it
# only passes the executable you name to the runtime.
#
# The runtime is a Windows program (AUDIT.md, item 6), so it runs under a
# compatibility layer even on Linux. Caches go to $XDG_CACHE_HOME/victory
# (disposable), what titles save goes to $XDG_DATA_HOME/victory (keep it).
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"

usage() {
    cat <<'EOF'
usage: scripts/play-linux.sh --exe <title.exe> [options] [-- title args]

Runs the cross-built runtime under Proton, umu-run or Wine.

options:
  --exe <path>        the title executable; relative paths are taken from the
                      configured game directory (required)
  --console <model>   series-x (default) or series-s, what the title sees
  --runner <name>     proton[:PATH] | umu-run | wine (default: auto — the
                      Proton in a Steam compatibilitytools.d first, with
                      Proton-CachyOS preferred, then umu-run, then Wine)
  --runtime <path>    the built runtime (default: the release build, else the
                      debug one that --debug of build-linux.sh leaves)
  --debug             VKD3D_DEBUG=warn, VICTORY_LOG=debug, PROTON_LOG=1
  --dry-run           print the environment and the command, run nothing
  --list              list the compatibility layers found, then exit
  -h, --help          this text

Nothing is optimised by default: VICTORY_RELAY, VICTORY_LATE_WAIT,
VICTORY_WIDE_BACK and VICTORY_PIPELINE_WAIT_MS are left unset here, to be
turned on one at a time (and measured) in Phase 4.
EOF
}

dry_run=0
list_only=0
use_debug=0
console=series-x
runner=auto
exe=
runtime=
title_args=()

while [ $# -gt 0 ]; do
    case $1 in
    --dry-run) dry_run=1 ;;
    --list) list_only=1 ;;
    --debug) use_debug=1 ;;
    --console) console=${2:?--console needs series-x or series-s}; shift ;;
    --console=*) console=${1#*=} ;;
    --runner) runner=${2:?--runner needs a name}; shift ;;
    --runner=*) runner=${1#*=} ;;
    --exe) exe=${2:?--exe needs a path}; shift ;;
    --exe=*) exe=${1#*=} ;;
    --runtime) runtime=${2:?--runtime needs a path}; shift ;;
    --runtime=*) runtime=${1#*=} ;;
    -h | --help)
        usage
        exit 0
        ;;
    --)
        shift
        title_args=("$@")
        break
        ;;
    *)
        echo "play-linux.sh: unknown argument: $1 (see --help)" >&2
        exit 2
        ;;
    esac
    shift
done

case $console in
series-x | series-s) ;;
*)
    echo "play-linux.sh: --console takes series-x or series-s, not '$console'" >&2
    exit 2
    ;;
esac

# --- finding a compatibility layer ---------------------------------------
#
# Proton ships as a folder with a `proton` script, installed by Steam into
# compatibilitytools.d (or by hand anywhere, named in PROTONPATH). umu-run
# takes PROTONPATH too. Plain Wine is the last resort: it has no
# vkd3d-proton of its own unless the system installs one beside it.

proton_dirs=(
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.steam/root/compatibilitytools.d"
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"
    "/usr/share/steam/compatibilitytools.d"
    "/usr/local/share/steam/compatibilitytools.d"
)

find_protons() {
    local d p real
    local -A seen=()
    if [ -n "${PROTONPATH:-}" ] && [ -x "$PROTONPATH/proton" ]; then
        seen[$(readlink -f "$PROTONPATH")]=1
        printf '%s\t%s\n' "$(basename "$PROTONPATH")" "$PROTONPATH"
    fi
    for d in "${proton_dirs[@]}"; do
        [ -d "$d" ] || continue
        for p in "$d"/*/proton; do
            [ -x "$p" ] || continue
            # The Steam directories are usually symlinks to each other.
            real=$(readlink -f "$(dirname "$p")")
            [ -z "${seen[$real]:-}" ] || continue
            seen[$real]=1
            printf '%s\t%s\n' "$(basename "$(dirname "$p")")" "$(dirname "$p")"
        done
    done
}

# Proton-CachyOS is what this machine runs; after it, the newest build by
# version (GE-Proton11-3 after GE-Proton10-9), whatever its name.
pick_proton() {
    local line
    local -a sorted=() cachy=()
    mapfile -t sorted < <(find_protons | sort -t $'\t' -k1,1 -rV)
    [ ${#sorted[@]} -gt 0 ] || return 1
    for line in "${sorted[@]}"; do
        case ${line%%$'\t'*} in
        # The Steam-installed build before a system package
        # (`proton-cachyos-slr`): the former is the one that gets updated.
        Proton-CachyOS*)
            printf '%s\n' "${line#*$'\t'}"
            return 0
            ;;
        *[Cc]achyos*) cachy+=("$line") ;;
        esac
    done
    if [ ${#cachy[@]} -gt 0 ]; then
        printf '%s\n' "${cachy[0]#*$'\t'}"
        return 0
    fi
    printf '%s\n' "${sorted[0]#*$'\t'}"
}

if [ "$list_only" -eq 1 ]; then
    echo "proton:"
    protons=()
    mapfile -t protons < <(find_protons)
    if [ ${#protons[@]} -gt 0 ]; then
        printf '%s\n' "${protons[@]}" | sort -t $'\t' -k1,1 -rV | sed 's/\t/  /'
        echo "  default: $(pick_proton)"
    else
        echo "  none in compatibilitytools.d (set PROTONPATH)"
    fi
    echo "umu-run: $(command -v umu-run || echo none)"
    echo "wine:    $(command -v wine || echo none)"
    exit 0
fi

runner_kind=
runner_path=
resolve_runner() {
    case $runner in
    auto)
        if runner_path=$(pick_proton); then
            runner_kind=proton
        elif command -v umu-run >/dev/null; then
            runner_kind=umu-run
            runner_path=$(command -v umu-run)
        elif command -v wine >/dev/null; then
            runner_kind=wine
            runner_path=$(command -v wine)
        else
            echo "play-linux.sh: no Proton, umu-run or wine found" >&2
            return 1
        fi
        ;;
    proton | proton:*)
        runner_kind=proton
        if [ "$runner" = proton ]; then
            runner_path=$(pick_proton) || {
                echo "play-linux.sh: no Proton found (see --list)" >&2
                return 1
            }
        else
            runner_path=${runner#proton:}
            [ -x "$runner_path/proton" ] || {
                echo "play-linux.sh: $runner_path has no proton script" >&2
                return 1
            }
        fi
        ;;
    umu-run | umu)
        runner_kind=umu-run
        runner_path=$(command -v umu-run) || {
            echo "play-linux.sh: umu-run is not installed" >&2
            return 1
        }
        ;;
    wine)
        runner_kind=wine
        runner_path=$(command -v wine) || {
            echo "play-linux.sh: wine is not installed" >&2
            return 1
        }
        ;;
    *)
        echo "play-linux.sh: unknown --runner '$runner' (proton[:PATH], umu-run, wine)" >&2
        return 1
        ;;
    esac
}
resolve_runner

steam_client() {
    local d
    for d in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.steam/root"; do
        if [ -d "$d" ]; then
            printf '%s\n' "$d"
            return
        fi
    done
    printf '%s\n' "$HOME"
}

# --- the configuration ----------------------------------------------------
#
# The runtime resolves victory.toml itself (env first, then [paths]); this
# only needs the game directory to make a relative --exe absolute. Python
# reads the file so quoted Windows paths and `#` in values work as TOML says.

config_path() {
    if ! command -v python3 >/dev/null; then
        echo "play-linux.sh: python3 is needed to read victory.toml" >&2
        echo "  or export VICTORY_GAME_DIR yourself" >&2
        return 1
    fi
    python3 - "$1" <<'PY'
import os, sys, tomllib
key = sys.argv[1]
env_names = {
    "game_dir": "VICTORY_GAME_DIR",
    "cache_dir": "VICTORY_CACHE_DIR",
    "data_dir": "VICTORY_DATA_DIR",
}
value = os.environ.get(env_names[key]) or ""
if not value:
    path = os.environ.get("VICTORY_CONFIG") or "victory.toml"
    try:
        with open(path, "rb") as f:
            value = tomllib.load(f).get("paths", {}).get(key) or ""
    except FileNotFoundError:
        value = ""
print(value)
PY
}

game_dir=$(config_path game_dir) || exit 1
if [ -z "$game_dir" ]; then
    echo "play-linux.sh: no game directory configured." >&2
    echo "  Set [paths].game_dir in victory.toml (see victory.example.toml)" >&2
    echo "  or export VICTORY_GAME_DIR. The value is never printed here." >&2
    exit 1
fi

if [ -z "$exe" ]; then
    echo "play-linux.sh: --exe <title.exe> is required." >&2
    echo "  The script does not search the game folder for it." >&2
    exit 2
fi
case $exe in
/*) title_exe=$exe ;;
*) title_exe="$game_dir/$exe" ;;
esac
exe_name=$(basename "$title_exe")

if [ -z "$runtime" ]; then
    for candidate in \
        "target/x86_64-pc-windows-msvc/release/victory.exe" \
        "target/x86_64-pc-windows-msvc/debug/victory.exe"; do
        [ -f "$candidate" ] && runtime=$candidate && break
    done
    runtime=${runtime:-target/x86_64-pc-windows-msvc/release/victory.exe}
fi

if [ "$dry_run" -eq 0 ]; then
    [ -f "$runtime" ] || {
        echo "play-linux.sh: no runtime at $runtime — run scripts/build-linux.sh first" >&2
        exit 1
    }
    [ -f "$title_exe" ] || {
        echo "play-linux.sh: the executable named by --exe does not exist" >&2
        exit 1
    }
fi

# --- the environment ------------------------------------------------------
#
# VICTORY_CACHE_DIR / VICTORY_DATA_DIR  the runtime's derived data and the
#   title's persistent storage, kept apart (below $XDG_*, never the repo).
# VKD3D_CONFIG=dxr,dxr11  vkd3d-proton's DXR; the title lights with ray
#   tracing and this box has an RTX 3070. `nodxr` disables it to bisect
#   black shadows; without either, vkd3d-proton enables DXR only when it
#   judges it safe (`dxr` forces it).
# VKD3D_SHADER_CACHE_PATH  vkd3d-proton's own translated-shader and pipeline
#   cache (a directory; the runtime's own caches are separate).
# WINEDEBUG=-all  Wine's fixme spam otherwise buries vkd3d and our lines.
# VICTORY_LOG  our tracing filter (falls back to RUST_LOG).
# --debug also sets VKD3D_DEBUG=warn, VICTORY_LOG=debug and PROTON_LOG=1
#   (with PROTON_LOG_DIR, so the log lands in the cache, not $HOME).
#
# Inherited values win: `set_default` only fills what is unset.

cache_root=${VICTORY_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/victory}
data_root=${VICTORY_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/victory}
prefix=$data_root/prefix

names=()
values=()
shown=()
add_env() {
    names+=("$1")
    values+=("$2")
    shown+=("$3")
}
set_default() {
    if [ -n "${!1:-}" ]; then
        add_env "$1" "${!1}" "\$$1 (inherited)"
    else
        add_env "$1" "$2" "$3"
    fi
}

set_default VICTORY_CACHE_DIR "$cache_root" '$XDG_CACHE_HOME/victory'
set_default VICTORY_DATA_DIR "$data_root" '$XDG_DATA_HOME/victory'
set_default VKD3D_CONFIG "dxr,dxr11" 'dxr,dxr11'
set_default VKD3D_SHADER_CACHE_PATH "$cache_root/vkd3d" '$XDG_CACHE_HOME/victory/vkd3d'
set_default WINEDEBUG "-all" '-all'
set_default VICTORY_LOG "$([ "$use_debug" -eq 1 ] && echo debug || echo info)" \
    "$([ "$use_debug" -eq 1 ] && echo debug || echo info)"
if [ "$use_debug" -eq 1 ]; then
    set_default VKD3D_DEBUG warn warn
    set_default PROTON_LOG 1 1
    set_default PROTON_LOG_DIR "$cache_root/proton" '$XDG_CACHE_HOME/victory/proton'
fi

case $runner_kind in
proton)
    # Proton needs a prefix (its own STEAM_COMPAT_DATA_PATH, not WINEPREFIX)
    # and a Steam client directory to borrow the runtime from.
    set_default STEAM_COMPAT_DATA_PATH "$prefix" '$XDG_DATA_HOME/victory/prefix'
    set_default STEAM_COMPAT_CLIENT_INSTALL_PATH "$(steam_client)" "$(steam_client)"
    ;;
umu-run)
    # umu-run wants PROTONPATH (a Proton folder) and names its prefix in
    # WINEPREFIX; GAMEID only labels it (0 = unknown to protonfixes).
    if [ -z "${PROTONPATH:-}" ] && proton=$(pick_proton); then
        set_default PROTONPATH "$proton" "$proton"
    fi
    set_default WINEPREFIX "$prefix" '$XDG_DATA_HOME/victory/prefix'
    set_default GAMEID 0 0
    ;;
wine)
    set_default WINEPREFIX "$prefix" '$XDG_DATA_HOME/victory/prefix'
    ;;
esac

# --- the command ----------------------------------------------------------

runtime_args=(run "$title_exe" --console "$console" --execute)
runtime_shown=(run "\$VICTORY_GAME_DIR/$exe_name" --console "$console" --execute)
if [ ${#title_args[@]} -gt 0 ]; then
    runtime_args+=(-- "${title_args[@]}")
    runtime_shown+=(-- "${title_args[@]}")
fi

case $runner_kind in
proton) cmd=("$runner_path/proton" run "$runtime" "${runtime_args[@]}") ;;
*) cmd=("$runner_path" "$runtime" "${runtime_args[@]}") ;;
esac
case $runner_kind in
proton) shown_cmd=("$runner_path/proton" run "$runtime" "${runtime_shown[@]}") ;;
*) shown_cmd=("$runner_path" "$runtime" "${runtime_shown[@]}") ;;
esac

if [ "$dry_run" -eq 1 ]; then
    echo "# runner: $runner_kind ($runner_path)"
    echo "# paths from victory.toml are shown as variables; --exe as its file name"
    echo "env:"
    for i in "${!names[@]}"; do
        printf '  %s=%s\n' "${names[$i]}" "${shown[$i]}"
    done
    echo "command:"
    printf '  '
    first=1
    for arg in "${shown_cmd[@]}"; do
        [ "$first" -eq 1 ] || printf ' '
        first=0
        case $arg in
        # Quote only what needs it, so the $VARIABLE placeholders stay
        # readable rather than printf %q's escaped form.
        *[[:space:]]*) printf "'%s'" "$arg" ;;
        *) printf '%s' "$arg" ;;
        esac
    done
    printf '\n'
    exit 0
fi

# The caches and the prefix are ours to make; victory.toml paths are the
# runtime's to make (it checks them against the asset policy itself).
mkdir -p "$cache_root" "$data_root" "$prefix"

for i in "${!names[@]}"; do
    export "${names[$i]}=${values[$i]}"
done

exec "${cmd[@]}"
