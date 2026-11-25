# Linux baseline: the commands and the numbers to fill in

What Phase 2 must not change without a "before". Only you can run these: they
need the title's own files, which the agent never reads or lists (`CLAUDE.md`,
hard rule 1). `scripts/play-linux.sh` hands the executable you name to the
runtime and never looks in the game folder itself.

Record every run with the same four facts, or the numbers cannot be compared:
driver version, Proton build, runtime commit (`git rev-parse --short HEAD`),
and console model.

## 1. Build once (release)

```bash
./scripts/build-linux.sh                     # target/x86_64-pc-windows-msvc/release/victory.exe
```

`victory.toml` at the repository root needs `[paths].game_dir` (see
`victory.example.toml`). Nothing else in this document reads that file.

## 2. Check the command line before running anything

```bash
./scripts/play-linux.sh --exe <name.exe> --dry-run
./scripts/play-linux.sh --list
```

`--dry-run` prints the environment and the exact command with the game path
as `$VICTORY_GAME_DIR`, so the output is safe to paste into a bug report.

## 3. First run: does it boot at all?

```bash
./scripts/play-linux.sh --exe <name.exe> --console series-x --debug 2>&1 | tee boot.log
```

`--debug` sets `VICTORY_LOG=debug`, `VKD3D_DEBUG=warn` and `PROTON_LOG=1`
(its log goes to `$XDG_CACHE_HOME/victory/proton/`). Note the first line that
mentions a Windows API we do not answer — that is the boot blocker to record
in `PROGRESS.md`.

If it dies before drawing anything, stop here and go to §6: the numbers below
mean nothing until a frame appears.

## 4. Measuring, in a second terminal while the title runs

```bash
# RSS, swap, and the machine's own swap use, once a second until it exits.
pid=$(pgrep -f 'victory\.exe' | head -1)
while kill -0 "$pid" 2>/dev/null; do
  rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status)
  swap=$(awk '/VmSwap/{print $2}' /proc/$pid/status)
  host=$(awk '/SwapTotal|SwapFree/{printf "%s ", $2}' /proc/meminfo)
  echo "$(date +%s) rss_kb=$rss swap_kb=$swap host_swap_total_free=$host"
  sleep 1
done | tee rss.log
```

```bash
# VRAM and GPU utilisation, twice a second (NVIDIA proprietary driver).
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu \
  --format=csv,noheader,nounits -lms 500 | tee vram.csv
```

Both numbers are what `VICTORY_MEM_STATS=1` will report in Phase 2; these are
the external cross-check for it.

**Frame time**: there is no runtime counter yet, so record how you got it.
With MangoHud installed, prefix the launcher:

```bash
MANGOHUD=1 mangohud ./scripts/play-linux.sh --exe <name.exe> --console series-x
```

otherwise use the title's own counter and say so — the two are not
comparable across runs and must not be mixed in one table.

**Shader warm-up**: wall-clock from launching to the first frame you can
control, three runs in a row. The first run after deleting
`$XDG_CACHE_HOME/victory/vkd3d` is the cold number; the second is the warm
one. Record both.

## 5. The table to fill in

One row per run. `p50/p95` are frame times in ms; peaks are the maximum of
the sampled log.

| # | date | commit | console | profile | runner | p50 ms | p95 ms | RSS peak MiB | swap peak MiB | VRAM peak MiB | warm-up s (cold/warm) | notes |
|---|------|--------|---------|---------|--------|--------|--------|--------------|---------------|---------------|------------------------|-------|
| 1 |      |        | series-x | release |        |        |        |              |               |               |                        |       |
| 2 |      |        | series-s | release |        |        |        |              |               |               |                        |       |
| 3 |      |        | series-x | release |        |        |        |              |               |               |                        |       |

Expected, from `AUDIT.md` (structural only, not measured): the title asks for
a 6.1 GiB physical-page section at once, Series X reports 10 GiB and Series S
7,776 MiB, and the machine has 16 GB of RAM — so swap is the number to watch
on run 1, and the reason `--console series-s` is a separate row.

## 6. When it does not boot: settings to narrow it down

Set one at a time, re-run, keep the log:

| Symptom | Setting | What it changes |
|---------|---------|-----------------|
| Any early exit | `VICTORY_LOG=victory_loader=trace,info` | Every prepare/map/bind step, not just info |
| Missing import or a stub being called | `VICTORY_LOG=debug` | Which `dll!function` we answer, and with what |
| Nothing after device creation | `VKD3D_DEBUG=warn` | vkd3d-proton's own warnings (err/fixme/warn/trace) |
| Black shadows or no lighting | `VKD3D_CONFIG=nodxr` | Turns ray tracing off entirely, to compare |
| Suspected driver/validation fault | `VKD3D_CONFIG=vk_debug` | Loads the Vulkan validation layer (slower) |
| Suspected stale shaders | `rm -rf $XDG_CACHE_HOME/victory/vkd3d` | Cold shader cache, for the cold warm-up number |
| Wine-level failure | `WINEDEBUG=+loaddll,+module` | Which DLL load failed (very noisy) |
| Region or locale | `LANG`, `LC_ALL=C` | Rules out encoding in path handling |

`--debug` already covers the first two rows' environment; the table is for
what to change *while* investigating, not for normal runs.

Boot blockers already known from the audit, so they are not surprises: the
in-process PE loader and its fixed-address mappings, write-watch page
queries, DRED/telemetry calls, and the missing page mapper before
`xmem` exists (`AUDIT.md` §5, §7).

## 7. What to send back

For each row: `rss.log`, `vram.csv`, and the first 200 lines of `boot.log` —
with paths as `play-linux.sh --dry-run` prints them. Do not attach the game
folder, a shader pack, or a save file; `CLAUDE.md` forbids it and none of the
numbers need them.
