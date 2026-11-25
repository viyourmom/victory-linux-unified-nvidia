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
| `7c5e877` | `PROGRESS.md`: what the series-x run does now, measured, and the one blocker left. |
| _this commit_ | Trexies' fork evaluated commit by commit, host-copy refreshes run on several threads (`VICTORY_WIDE_REFRESH`), `fread` reads beside the title's buffer, and `VICTORY_MEM_STATS=1` reports RSS/commit and the card's budget. |

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

## Trexies' fork (`trexies/VIwork`) — evaluated, two changes ported

Fetched into the temporary remote `trexies` (branch `VIwork`): **90 commits**
on top of `ffe310e` (upstream main), **45,377 lines** across 101 files, while
this tree carries 329 commits since that base. The fork's lineage is
upstream-plus-its-own-work; this tree is the allforks lineage, so the same
files have been rewritten twice, differently.

### What it adds

- **Submission/memory architecture (the bulk of the diff).** Flights of
  submissions sent ahead of their wait (`VICTORY_RELAY`, `VICTORY_LATE_WAIT`),
  copies that settle run on the card (`VICTORY_GPU_BUFFER_COPY`,
  `VICTORY_FILL_ON_CARD`), title buffers folded into their windows
  (`VICTORY_FOLD_BUFFERS`), an indirect-draw budget in card memory with the
  clamp charging once per group, card fetches on a second copy queue, and a
  parallel wide merge. Its own numbers on an RTX 4070: 179 -> 160 ms/frame
  (fold), 159 -> ~121 ms/frame (indirect windows).
- **Shader recompiler.** Clean-up passes over the finished module
  (`VICTORY_SHADER_OPT`: dead code, folding, reuse, branch facts), a census,
  ~43 % fewer host instructions and ~20 ms/frame less GPU time on its machine;
  plus title-specific lowering fixes (fog reconstruction, shadow mask, hair,
  blend-shape skinning, immediate samplers, `v_cvt_f32_f64`, ISG1 usage after
  the opt pass), 5,198 lines added to `emit/lower.rs`.
- **Ray tracing.** Emulated ray/box and ray/triangle tests in DXIL, structure
  builders translate, `VICTORY_RT_OFF` drops the RT pipelines by name.
- **HLE.** `fread`/`ReadFile` that read beside a guarded title buffer, page
  arrays read when a storage request runs, mouse-look (capture, raw motion).
- **Diagnostics.** `victory warm`, program census, more captures.

### Why nothing could be cherry-picked

Each of the 90 commits was applied to this tree with `git apply --3way` in a
linked worktree and the conflict markers counted. **Three applied cleanly**:
`0f78833` (`.bat` line endings), `c255005` (a GPU benchmark test only) and
`e6d37be` (title buffer copies on the card, which needs the flights
architecture this tree does not have). Everything else conflicts, because
the fork's `host.rs` (+6,479 lines), `shadow.rs` (+3,439), `descriptor/host.rs`
(+2,257) and `emit/lower.rs` (+5,198) are rewrites of files this tree also
rewrote. Rule 4 (no speculative cross-crate rewrites) rules out resolving
thousands of conflict hunks by hand.

### What was ported

1. **Host-copy refreshes on several threads** (`crates/victory-gpu/src/host.rs`).
   `Batch::flush` brought up to ~80 copies per submission one after another
   on the submitting thread, each asking the kernel which pages the title
   wrote (`GetWriteWatch`, a page-table walk) and copying them. The copies are
   independent mappings (`Shadow` is already `Send + Sync`, each tracks its
   own pages), so they now go to a thread each: `VICTORY_WIDE_REFRESH=0`
   disables it, `=1` forces it, unset means on where the host has four or more
   logical CPUs. The range bookkeeping (`current`, the counters) stays on the
   submitting thread and in the recorded order. *(fork 787a4a8, same switch
   name and defaults.)*
