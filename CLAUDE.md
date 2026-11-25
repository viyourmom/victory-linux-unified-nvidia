# CLAUDE.md: VIctory Linux port (unified fork)

Persistent rules for the local agent. Read this at the start of every session.

## Project

Goal: make a VIctory-based compatibility layer (runs an Xbox Series build natively from user-supplied files) run well on Linux via Proton/Wine + vkd3d-proton, with a Rust codebase licensed GPL-3.0.

Sources (add as git remotes in ONE repo; do not keep separate copies):

- https://github.com/Marvisak/VIctory (upstream)
- https://github.com/WillyboPeep/victory-all-forks
- https://github.com/Zettrox/ztrx

Optional read-only references. Before using anything from them, confirm the repo exists and check its licence is GPL-3.0 compatible:

- Belobug/VIctory-Belobug-AMD
- brcly/TuxBox

## Test machine

- OS: CachyOS (Arch-based), Proton-CachyOS / Wine available
- GPU: NVIDIA RTX 3070, 8 GB VRAM, proprietary driver (mesh shaders and DXR supported)
- CPU: Ryzen 7 3700X (AVX2 OK)
- RAM: 16 GB DDR4 (the main constraint; the title reportedly needs ~24 GB)
- AMD GPU support cannot be tested here. Treat it as optional and last.

### Where this stands (2026-11-25)

