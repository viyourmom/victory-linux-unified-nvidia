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

## Three more forks audited: soldsawn, datingesp, CGBJ (2026-11-25)

Fetched as temporary remotes; all removed before the commit below.

### `datingesp-hash/victory-proton`

Not a fork of the code: **four files** — `victory-proton` (a bash launcher),
`README.md`, a `.gitignore` and `wine/wineserver-view-tree.patch`. Nothing to
port: `scripts/play-linux.sh` already sets `PROTON_USE_NTSYNC=1`,
`VKD3D_CONFIG=nodxr`, per-runner prefixes and `VICTORY_LOG_FILE`, and its
`--debug` writes the log the patch is about. One idea kept in mind rather than
copied: it lets the vkd3d-proton build be chosen with a folder (`VICTORY_VKD3D_DIR`),
which is how a tracing build would be A/B'd. Not added; no build to point it
at on this machine yet.

### `soldsawn/victory-nvidia-8gb`

59 commits on `ffe310e` (the same base as Trexies' fork), 63,754 lines over
116 files, of which 5,418 are `emit/lower.rs` and 1,164 a new
`wave64_tests.rs`. Its headline is **wave64 programs in a paired form on
32-lane hosts** (`26600c6`: two console lanes per host thread, "230 more
programs pass"). That is the only fix we have seen for our two refused
compute pipelines (`Required WaveSize range [64, 64], but supported range is
[32, 32]` on the RTX 3070), and it is a re-architecture of `wave.rs`
(651 lines changed) with its own test suite — not portable in a session.

Nothing else there was new to us: wide refreshes (`5b7c878`, same switch we
ported from Trexies), texture mips dropped on the host (`VICTORY_TEXTURE_DROP_MIPS`),
a shadow SNAPS flush before drop, and `xmem` low-4GiB guards.

### `JordanFromIT/CGBJ-VIctory` (the one to learn from)

**458 commits** ahead of `d2a4bae`, 70,639 lines over 165 files, plus real
notes: `docs/PROTON-STATUS.md`, `docs/notes/{vram-placement,title-memory-hazards,queue-wait-path,submission-chain}.md`.
It targets **stock Proton on an RX 7900 XTX** and reports a running world at
4.3 fps, the opening cutscene lit and finishing, and 5.6 to 10 minute runs
without a GPU fault — all things we do not have yet. Its notes are the most
useful single document we have read on this project:

- Every host copy of title memory is a `WRITE_BACK`/`L0` custom heap, which
  vkd3d-proton turns into GTT (system RAM over PCIe): 8.7 GiB GTT and 10.5 GiB
  VRAM in their world run. Their frame is ~9,000 commands of a few
  microseconds each, memory-latency bound, not shader bound.
- The frame is 12 batches, prepare/execute/wait/copy-back, GPU busy 37 %;
  copies move ~880 MB per frame for ~65 MB the title wrote (13.6x).
- `VICTORY_LAZY_VIEWS` is on by default under Wine; `VICTORY_LIST_FREE_FRAMES`
  fixed a ~1 GB/minute leak; `VICTORY_GI_STANDIN` / `VICTORY_RT_STANDIN`
  replace GI gathers and unneeded RT passes with a constant.

Ported from it:

1. **`LOOP_LIMIT` 2^16, not 2^20** (`2e40053`). Their measurement: a BVH
   parent walk in `XboxBvhBuilder.dll` whose lanes never reach a root ran
   1.1 to 1.7 s per dispatch at 2^20, and the driver reset the device past
   its 2 s. `crates/victory-shader/src/emit/lower.rs` now caps at 2^16 with
   their reasoning in the comment.
2. **`VICTORY_SKIP_MOVIES=1`** (`91318e2`, diagnostics builds). The title's
   own Bink library still opens the video; a stand-in for its
   `BinkOpenWithOptions` sets the opened video's frame count to one. New
   `crates/victory-hle/src/modules/bink.rs`, hooked at the top of
   `registry::lookup`. Verified in a run: four videos opened and cut.
3. **Its notes** (the facts above) rather than code.

Not ported, with reasons:

| CGBJ work | Why not |
| --- | --- |
| Whole tree (458 commits) | Conflicts in every file; base is 461 commits behind ours. Same conclusion as Trexies' fork. |
| `VICTORY_BINK_PARK` (`c52e76c`, 378 lines) | Rests the Bink library's polling threads. Plausible but large, and our runs die before video playback shows up as a cost. |
| `VICTORY_VRAM` placement (`229f2d7`) | Their design notes say it needs no per-view work at preparing; ours has a different copy design. Not a drop-in. |
| GI/RT stand-ins | Our default is `VKD3D_CONFIG=nodxr`; no DXR passes exist to stand in for. |

Already ours, checked before porting: dropping a draw or dispatch whose table
gets no dynamic descriptor slots (`33eaf1c` — our `draw.rs` `bind` returns
`bool`, `DROPPED` counts it); the heap-texture walk lock (`693d198`) — our
tree has no such walk.

### What the runs now say about the pre-cutscene stop

Seven runs, 75 to 240 s, diagnostics build, `--console series-x`,
`VICTORY_MEM_STATS=1`, keys every 5 s from 10 s (`VICTORY_KEYS`). Numbers
from the host (`nvidia-smi`, 2 s samples):

| Run | What changed | VRAM peak | Ends |
| --- | --- | --- | --- |
| C | before this session | 7,570 MiB | exit 3 at frame 2279, no report |
| E | loop cap not yet | 7,851 MiB | survived 120 s (never reached the cutscene) |
| F | dense keys | 7,851 MiB | exit 3, no report |
| G | `LOOP_LIMIT` 2^16 | — | exit 3 |
| H | + `VICTORY_SKIP_MOVIES=1` | — | exit 3 (videos cut, same point) |
| I | warm shader cache | — | exit 3 |
| J | cold shader cache | — | exit 3 |

So: **the loop cap did not change the outcome, and the videos are not what
ends the run.** What is now known:

- It is not an exception: `victory-loader`'s unhandled-exception filter and
  panic hook write `crashes.log`, and the only report there (`write 0x0`,
  title code at `+0x2215c35`, `kernel32` thread entry) is from the 13:40 run.
  The recent runs leave none.
- It is not `ExitProcess`, `TerminateProcess` or the CRT's `exit`: all three
  are logged through HLE now (the first two were added this session), and
  none fires. The title's entry returns 3 instead — `apps/victory/src/main.rs`
  exits with the code the entry returned, which is why the shell sees 3.
- It is not video: with every video cut to one frame the run ends at the same
  point.
- At that point the host refuses two compute pipelines for requiring wave 64
  (`Required WaveSize range [64, 64]`, `[32, 32]` supported), and their
  dispatches are dropped with `a dispatch without a host pipeline dropped`.
  The wave-reason line added to `lower.rs` did not print even with a cold
  shader cache, so those two programs get their `WaveSize` from a path other
  than the compute-window decision; that is the next thing to find.
- VRAM reaches 7,851 of 8,192 MiB (96 %) before the stop, and RSS peaked at
  16.2 GB in run C. Neither is proven to be the cause.

Next, in order: find where those two programs get wave 64 (finish the wave
diagnostic, then either port soldsawn's paired form or relax the requirement
behind a `VICTORY_*` switch); if that is not it, dump the title's own state
at the stop with `VICTORY_DUMPS`-style tables on the last frame.

## JMAN730 and the wave-size question (2026-11-25, second pass)

`JMAN730/victory` is reachable and large: **113 branches**, `main` 780 commits
ahead of `ffe310e`. Its `docs/linux-proton.md` is a full Linux guide (Nix
shell, `cargo xwin`, umu-run, Proton) and `docs/arch-proton-rendering.md` is a
**CachyOS + RTX 4080** report that describes our failure exactly:

> During the transition to the world, two compute pipelines were refused. The
> Linux kernel then logged NVIDIA Xid 13 (GPU MMU fault) for the title
> process, and VIctory recorded a null write (`0xc0000005`) in `crashes.log`.

Our 13:40 crash report is the same null write, and the same two refusals
appear in every run since. Their `docs/research/wave-size-rules.md` (215
lines, primary sources) settles the mechanism: `[WaveSize(N)]` is entry
property tag 11 in DXIL and `MinimumExpectedWaveLaneCount`/
`MaximumExpectedWaveLaneCount` in `PSV0`; the **runtime** rejects a pipeline
state whose declared size does not satisfy `WaveLaneCountMin <= N <=
WaveLaneCountMax`; NVIDIA reports 32/32 in all 509 community reports, AMD
RDNA 32/64, so a `WaveSize(64)` compute program can only ever load on AMD.
That is not a driver bug to work around at the pipeline call — the program has
to stop declaring 64, which means running its 64 lanes on 32-lane hardware.

Their branches for that (`fix/wave64-lane-mask-pair`, 332 lines in 10 files;
`codex/wave64-indexed-lane-reads`, 286 lines; `shaders/whole-wave-sections`)
are focused but each sits on their own rewritten `lower.rs` (2,252 lines
changed from our base) and none applies to ours: `git apply --3way` conflicts
in every one. soldsawn's `26600c6` is the same idea at full size (`lower.rs`
1,863 lines changed plus 6 new modules and 1,164 lines of new tests).

**Conclusion: paired wave64 is a project, not a port.** It needs the
translator's lane model changed (two console lanes per host thread, lane
masks kept as a pair, `v_cndmask`/`vcc_hi`/DPP handled together), its tests,
and a cache-key bump. Doing it by hand in this tree without the test suite is
the kind of rewrite the project's rules forbid. It is the single highest-value
piece of work left, and it should be its own phase with CGBJ's/JMAN's tests as
the reference.

