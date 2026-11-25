# Progress

Phases as `CLAUDE.md` lays them out: one phase per session, each ending in
`cargo check --workspace` + `cargo test --workspace`, one commit, then a stop
for approval. Windows-only behaviour stays Windows-only: a Linux build is for
checking and testing, never for running a title.

## Commits

| Commit    | What it did |
| --------- | ----------- |
| `2458e38` | Phase 0: `AUDIT.md` — three-tree topology, per-crate divergence, real build/test results, structural memory map. No source change. |
| `959e971` | Phase 1: workspace compiles and tests on Linux; `scripts/build-linux.sh` cross-builds the Windows PE with cargo-xwin. |
| _step2_   | Phase 1: `scripts/play-linux.sh` — runner detection, vkd3d-proton env, XDG caches and saves. |
| _this commit_ | Phase 1: `docs/linux-baseline.md` — commands, measurement tables and the env matrix for boot failures. |

## Phase 0 — audit (done)

See `AUDIT.md`. Headline: merge base `ffe310eb`, trunk `allforks ef7f036`; the
three forks all fail to build natively on Linux; `cargo xwin build -p victory`
produced a 19.4 MB debug `victory.exe` in 44.8 s; the memory story is
structural only (no runtime numbers exist).

## Phase 1 — Linux/Proton baseline (in progress)

Done:

- Every Linux `cargo check`/`cargo test` failure traced to Windows-only code
  outside a `cfg(windows)` gate (host copies, the title allocator and page
  mapper, modal dialogs, translate/prebuild) rather than to missing
  functionality. Ten tests that parse the running test binary as a PE, or
  assert a drive letter, are ignored off Windows and still run on Windows.
- `cargo check --workspace --all-targets`: exit 0 on
  `x86_64-unknown-linux-gnu` and on `x86_64-pc-windows-msvc` (cargo-xwin).
- `cargo test --workspace`: 399 passed, 0 failed, 18 ignored.
- `scripts/build-linux.sh`: `victory.exe`, 16.4 MB, 24.19 s (debug profile).

- `scripts/play-linux.sh`: finds Proton (Steam `compatibilitytools.d`,
  Proton-CachyOS preferred), umu-run or Wine; sets `VKD3D_CONFIG`,
  `VKD3D_SHADER_CACHE_PATH`, `WINEDEBUG`, `VICTORY_LOG` and the Proton/umu
  prefix variables; keeps caches in `$XDG_CACHE_HOME/victory` and saves in
  `$XDG_DATA_HOME/victory`; takes `--console series-x|series-s` and passes
  title arguments through; `--dry-run` prints the command with the game path
  as `$VICTORY_GAME_DIR`. No `VICTORY_*` tuning flag is set by default.
- `docs/linux-baseline.md`: the commands and the empty tables for frame time,
  RSS, swap, VRAM and shader warm-up, plus the env matrix for boot failures.

Not done yet: a title boot under a compatibility layer, and therefore every
runtime number (frame time, RSS, swap, VRAM, shader warm-up). Those need the
title's own files, so the user runs them.

Known limitations:

- `cargo fmt --check` fails on pre-existing drift in the fork (proved against
  an untouched file at `HEAD`); deferred to the final verification phase so no
  unrelated code is reformatted mid-audit.
- No AMD GPU here; anything AMD-specific stays untested.
