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
| `a26f6c1` | Phase 1: `scripts/play-linux.sh` — runner detection, vkd3d-proton env, XDG caches and saves. |
| `0b208da` | Phase 1: `docs/linux-baseline.md` — commands, measurement tables and the env matrix for boot failures. |
| `2163dc2` | Phase 1: `play-linux.sh` fixups before the first boot — release build by default, one prefix per runner, `Z:` title paths, directories made before exec. |
| `398edf5` | Boot diagnosis: `VICTORY_LOG_FILE` (a Proton run's log has to go to a file), `nodxr` + `PROTON_USE_NTSYNC=1` defaults, warning when the host clamps a descriptor heap. |
| `b41d337` | Phase 1: `PROGRESS.md` records the first boot attempt and what its logs prove. |
| `a1aeebf` | Runtime invariants in `CLAUDE.md`: series-x is the target, the 1,000,000-slot host heap, 16 GB/8 GB discipline, portable Vulkan + NTSYNC, and the evidence loop. |
| `6ffc235` | The descriptor loop counts instead of logging per slot, staging buffers are capped at 1 GiB, and host textures stop at the card's budget instead of killing the driver. |
| _this commit_ | `PROGRESS.md`: what the series-x run does now, measured, and the one blocker left. |

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
- Fixups after re-reading the script against what the first boot will need:
  the runtime defaults to the **release** build that `build-linux.sh` writes
  (`--profile debug` picks the debug one; `--debug` stays what it says, log
  verbosity), and a missing `.exe` is a clear failure rather than a Wine
  message. Each runner gets its own prefix
  (`$XDG_DATA_HOME/victory/prefix/{proton,umu,wine}`) instead of three layers
  sharing registry and DLL state. `mkdir -p` runs for the prefix, the vkd3d
  shader cache, both XDG roots and `PROTON_LOG_DIR` before `exec`, because
  `proton run` will not create a compatdata folder itself. The title path is
  handed over as a Windows path (`/x/y` → `Z:\x\y`, a path already naming a
  drive passes through), and `--debug` now sets
  `WINEDEBUG=err+all,warn+loaddll` so loader and DLL errors are visible;
  `PROTON_LOG`/`PROTON_LOG_DIR` are limited to proton and umu-run.
- `docs/linux-baseline.md`: the commands and the empty tables for frame time,
  RSS, swap, VRAM and shader warm-up, plus the env matrix for boot failures.

### Boot attempt 1 — what the logs prove

Two runs exist: the user's (12:33, `VKD3D_CONFIG=nodxr`, `umu-run`, window
black) and an instrumented one (12:37, diagnostics build, `dxr,dxr11`,
`VICTORY_CAPTURE`, 180 s budget).

From `~/.cache/victory/proton/steam-*.log` and the captured frame:

- vkd3d-proton 3.1.0 on the RTX 3070 (driver 620.73.4): DXR 1.0/1.1/1.2
  enabled, DX Ultimate, SM 6.6-6.8 (6.9 experimental), `VK_EXT_descriptor_buffer`.
- Swapchain created at **3840×2160**, BufferCount 2, four images,
  `KHR_present_wait` with a 3-frame latency.
- Exactly **one frame was presented**, and `frame-1.png` is all black
  (half-size 1920×1080, largest byte 0).