- The combination that reaches the opening cutscene here: **GE-Proton 11-14**
  (the launcher's default runner) with `VKD3D_CONFIG=nodxr,descriptor_heap`
  (also the default now). It gets past the exit code 3 older Protons stop at,
  loads the world and plays the cutscene: 146 draws/frame, 35.2 ms on the
  GPU. CachyOS 11.0 did not get there.
- Before numbers, from that run (baseline for the memory work): RSS peak
  **16,020 MB** on 15,910 MB of RAM; host textures 6,979 MB; frame 1,476.6 ms
  with **1,028.5 ms preparing**, of which copies of title memory took 1,768
  ms for 159.9 MB (times overlap across threads), and 0.7 fps.
- After numbers, measured on 2026-11-25 after a cold reboot and a clean
  prefix: the Vulkan device is created again (no `vr -3`), the menu runs at 30
  fps / 12 draws with host textures 4,518 MB of the 5,632 MB budget and RSS
  3.6 GB, and a 90 s run reaches frame 2048+ (11,186 draws) and the opening
  cutscene **with sound**. The picture is **black** and the run still ends
  silently (~137 s). See PROGRESS.md, "Cold reboot".
- `descriptor_heap` does **not** lift vkd3d-proton's 1,000,000 cap on this
  stack: with it on, a heap of 1,245,184 slots is handed out that the host
  says it cannot make. `VKD3D_CONFIG=nodxr` alone gives the proven clamp
  (934,464 title slots) and is the configuration to debug rendering with.
- Host texture budget default is now **5,632 MB** (was 6,656), so host
  textures plus the title's own memory fit under 13.5 GB on this 16 GB box.
- A view-tree wineserver (`~/.local/share/victory/ge-proton11-14-viewtree`)
  builds, speaks protocol 938 and is reachable with `--runner proton:...`, but
  is **not** the default: the run under it failed at device creation.

## Target stack (what "works" means for late-stage work)

- **vkd3d-proton is the only D3D12 host.** Vulkan 1.3+, portable SPIR-V lowering (no wave-width or AMD-only intrinsic assumptions), `VK_KHR_timeline_semaphore` for fences, `VK_EXT_memory_budget` for the VRAM budget. Anything that only works on one vendor, or only on Windows' own D3D12 runtime, is a bug.
- **TuxBox's shape is the model** (brcly/TuxBox): a thin Xbox-delta layer over native Proton/Wine - kernel NTSYNC for sync objects, vkd3d-proton for D3D12, Steam Input for pads - instead of re-implementing what the stack already provides. New work goes in the HLE delta only.
- **Never depend on services the layer does not have** (DRED, PIX, telemetry, Xbox Live): detect and skip.
- **Host limits are real and may clamp instead of fail.** vkd3d-proton caps a `CBV_SRV_UAV` heap at 1,000,000 descriptors and makes a smaller heap rather than returning an error (seen in the first Linux boot). Read back what was made (`GetDesc`) and log a mismatch; never trust the requested size.
- **A Windows PE's stdio is not the launching terminal** under `proton run`: a run whose log matters writes it with `VICTORY_LOG_FILE`, because its stderr never reaches the shell.

## Runtime invariants (proved in Phase 1; do not re-litigate)

1. **`--console series-x` is the active boot and rendering target.** It reaches the
   legal screens and active rendering (2048 frames at 30 fps, 11 draws/frame,
   1519 host textures / 2603 MB). `--console series-s` stalls before the first
   present and is not a test target; do not spend cycles on it.
2. **The host descriptor heap is capped at `1,000,000` slots on NVIDIA + vkd3d-proton**
   (`934,464` usable title slots after `65,536` internal ones). vkd3d-proton
   *succeeds* while making a smaller heap than asked for, so read
   `GetDesc().NumDescriptors` back and never trust the request.
   - Never hand unmapped 21-bit (`2,097,152`) virtual indices straight to
     D3D12/vkd3d-proton: a title index past the made heap must be clamped or
     remapped, not passed through to a shader root view (which has no bounds).
   - **Never log per slot inside a descriptor write/copy loop.** The first
     Linux run walked 310,720 consecutive slots past the heap and wrote
     621,440 log lines (65 MB, synchronously, under a writer mutex) during
     loading. Use atomic counters plus a rate-limited summary (one line per
     doubling, highest index reached).
3. **16 GB RAM / 8 GB VRAM survival discipline.** The kernel has already
   logged `NVRM: Out of memory [NV_ERR_NO_MEMORY]` for this title. Free
   transient shader IR / DXIL blobs once a PSO exists (reload from the disk
   cache), bound and recycle staging/upload buffers and descriptor slots
   deterministically on GPU fence completion, and respect the real budget
   (`VK_EXT_memory_budget` / `IDXGIAdapter3::QueryVideoMemoryInfo`) while the
   world streams. `VICTORY_MEM_STATS=1` (default off) reports live RSS, swap,
   VRAM budget/usage and pool sizes.
4. **Universal Vulkan via vkd3d-proton, TuxBox's NTSYNC shape.** Vulkan 1.3+,
   portable SPIR-V (no AMD-only ISA, no Wave64 assumptions),
   `VK_KHR_timeline_semaphore` for fences, `VKD3D_CONFIG=nodxr` by default (do
   not enable the experimental `VKD3D_CONFIG=descriptor_heap` on NVIDIA),
   `PROTON_USE_NTSYNC=1` with native NT sync primitives on `/dev/ntsync` (no
   user-space busy-wait spinlocks; sharded or lock-free page-guard tracking),
   case-insensitive path lookup caching in `modules::files`, and clean
   Wine/Proton stubs (`ntdll!wine_get_version`) for DRED, PIX and telemetry.
5. **Evidence loop, not guesses.** Each cycle is: edit -> `cargo check` -> build
   the release PE -> `timeout`-bounded run with `--console series-x` -> read
   `~/.cache/victory/victory.log` tail, `$XDG_DATA_HOME/victory/data/crashes.log`
   and `journalctl -k` (Xid / NVRM / PAT). At most 6 cycles per session; a
   cycle that changes nothing measurable is a wasted one. Rendering quality is
   still judged by the user from `VICTORY_CAPTURE` frames, never by the agent.

## Hard rules

1. **No game files, ever.** Never read, copy, hash, list, or commit anything from the user's game folder. Game paths live only in an untracked `victory.toml` (keep it in `.gitignore`).
2. **Keep GPL-3.0** and upstream attribution (`ALL-FORKS.md`). Do not strip credits.
3. **Strict phases.** After each phase: `cargo check --workspace` and `cargo test --workspace` pass, make ONE clean git commit, then **STOP and wait for my approval**.
4. **No speculative cross-crate rewrites.** Small, reviewable changes, each with a stated and checkable reason. Mark unverified guesses as "UNVERIFIED".
5. **Experimental behaviour goes behind `VICTORY_*` env flags, default off.** Safe defaults only.
6. **Measure before and after.** Record a baseline (frame time, RSS, swap, VRAM, shader-cache warm-up time) before optimizing, and report the same numbers after. Do not claim a reduction you did not measure; say "structural" if only reasoned.
7. **Rendering can't be judged by the agent.** Use `VICTORY_CAPTURE` frames and ask me to describe what I see.
8. **Vendor honesty.** Anything NVIDIA/AMD-specific must be identified and guarded, not silently assumed.

## Phase plan (one phase per session)

### Phase 0: Audit (read-only, no code edits) -> `AUDIT.md`

1. Per-crate diff of all-forks vs ztrx (shader recompiler, D3D12 backend, HLE/memory, submission, launchers), using `git merge-base` against upstream.
2. Why ztrx is stable on 8 GB: which settings/commits, with hashes.
3. Fixes unique to all-forks, and unique to ztrx.
4. Vendor-specific (NVIDIA/AMD) or Windows-only API usage that matters under Wine/vkd3d-proton, with file paths.
5. Memory map: where the ~24 GB goes (title memory, mirrors, staging, descriptors, shader/PSO data) with file/line references.
6. Which crates build and test on `x86_64-unknown-linux-gnu` today, and whether the Windows target cross-compiles (`x86_64-pc-windows-gnu` vs `cargo-xwin`). Actually run it.
7. Recommended merge base and an ordered plan.

Then stop.

### Phase 1: Linux/Proton baseline

- Cross-build the Windows PE from Linux; add `scripts/build-linux.sh`.
- Check the Windows binary boots under Proton-CachyOS + vkd3d-proton. Record exactly what breaks (in-process PE loader, fixed-address memory, write-watch/page queries, DRED/telemetry calls, etc.).
- Add `scripts/play-linux.sh`: detects Proton/Wine, sets `VKD3D_CONFIG` and related env vars, puts caches under `$XDG_CACHE_HOME` and saves under `$XDG_DATA_HOME`, supports `--console series-x|series-s`.
- Record the baseline numbers.

### Phase 2: Memory (RAM first, then VRAM)

- Lazy reserve + on-demand commit where safe.
- Remove duplicate CPU/GPU mirror pages; bound and recycle staging buffers after fence completion.
- Fence-tracked descriptor heap recycling; make sure released allocations free host resources.
- Free shader IR / DXIL blobs after PSO creation (reload from the disk cache when needed).
- Respect the real VRAM budget (`IDXGIAdapter3::QueryVideoMemoryInfo` or equivalent).
- Verify `--console series-s` works end to end.
- Add `VICTORY_MEM_STATS=1` (live RSS, swap/commit, VRAM budget/usage, staging pool size).
- Recommend zram / NVMe swap config for the 16 GB machine.

### Phase 3: Stability and rendering

- Merge verified fixes from ztrx and all-forks.
- Black shadows: optional ambient fallback behind `VICTORY_AMBIENT_FALLBACK=1` when RT lighting is inactive. Check tone-map/exposure bindings for bright-scene blowouts.
- Blocky artifacts: audit descriptor mirroring, sub-element view copies, BCPack/tiled decoding, indirect draw and meshlet culling bounds.
- Anti-TDR: chunk heavy `DispatchMesh`/compute submissions with safe synchronization.
- Shader/PSO disk cache with a pre-warm CLI so later runs skip translation hitches.
- Linux/Wine: case-insensitive path lookup cache (`modules::files`), detect Wine at runtime and skip unsupported calls, XInput via Steam Input with a keyboard fallback.

### Phase 4: Performance

- Evaluate `VICTORY_RELAY`, `VICTORY_LATE_WAIT`, `VICTORY_WIDE_BACK`, `VICTORY_PIPELINE_WAIT_MS` and similar on the test machine; only change defaults with measured evidence.

### Phase 5 (optional, only if testable): AMD

- Wave64 vs Wave32 correctness, strict barrier/state compliance, AMD pipeline-build guards (`VICTORY_AMD_NOOPT`), clean capability-check failures on unsupported cards.

### Final: Verification and docs

- `cargo fmt --check`, `cargo clippy --workspace`, `cargo test --workspace`, `cargo build --release -p victory`.
- `README.md`: Windows and Linux build/run instructions and all `VICTORY_*` flags.
- `CHANGELOG-UNIFIED.md`: every fix, measured (or labelled structural) memory/VRAM changes, remaining blockers.

## Working style

- Plan first, then act. For each phase, state the plan before editing code.
- Prefer findings with file and line references over general statements.
- When blocked or uncertain, say so and ask rather than guessing.
- End each phase with: what changed, what was measured, what is still unverified, and what you propose next.