2. **`fread` reads beside the title's buffer** (`crates/victory-hle/src/modules/files.rs`).
   The CRT read large requests straight into the caller's buffer through the
   kernel, whose writes fail on a block we left read-only to see the title's
   next write (the guard's handler never runs for them). Bytes now come back
   in 1 MiB chunks into a side buffer and are copied in from user mode, where
   a guarded block faults into the guard like the title's own writes. This is
   in the RPF streaming path, where the run spends its world load.
   *(fork 5c17a72, ported onto this tree's `KernelWrite` guard, which must be
   held across the copy.)*
3. **`VICTORY_MEM_STATS=1`** (default off). One `memory:` line per frame-rate
   line: RSS and peak, commit and peak (`K32GetProcessMemoryInfo`). It also
   asks `IDXGIAdapter3::QueryVideoMemoryInfo` for the card's budget; under
   vkd3d-proton the D3D12 device is **not** an `IDXGIDevice`, so the query
   reports that once and stops (see the run below). Reporting only — no
   budget here changes what is allocated.

### What was rejected, and why

| Fork work | Why not ported |
| --- | --- |
| Flights/relay/card copies/fold buffers/indirect budget (the 121–160 ms/frame work) | Needs the rewritten `shadow.rs`/`host.rs`/`indirect.rs`; conflicts in every file it touches. A port is a re-architecture, not a fix. |
| `VICTORY_SHADER_OPT` clean-up passes (~43 % fewer host instructions) | 2,136 new lines plus conflicts in `lower.rs`, `mod.rs`, `shader.rs`, `bitcode.rs`, and it changes the shader-cache key (every program retranslates). Highest-value item left; needs its own phase with a warm-cache measurement. |
| Ray tracing, `VICTORY_RT_OFF` | This tree's default is `VKD3D_CONFIG=nodxr`; RT is a rendering feature, not speed or RSS. |
| Texture eviction by reverse index, sparse descriptor remapping | The fork has no such thing either. Its `VICTORY_TEXTURE_ROOM_PERCENT` is the same budget wall this tree already has in `VICTORY_TEXTURE_BUDGET_MB`. |
| Case-insensitive path cache in `modules::files` | Not in the fork; a new feature with its own invalidation rules. Not started. |
| Wave64 (`VICTORY_WAVE_WIDE`, `VICTORY_HOST_MAX_WAVE`) | AMD-targeted and the fork's own README says its 64-lane barrier form lost the card until made opt-in. Out of scope per the invariants. |

Already present here, so nothing to port: copy-back comparing 64 KiB pieces
with one scratch buffer per submission, `ReadProcessMemory` copies instead of
`VirtualQuery`-then-`memcpy`, and the descriptor clamp past the host heap.

### Measured (one bounded run per arm, 75 s, diagnostics build)

The Enter script (`VICTORY_KEYS=25:Enter,35:Enter,50:Enter`) is required to
leave the menu. Both arms below ran the same build and script; only
`VICTORY_WIDE_REFRESH` differed.

| Arm | copies (ms/frame) | preparing (ms/frame) | RSS | What the run did |
| --- | --- | --- | --- | --- |
| off (`=0`) | 0.0, 0.0, 0.6, 2.4, 6.7, 15.3, 14.0, 2.5 | 0.7 → 34.4 | 6.5 GB → 13.6 GB | menu, one load-start blip, back to menu (30 fps) |
| on (default) | 0.0, 0.2, 0.2, 0.0, 0.2 | 0.5 → 1.5 | 3.0 → 3.6 GB | menu, then world load from 13:39:51, silent stop 13:40:20 |

Honest reading: **the two arms did different work**, so this is indicative,
not a controlled measurement. The serial arm's 15 ms copy bucket came from the
texture-computer stretch; with threads on, the same stretch's buckets read
0.2 ms, and no bucket got worse. A world frame (the fork's 45–50 ms serial
case) is still unreachable here, so the win in the world is **UNVERIFIED** on
this machine; the menu is too light to show it.

`VICTORY_MEM_STATS=1` output from the run: `memory: RSS 2992 MB (peak 2992 MB),
commit 1704 MB (peak 1704 MB)`, then `vram: the device is not an IDXGIDevice;
no video memory budget` — vkd3d-proton's device does not reach a DXGI adapter,
so VRAM has to be read from the host (`nvidia-smi`), not from the runtime.

Also measured: a void run in between (13:37) in which vkd3d-proton failed to
create the Vulkan device (`vr -3`) because the previous `kill -9`'d run had
not finished releasing the GPU. Its log says `no host D3D12 device` and no
frames ran; it is not part of the comparison. Space consecutive runs further
apart, or wait for `wineserver` to exit.

The world load still stops silently at 13:40:20 (texture computer starts,
resource allocations, then no line: no panic, no Xid, no NVRM, no OOM entry),
the same failure as the 13:16 run. Nothing here claims to fix it.
