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