- Two view heaps were requested larger than the host's limit
  (**2,097,152** and **1,310,720** against vkd3d-proton's 1,000,000); our
  `HEAP_VIEWS` is `1 << 21`.
- After device setup vkd3d-proton reports the title "stopped creating new
  PSOs" twice and no draw or dispatch follows: the world never draws.
- The process ended by itself after 51 s with **exit 58**, no `crashes.log`,
  and no line of the runtime's own stdout/stderr in either log — hence
  `VICTORY_LOG_FILE`.

So the stall is after D3D12 device and swapchain creation and before world
drawing, not in the Wine loader, not in DXR init (which succeeded) and not in
shader translation of the first PSOs. Because both `nodxr` and `dxr,dxr11`
runs are black, DXR is not the divider; the safe default is now `nodxr`.

### Merge check (what is actually left to port)

- **upstream**: `git rev-list --count HEAD..upstream` = **0** — already
  contained, nothing to merge.
- **ztrx**: 13 commits, all still "absent" as patches because the fork was
  hand-ported file by file. Content check: `wanted_early`/`note_used` are
  present, so the pipeline-library work is in; `VICTORY_PIPELINE_WAIT_MS`,
  `VICTORY_WAVE_WIDE` and `set_host_max_wave` are **absent**.
- The one boot-shaped stability fix, `e9765a7` ("Fix the device loss
  introduced by the wave64 update"), makes `VICTORY_WAVE_WIDE` opt-in because
  that barrier form lost the card. **This tree has no such switch and no
  wide-wave barrier form**, so there is nothing to port: a port would add a
  flag for code that does not exist.
- `d279e69` (configurable pipeline wait) is behaviour-changing and not
  boot-related; deferred to Phase 4 where it can be measured, per rule 6.

### Still open

- Every runtime number (frame time, RSS, swap, VRAM, warm-up) needs a boot
  that reaches the world. None exists yet.
- Whether the descriptor-heap clamp is what keeps the world from drawing:
  the next boot's `victory.log` now answers it with the new warning.
- No `--console series-s` run yet.

Known limitations:

- `cargo fmt --check` fails on pre-existing drift in the fork (proved against
  an untouched file at `HEAD`); deferred to the final verification phase so no
  unrelated code is reformatted mid-audit.
- No AMD GPU here; anything AMD-specific stays untested.

## Phase 1 loop: series-x on the test machine (measured)

Three runs of the release PE, `--console series-x --debug`, each with the
Enter that leaves the menu (`VICTORY_KEYS=25:Enter,35:Enter,50:Enter`, a
diagnostics build). The game renders the legal screens and the menu, then
loads the world.

| Run | What changed | Outcome |
| --- | --- | --- |
| 13:03 | baseline | 621,440-line / 130 MB log flood; host textures 8,156 MB; `NVRM: Out of memory` 13:04:48 |
| 13:12 | staging capped at 1 GiB | staging 76 MB; host textures 8,223 MB; `NVRM: Out of memory` 13:12:25 |
| 13:14 | texture budget 6,656 MB + Enter | host textures stay 6,979 MB, 1,024 new ones refused; **no NVRM OOM**; world load starts (texture computer 512x512, `story000` anim RPFs, 126 XMA voices, fade levels 219-228); process gone at frame ~2,279 (13:16:30) |

Per-frame numbers from the last run: 30 fps / 33.3 ms at the menu, 10-12
draws/frame, 2,404 host textures, staging 76 MB, peak RSS 17 GB on 16 GB of
RAM with 15.5 GB of zram. The descriptor walk is 2,097,153 slots with the
highest index 1,245,183, now reported in 19 lines.

Still open, in the order the evidence puts them:

- **The silent end.** No panic, no `win32` exception, no Xid, no device
  removal, no OOM-kill entry: the process is simply gone, exit 3, at the
  moment the texture computer starts and 126 XMA voices are enabled. Peak RSS
  of 17 GB says system memory, so the next step is to find whether it is the
  title, the emulated memory or the driver's host-side copies (Phase 2's
  lazy commit and eviction), not to guess.
- **Host textures are 1:1 with title textures**: 8 GB of them are the title's
  own resident set, so a budget alone drops detail rather than restoring it.
  Real eviction needs a reverse index from a host texture to the heap slots
  that view it (`Viewed` has none), which is the Phase 2 descriptor-recycling
  work.
- **Two compute pipelines are refused by vkd3d-proton**: `Required WaveSize
  range [64, 64], but supported range is [32, 32]` - a wave64 shader on
  NVIDIA's 32-lane waves. The dispatches are dropped; world ComputeFX work
  that needs them will be missing. This is the portable-SPIR-V rule, not a
  driver quirk.
- **series-s** was not run (stalls before the first present, per the
  invariants).
