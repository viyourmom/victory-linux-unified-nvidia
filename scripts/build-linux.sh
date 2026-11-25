#!/usr/bin/env bash
# Builds the Windows PE that runs a title under Proton/Wine, from Linux.
#
# The runtime is a Windows program: it maps a title's PE image with the
# Windows loader, so a Linux host cross-builds it instead of compiling it
# natively (see AUDIT.md, item 6). cargo-xwin supplies the MSVC-ABI import
# libraries that `windows` and `windows-sys` link against.
#
#   scripts/build-linux.sh            release, x86_64-pc-windows-msvc
#   scripts/build-linux.sh --debug    dev profile, faster to rebuild
#   scripts/build-linux.sh --gnu      x86_64-pc-windows-gnu, needs mingw-w64
#
# The result is target/<target>/<profile>/victory.exe. The build reads only
# this repository; nothing here touches the game folder.
set -euo pipefail

cd "$(dirname "$0")/.."

target=x86_64-pc-windows-msvc
profile=release
build_args=(--release)

for arg in "$@"; do
    case "$arg" in
    --debug)
        profile=debug
        build_args=()
        ;;
    --gnu)
        target=x86_64-pc-windows-gnu
        ;;
    -h | --help)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "build-linux.sh: unknown argument: $arg" >&2
        exit 2
        ;;
    esac
done

if [ "$target" = x86_64-pc-windows-gnu ]; then
    if ! command -v x86_64-w64-mingw32-dlltool >/dev/null; then
        echo "build-linux.sh: the GNU target needs mingw-w64's dlltool" >&2
        echo "  CachyOS/Arch: sudo pacman -S mingw-w64-gcc" >&2
        exit 1
    fi
    cargo build -p victory --target "$target" ${build_args[@]+"${build_args[@]}"}
else
    if ! command -v cargo-xwin >/dev/null; then
        echo "build-linux.sh: the MSVC target needs cargo-xwin" >&2
        echo "  cargo install cargo-xwin" >&2
        exit 1
    fi
    cargo xwin build -p victory --target "$target" ${build_args[@]+"${build_args[@]}"}
fi

exe="${CARGO_TARGET_DIR:-target}/$target/$profile/victory.exe"
if [ ! -f "$exe" ]; then
    echo "build-linux.sh: built, but $exe is missing" >&2
    exit 1
fi
printf '%s (%s bytes)\n' "$exe" "$(stat -c %s "$exe")"