### Abort visibility (ported, and what it proved)

`apps/victory/src/abort.rs` now installs a panic hook that writes the payload,
location, thread and `Backtrace::force_capture()` to `VICTORY_LOG_FILE` with
`flush()` + `sync_all()`, and a CRT `SIGABRT` handler that does the same and
exits 3 (the status the CRT uses). `victory-core`'s log writer now flushes
inside every `write`, so no line is lost when a run ends without unwinding.

The one 120 s run after that still ended at **exit 3 with no panic, no
`SIGABRT`, no `crashes.log` and no line from our HLE exit paths**. Since a
statically linked CRT in a title DLL keeps its own `signal` table, an `abort`
inside such a DLL is still invisible to us — that, or the driver runtime
ending the process after the GPU fault, is what is left. Neither is provable
from inside the PE; the next step is to correlate a run with
`journalctl -k -g 'NVRM: Xid'` (this machine's journal had no Xid line for our
runs, unlike JMAN's report) and with `winedbg`/`WINEDEBUG=+seh` around the
last frame.

## Part 1: `datingesp-hash/victory-proton` and Wine's view list (2026-11-25)

The repository is **three files** (`README.md`, the `victory-proton` launcher,
`wine/wineserver-view-tree.patch`, 143 lines), cloned to
`/tmp/victory-proton-check` and read in full. It contains no VIctory code.

### What the patch fixes

Wine's `server/mapping.c` keeps each process's mapped views in
`process->views`, a `struct list`, and finds them by walking it:

- `find_mapped_view(process, base)` — every `map`/`unmap` view lookup;
- `find_mapped_addr(process, addr)` — every address lookup;
- `is_valid_view_addr(...)` — an overlap test that scanned until it found a
  view past the range.

A title that aliases GPU memory one page at a time reaches tens of thousands
of views, so each of those calls becomes O(views): the README measures
0.5–1 ms per map/unmap with 20,000+ views, wineserver on most of a core, and
texture uploads stalling for seconds a frame.

The patch adds **an index beside the list**, not a replacement: a
`struct rb_tree view_tree` from `wine/rbtree.h` keyed by `(process, base)`,
plus `find_view_at_or_below` (predecessor search by address) and
`compare_view`. `find_mapped_view` becomes `rb_get`; `find_mapped_addr` a
predecessor plus a range test; `is_valid_view_addr` a single predecessor test
("views do not overlap each other, so only the last one starting below the
end of the range can reach into it"); `free_memory_view` removes the entry.
The list stays because its order is meaningful (exe first, then load order).

The safety valve matters: if `rb_put` ever finds two views of one process
sharing a base, `view_tree_unreliable` is set once and every path walks the
list exactly as before. The patch can make lookups faster, never differently
correct.

Their measurements, one machine and one scene:

| | stock wineserver | patched |
|---|---|---|
| map / unmap | 450–900 / 300–500 µs | 9–12 / 10–15 µs |
| texture refreshes per frame | 0.2–3 s | 30–57 ms |
| wineserver CPU | 57–91 % | 3 % |

### Is our wineserver patched? No — checked, not assumed

`Proton-CachyOS Latest` (`cachyos-11.0-20261015-slr`, `wine-11.0 (CachyOS)`)
ships `files/bin/wineserver` **not stripped**, so a patched build would show
the new statics. `nm` lists only `rb_remove` (Wine's own rbtree helper) and
nothing matching `view_tree` / `find_view_at_or_below` / `compare_view`:
the server walks the list. Wine upstream still keeps `process->views` as a
list, so any Proton without this out-of-tree patch is unpatched.

Getting it is not a port: their launcher fetches the sources of the *exact*
Proton release, applies that release's own Wine patches, then this one, and
builds `wineserver` only, because the server must match its wine. That is a
Wine build (the patch is Wine's, LGPL-2.1+), not something this repository
should carry. It is also the only part of the change that can help us: the
per-call cost is server-side.

### Our side already coalesces the queries

The in-process half is not a to-do; it is done, with these call sites:

- `crates/victory-gpu/src/watch.rs:396-470` (`protect`): pages are gathered
  into **runs of consecutive pages** and each run costs one `VirtualProtect`
  (`set(run[0], run[len-1] + 1)`), falling back to one call per page only
  when the run fails.
- `watch.rs:231-260` (`runtime_memory`): one `GetWriteWatch` per tracked
  allocation, and a `VirtualQuery` only when that says nothing is watched.
- `watch.rs:406-430`, `632-641`: `VirtualQuery` per page survives only on
  the paths that meet an unguardable or already-unmapped page — the rare
  case, not per-copy steady state.

So there is no redundant query to cache away: what is left is the server's
cost per call, which the wineserver patch is about. `VICTORY_MEM_STATS`
already reports the copy/guard timings that would show it
(`crates/victory-gpu/src/copystat.rs`).

### Version and environment recommendations, and what was applied

- **`VKD3D_CONFIG=descriptor_heap`** (their README, item 3): "Without it,
  vkd3d-proton caps shader-visible descriptor heaps at 1,000,000 entries.
  Games that ask for more fault the GPU within a minute." That is exactly
  the shape of our log — the title asks for 2,097,153 slots, its highest
  live slot is 1,245,183, and the host heap is capped at 1,000,000 — and
  the installed `files/lib/wine/vkd3d-proton/x86_64-windows/d3d12core.dll`
  does know the option (its strings contain `descriptor_heap`). Diagnoses
  matching symptoms is not proof it is ours, so it is **not a new default**:
  the launcher already lets an inherited `VKD3D_CONFIG` win over its
  `nodxr`, so `VKD3D_CONFIG=nodxr,descriptor_heap` is a one-variable
  experiment. Documented in the script's environment block.
- **Proton version.** They require GE-Proton 11-13+, listing two symptoms
  we have: "Older dxil-spirv generates invalid code for the first
  mesh-shader pipeline, and VIctory exits with code 3", and in
  troubleshooting "Exit code 3 at the first 3D scene → GE-Proton is older
  than 11-13". Installed here: GE-Proton 11-12, Proton-CachyOS
  `cachyos-11.0-20261015`, Proton-Wineland 11.0, UMU-Proton 11.0-2e. None
  is 11-13. **This is now the cheapest experiment we have for the exit-3
  stop**, and it needs no build.
- **No new override variable.** `PROTONPATH` (read by Proton and umu-run)
  and `--runner proton:/path` already choose the build, and plain Wine is
  the last fallback; adding `VKD3D_PROTON_DIR`/`CUSTOM_PROTON_DIR` would be
  a second way to say the same thing.

## Part 2: paired wave64 — measured, specified, not faked

The two refusals are compute. vkd3d-proton's
`d3d12_device_validate_shader_meta` compares the `PSV0`
`WaveLaneCountMin..Max` pair, which `crates/victory-shader/src/emit/container.rs:199`
writes from `wave_size`, which only the compute branch sets
(`emit/lower.rs:499-556`): `console_lanes || one_wave && lds_dwords > 0`.
Nothing else in the crate can declare 64 — the DXIL entry tag 11
(`emit/shader.rs:837`) and `PSV0` come from the same field.

That gives exactly two possible reasons, and they need different work:

- `console_lanes`: the program reads other lanes (ballots, DPP, permutes,
  `v_mbcnt`, lane reads, readlane/writelane, lane masks used as data). Two
  32-lane halves cannot compute a 64-bit ballot without shared memory and a
  barrier.
- `one_wave && lds_dwords > 0`: the whole group is one console wave that
  shares LDS with no barrier, because the console compiler knew all 64 lanes
  were resident. Splitting it into two host waves makes each half's LDS
  private and silently loses that sharing — a "fix" that changes results
  instead of crashing, which is worse.

Neither is reachable by changing metadata: declaring `[32, 32]` on either
makes the pipeline load and the program wrong. The honest fix is the paired
lane model (two console lanes per host lane, lane masks kept as a pair,
DPP within a half, cross-half operations through memory), i.e. what
`soldsawn`'s `26600c6` (1,863 lines in `lower.rs`, six new modules, 1,164
lines of tests) and JMAN's `fix/wave64-lane-mask-pair` (332 lines in 10
files) do on a `lower.rs` that differs from ours by 2,252 lines. Every
attempt to apply either (`git apply --3way`) conflicts. Writing that by hand
here, with one 120 s run as the only verification, is precisely the blind
rewrite this project's rules forbid; it stays a phase of its own, and the
branches plus their tests are the spec.

This session ran no subagent or `opencode` worker: none is available to the
agent in this environment, so every check below was done directly.

**What was done instead:** the wave-requirement line existed but was behind
`cfg(feature = "diagnostics")` and did not appear in the run that produced
the refusals. It is now behind `VICTORY_LOG_WAVE=1` in every build
(`emit/lower.rs:541-560`) and prints the wave size, the thread-group size
and which of the two reasons applied — the one fact the paired-lane design
needs. The launcher's help and environment notes describe it, and
`descriptor_heap`.

### The one bounded run (120 s)

`VICTORY_LOG_WAVE=1 VICTORY_MEM_STATS=1 VICTORY_KEYS=… play-linux.sh
--console series-x --debug`, killed by `timeout` at 120 s (status 124, so
**no exit 3 in this window**): world streaming, 2,617 host textures at the
6,974 MB budget, RSS 13,317 MB (peak 13,318), 4.9 fps at 205 ms/frame with
142 ms in preparation and 14 ms on the GPU. No refusal and no wave line —
the two compute pipelines are created later than this run got, so their
reason is still unrecorded. Honest limitation: the run answers "did it
survive 120 s" (yes, this time) and nothing about the transition.

## Part 3: the cutscene, the four changes, and the run that went white

### Baseline (the run that got into the cutscene)

`victory-first-cutscene.log`, GE-Proton 11-14 with
`VKD3D_CONFIG=nodxr,descriptor_heap`: past the exit code 3, world loaded,
**146 draws/frame**, and the opening cutscene reached.

| What | Before |
|---|---|
| Frame | 1,476.6 ms (0.7 fps) |
| Preparing, host side | 1,028.5 ms |
| Copies of title memory | 1,768.4 ms for 159.9 MB |
| Copy-back of GPU writes | 119.3 ms |
| On the GPU | 35.2 ms |
| RSS | peak 16,020 MB of 15,910 MB |
| Host textures | 6,979 MB (budget 6,656 MB) |
| Descriptor heap | `title slots past the host heap slots=4194305 highest=1245183 count=934464` |

That last line is arithmetic, not a guess: `count` is the host heap's title
slots, `PORTABLE_VIEWS - MIN_DYNAMIC` = 1,000,000 − 65,536 = **934,464**
(`descriptor/host.rs:88,98,169`), so every live slot from 934,464 up to
1,245,183 was never mirrored.

### What changed

1. **Launcher defaults** (`scripts/play-linux.sh`): `VKD3D_CONFIG` defaults to
   `nodxr,descriptor_heap` (inherited values still win), and `pick_proton`
   prefers **GE-Proton 11-14**, then any GE-Proton 11-13 or newer, then
   CachyOS. `PROTONPATH` and `--runner` still override everything.
2. **The 1M host heap cap is lifted when vkd3d-proton's descriptor-heap path
   is on** (`crates/victory-gpu/src/descriptor/host.rs`): a new
   `vkd3d_descriptor_heap()` reads `VKD3D_CONFIG`; when it is set, a heap the
   host refuses falls back to the **title's own slot count** (dynamic slots
   0, and they say so when asked) instead of 1,000,000. Without the flag the
   old cap and `MIN_DYNAMIC` room apply unchanged. Cost of the full heap:
   ~33 MB of `made`, ~70 MB of `kept`, ~50 MB of stride/mark upload buffers,
   and the shader-visible heap itself (4,194,305 × 32 B); against that, the
   texture budget below gives back 1,024 MB.
3. **Texture budget 6,656 → 5,632 MB** (`crates/victory-gpu/src/resource.rs`):
   8 GB of VRAM's usable share less what a 16 GB machine has to keep for the
   title, which is what the 16,020 MB peak above says was missing.
4. **View-tree wineserver**: `wineserver-view-tree.patch` (datingesp-hash)
   applied to **GE's own wine source** — ValveSoftware/wine `a47c73f` plus
   the GE-Proton11-14 tag's full patch series, so `make_requests` produced
   **protocol 938**, the number the installed client sends (the tag's bare
   submodule pin gives 931, and that server was refused: `version mismatch
   931/938`). Built as a 64-bit `wineserver` (`nm` shows `view_tree`,
   `view_tree_unreliable`), installed in a hardlink copy of the whole Proton
   tree at `~/.local/share/victory/ge-proton11-14-viewtree` so ntdll's
   `realpath`-based `bin_dir` lands there; a wrapper at
   `files/bin/wineserver` proved that ntdll execs this binary, and
   `wine cmd /c exit` under the tree succeeds. Method: the release's patch
   script (`patches/protonprep-valve-staging.sh`, wine section only) with
   `apply_patch`/`apply_all_in_dir` defined; every patch applied, 0 failures.

### The one bounded run (150 s) — white window

`VICTORY_MEM_STATS=1 VICTORY_KEYS=… play-linux.sh --exe game_scarlett_master.exe
--console series-x --debug` (which now picks the view-tree runner): **exit 58
after ~40 s** and a **white window**. vkd3d-proton never got a device:

```
warn: vkd3d_remove_extension: Removing VK_NVX_binary_import extension from the array.
warn: vkd3d_remove_extension: Removing VK_NVX_image_view_handle extension from the array.
warn: vkd3d_create_vk_device: Disabled extensions that can cause Vulkan device creation to fail, retrying.
err:  vkd3d_create_vk_device: Failed to create Vulkan device, vr -3.
```

The runtime kept presenting frames with `drawn=0` (white). DXVK had found the
card (`NVIDIA GeForce RTX 3070 (NVIDIA 620.73.4)`), so it is the D3D12 device
creation that failed, before any heap, pipeline or title memory.

The only difference from the proven configuration was the runner (the tree is
byte-identical to stock GE-Proton 11-14 apart from `files/bin/wineserver`), so
**the view-tree runner is no longer the default**; `pick_proton` prefers the
stock GE-Proton 11-14 again and the patched tree is opt-in with
`--runner proton:$HOME/.local/share/victory/ge-proton11-14-viewtree` (a
`README.viewtree` in that tree says the same). Which of the two is at fault is
**UNVERIFIED**: the patch, or the hand-built server (its objects were compiled
by hand because the prepared tree's `Makefile` cannot be regenerated there —
`makedep` fails on the tree's missing wineopenxr sources — so `config.h` came
from a configure that exited 1 while writing the Makefile).

### Not ported, and why

- **`VICTORY_LAZY_VIEWS`** (CGBJ default on under Wine) needs
  `victory_gpu::lazy` — 212 lines in CGBJ, `lazy::table_mut()` at ~10 xmem
  sites (map, unmap, protect, query, `alias_of`) plus the guards in
  `watch`/`queue` that keep CPU writes coherent. This tree has no such module,
  and the view-tree wineserver attacks the same cost (each host view makes
  every map/unmap slower). It is a phase of its own, testable only by A/B.
- **`VICTORY_LIST_FREE_FRAMES`** (CGBJ closes a leak of ~1 GB/min with it):
  that leak lived in CGBJ's *loose buffer windows* (`loose.rs`), which this
  tree does not have; our `HostList` holds `Deferred` steps and a `states` map
  that `reset()` already clears, and a 600-frame idle window cannot elapse in
  a 150 s run at under 1 fps, so it could be neither ported nor measured here.
- **Cutscene lighting / barrier fixes** in CGBJ's `docs/PROTON-STATUS.md` are
  stand-ins (`VICTORY_GI_STANDIN=0.5`, `VICTORY_RT_STANDIN=1`, a dropped
  particle pass) for RADV; the picture here already reaches the cutscene and
  those knobs change what is rendered, so they stay behind their own flags for
  a rendering session with screenshots.

### After numbers

Not measured. The single allowed run failed before the title ran, so the
texture budget, the lifted heap cap and the launcher defaults have **no
after-measurement** yet. The next run answers all three in one line each:
`host textures: N (M MB …)` for the budget, `host view heap capped` *absent*
plus no `title slots past the host heap` line for the cap, and the frame line
for preparing/copies.
