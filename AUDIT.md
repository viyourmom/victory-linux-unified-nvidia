# AUDIT — Phase 0 (read-only)

Date: 2026-11-25. Machine: CachyOS, Ryzen 7 3700X, 16 GB DDR4, RTX 3070 8 GB
(proprietary driver), rustc 1.98.1, cargo-xwin 0.24.1, wine present,
Proton-CachyOS / GE-Proton11-12 / UMU-Proton-11.0 installed.

Scope: **no source file was edited in this phase.** The only changes are this
file, `.gitignore`, and a copied `CLAUDE.md`. No path under the game folder was
read, listed, hashed or copied. Nothing was executed against the title: every
memory figure below is *structural* (read off the code) unless it is quoted
from a fork's own recorded measurement, and those are marked as such.

---

## 0. Repository setup

One repo, `victory-unified/`, `git init`, three remotes, all fetched (no
separate copies of other repos):

```
upstream  https://github.com/Marvisak/VIctory
allforks  https://github.com/WillyboPeep/victory-all-forks
ztrx      https://github.com/Zettrox/ztrx
```

Heads at fetch time:

| remote | commit | date | subject |
|---|---|---|---|
| `upstream/main` | `940d32f69b22` | 2026-11-25 | GPU: a marked page's copy-back does not save the page for its own copy |
| `allforks/main` | `ef7f036a1ffa` | 2026-11-24 | Credits first: a test merge of other people's work, and exactly what was added here |
| `ztrx/main` | `90b529f878a4` | 2026-11-25 | ztrx: own README and a launcher for normal play |

Total commits in each history: upstream 532, allforks 471, ztrx 226.

### Merge bases (`git merge-base`)

| pair | merge base | date / subject |
|---|---|---|
| upstream ↔ allforks | `ffe310eb2098e52169f4c44db5ffdabf43a72622` | 2026-11-24, "Shaders: the console's waterfall loop over a first-lane table offset" |
| upstream ↔ ztrx | `ffe310eb2098e52169f4c44db5ffdabf43a72622` | same |
| allforks ↔ ztrx | `2119b0e44c53aa9648307b0c5c73590290305b1f` | 2026-11-24, "Put the parked lane-mask change (#11) back" |

Both forks branch from the same upstream commit `ffe310eb`. `2119b0e` is
*later* than that and is an ancestor of both forks (`git merge-base
--is-ancestor 2119b0e ztrx/main` → yes): ztrx carries it as its own 12th
commit from HEAD, and allforks merged the same fxceless commit as `2d3f43c`
("merge: sync fxceless/victory-fork (2119b0e) parked lane-masks …"). So the
two forks are not independent: they share the fxceless line.

### Divergence (`git rev-list --left-right --count A...B`, left = only in A)

| pair | only A | only B |
|---|---|---|
| upstream … allforks | 319 | 258 |
| upstream … ztrx | 319 | 13 |
| allforks … ztrx | 246 | 1 |

### Two provenance facts that shape the plan

1. **ztrx's history is squashed.** Its whole fork body arrives in one commit,
   `578d459` "victory-gta6: this fork's changes on top of VIctory main
   (ffe310e)" — that single commit is the source of ~36 k inserted lines in
   `victory-gpu` + `victory-shader`. The 12 commits after it are small fixes
   (see §2). Merging ztrx therefore means resolving one enormous, unattributed
   diff, not 246 reviewable commits.
2. **allforks' history is a real merge graph.** 20 merge commits join
   fxceless/victory-fork (`310c6eb`, `a803c87`, `c96b4f2`, PR #282),
   triippywhale/victory-fork (`371ba00`, `5493624`, `d10dc2f`), uiliannn/VItoriaBr
   (`3a9e747`, `32d7848`) and myokex/JoshuuDev AMD commits, each keeping the
   original author. `ALL-FORKS.md` states exactly what the repo added itself
   (merges, ~30 lines of glue, two PowerShell scripts).

---

## 1. Per-crate diff, both forks against the upstream merge base

`git diff --shortstat ffe310eb <fork>` per crate. Upstream's own 319 commits
are the control column.

| crate | base → allforks | base → ztrx | base → upstream (control) |
|---|---|---|---|
| `victory-core` | 3 files, +12/−2 | 1 file, +1/−1 | 2 files, +38/−1 |
| `victory-formats` | 3 files, +483/−24 | 2 files, +44/−5 | 3 files, +1025/−54 |
| `victory-game` | 6 files, +2132/−24 | 2 files, +3/−3 | 5 files, +2049/−17 |
| `victory-gpu` | 36 files, +32246/−1281 | 28 files, +21078/−804 | 37 files, +11211/−1094 |
| `victory-hle` | 25 files, +2498/−202 | 19 files, +164/−53 | 27 files, +4277/−211 |
| `victory-loader` | 10 files, +787/−54 | 6 files, +494/−1 | 7 files, +903/−83 |
| `victory-pe` | — (untouched) | — (untouched) | 3 files, +902/−25 |
| `victory-pipeline` | 2 files, +23/−27 | — (untouched) | 1 file, +87/−10 |
| `victory-shader` | 34 files, +20182/−706 | 26 files, +15401/−608 | 33 files, +16466/−556 |
| `apps` | 6 files, +883/−17 | 3 files, +135/−5 | 9 files, +1247/−81 |
| `xtask` | — (untouched) | — (untouched) | 1 file, +76 |

Reading of that table:

- **Shader recompiler** is where both forks put the most work, and it is the
  area where they diverge most from *upstream* too (+16 k upstream). allforks
  is ~4.8 k lines ahead of ztrx here.
- **D3D12 backend** (`victory-gpu`): allforks +32 k vs ztrx +21 k. Both are far
  ahead of upstream's +11 k.
- **HLE/memory**: allforks touches 25 files (+2498) — it inherited the newer
  upstream HLE work *and* the fork work; ztrx touches 19 files but only +164,
  i.e. ztrx's HLE is essentially the `ffe310eb` HLE plus the working-set
  accounting in `xmem` (§2). Upstream alone added +4277 after the merge base.
- **Loader**: ztrx's +494 is not memory work — `console_insn.rs` (+249) and
  `console_insn_decode.rs` (+233) decode the console's own CPU instructions
  (a `victory-loader/src/console_insn*` pair upstream does not have).
- **`victory-pe` and `xtask` are untouched by both forks**, while upstream
  changed `victory-pe` by +902. Neither fork contains upstream's 319 commits.

New files only in a fork:

- allforks `victory-gpu/src/`: `diagstream.rs`, `heap_marks.rs`,
  `heap_pass.rs`, `inplace.rs`, `shadow/relay_merge_simd.rs`.
- ztrx `victory-gpu/src/`: `inplace.rs`.

---

## 2. Why ztrx is claimed stable on 8 GB — what the evidence actually supports

**The claim.** `ztrx/main:README.md` (commit `90b529f`): tested on Windows 11
with an **RTX 3050, 8 GB**, 1 h 30 min+ in one session without a crash, 1–3 fps,
known problems: black shadows, overexposure, blocky artifacts. It also asks for
"several GB of free Windows commit memory (raise the paging file if
`crashes.log` reports error 1455)".

**The 13 commits since `ffe310eb`** (all of them):

```
90b529f 2026-11-25 ztrx: own README and a launcher for normal play
2119b0e 2026-11-24 Put the parked lane-mask change (#11) back
9e49b8a 2026-11-24 Take the parked lane-mask change (#11) back out for now
4e17478 2026-11-24 The game is no longer named in the tree
90228a7 2026-11-25 Shaders: restore parked lane-mask pairs a few instructions apart; relative VGPR reads keep parked lanes (#11)
3930989 2026-11-24 Fix mesh pipeline test on unsupported GPUs (#14)
1684989 2026-11-24 Shader clean-up passes; a test that needs a card skips without one
7b0f736 2026-11-24 Shader tests: recognise the software adapter from the device's own adapter
e9765a7 2026-11-24 Fix the device loss introduced by the wave64 update
004bf69 2026-11-24 Test fix for hosted runners, stencil diagnostics, and a stability warning
d279e69 2026-11-24 Make host pipeline waits configurable and prewarm pending requests (#1)
6a2d9f9 2026-11-24 Shadow and trace programs translate, lint clean, ray-tracing write-up
578d459 2026-11-24 victory-gta6: this fork's changes on top of VIctory main (ffe310e)
```

**Finding: not one of these commits is a memory or residency fix.** They are
shader-correctness (`90228a7`, `9e49b8a`, `2119b0e`, `e9765a7`), test
plumbing (`7b0f736`, `1684989`, `3930989`, `004bf69`), pipeline-wait tuning
(`d279e69`) and docs (`4e17478`, `90b529f`). So "ztrx is stable on 8 GB"
is **not** explained by a committed setting or a memory commit.

What the code says about memory in ztrx:

- The one memory-shaped feature, bare-metal "in place" title memory, is **off
  by default**: `VICTORY_INPLACE` unset → `level()` returns 0
  (`.trees/ztrx/crates/victory-gpu/src/inplace.rs:88-91`); the probe
  (`VICTORY_INPLACE_PROBE`) is likewise 0 by default. Its budget is
  `VICTORY_INPLACE_MB` = 4096 MiB (`inplace.rs:94-98`), and the doc records that
  opening an address heap **locks every page into the PC's memory**
  (`inplace.rs:15-18`), i.e. it would *raise* host memory, not lower it.
- ztrx's own log line admits the process is not inside a budget:
  `.trees/ztrx/crates/victory-hle/src/modules/xmem.rs:883-901` —
  `"used" is all the process has committed, the layer's own memory and the
  card's included (27 GB in run 60's gameplay against a limit of 13.5 GB). A
  title that budgets its streaming from these two figures believes it is far
  over its limit.`

**Most likely explanation (UNVERIFIED — I cannot run the title in Phase 0):**
on an 8 GB card ztrx does not fit either; it survives by *paging* — Windows
commit backed by a large pagefile (the README's error-1455 advice) and D3D12
residency paging of VRAM — and pays for it with 1–3 fps. That is consistent
with the 27 GB / 13.5 GB line above and with `docs/fork-ray-tracing.md`'s
statement that RT lighting does not run.

---

## 3. Fixes unique to allforks, and unique to ztrx

### allforks only

Merge sources (from `ALL-FORKS.md`, hashes as merged): fxceless/victory-fork
`310c6eb` + PR #282 + PR #613, triippywhale/victory-fork `371ba00` (the largest
share), uiliannn/VItoriaBr `3a9e747`, myokex/victory-amd `bddfb4a` + `892d259`,
JoshuuDev/victory-amd `10ea38e` (`fread`). Modules with no counterpart in
upstream or ztrx:

- `crates/victory-gpu/src/heap_pass.rs` — the per-pass sweep of the view heap's
  buffer views is change-driven instead of full. Its header records the cost it
  removed: "every buffer view of the heap (81,000 in the world) every 16
  passes", now only written/rewritten slots plus a full sweep every `FULL_EVERY`
  passes.
- `crates/victory-gpu/src/heap_marks.rs` — shaders mark the slots they store
  through when the index is computed (SM 6.6 dynamic resources), because
  declaring every unordered view is not affordable: "960 MB of them in the
  world" (`heap_marks.rs:9-12`). This is the mechanism behind the blocky-artifact
  class in `CLAUDE.md` Phase 3.
- `crates/victory-gpu/src/diagstream.rs` — diagnostics stream with a real VRAM
  budget readout (`DXGI_QUERY_VIDEO_MEMORY_INFO`, `diagstream.rs:639-650`); see
  §5, upstream has **no** `QueryVideoMemoryInfo` at all.
- `crates/victory-gpu/src/shadow.rs:278,298` — `VICTORY_CARD_WINDOWS_MB`
  (default 0): bounds how much title memory is kept resident in card-side
  windows. `ALL-FORKS.md` measures hard page-ins falling ~37,000/s → ~1,100/s
  at 4096 MiB (RTX 4090, 32 GB RAM).
- `crates/victory-gpu/src/shadow/relay_merge_simd.rs` — AVX2 compare/select for
  the relay's CPU merge (runtime-detected, scalar fallback); the doc explicitly
  claims **no measured speedup**.
- Switches with no upstream equivalent: `VICTORY_INDIRECT_WINDOW`
  (`victory-gpu/src/draw.rs:143,184`), `VICTORY_CARD_REHASH_RUNS`
  (`victory-gpu/src/host.rs:1699-1711`), `VICTORY_LATE_WAIT_LISTS`
  (`host.rs:2171-2183`), `VICTORY_LATE_WAIT_WRITES` (`host.rs:2188-2193`),
  `VICTORY_RELAY` stage 2 (`host.rs:2006-2017`).
- `zlib-rs` in the workspace (`Cargo.toml`, replacing `miniz_oxide`) — an
  allforks-only dependency choice; note the test target still references
  `miniz_oxide` (§6), a merge artifact.

### ztrx only

- `crates/victory-gpu/src/inplace.rs` (+1170 lines) — title memory opened as a
  host heap (`OpenExistingHeapFromAddress(1)` / `OpenExistingHeapFromFileMapping`)
  and placed as a buffer, so shaders touch the title's bytes with no host copy:
  no copy, no refresh, no copy-back. Off by default (§2). Its header is the most
  precise vendor/runtime note in any of the three trees (see §4).
- `crates/victory-shader/src/{bvh.rs (+696), emit/intersect.rs (+557),
  emit/rect.rs (+484), emit/own_bits.rs (+914), emit/bitcode/opt.rs (+2136),
  emit/bitcode/census.rs (+174), emit/threading.rs (+218), spill.rs (+380)}` —
  ray-tracing/BVH translation, a DXIL optimiser, own-bits analysis, register
  spilling and a threading pass. This is the "shadow and trace programs
  translate" work of `6a2d9f9`.
- `crates/victory-hle/src/modules/xmem.rs` — working-set statistics and
  remapping hooks: `victory_gpu::title_memory_section/view/remapping` calls
  (`xmem.rs:433`, `:605-606`, `:742` in the ztrx tree) and the "the title asks
  how much memory it uses" log (`xmem.rs:883-901`).
- `crates/victory-loader/src/console_insn*.rs` — console CPU instruction decode
  (no upstream equivalent).
- `scripts/play.ps1`, own `README.md` (`90b529f`).

### Present in both, but differently

- `inplace.rs` exists in both trees and is **not the same file**: allforks'
  copy sits beside a `shadow/` directory and predates ztrx's section/view census
  API. Porting one over the other is a real merge, not a copy.
- Wave64 handling: both diverged (`emit/wave.rs`, `emit/wave64_tests.rs` in
  ztrx; allforks' `structure.rs` exact-pair logic). `e9765a7` ("Fix the device
  loss introduced by the wave64 update") exists **only** in ztrx.

---

## 4. Vendor-specific and Windows-only usage that matters under Wine/vkd3d-proton

| # | What | Where | Why it matters on this stack |
|---|---|---|---|
| 1 | `#[cfg(windows)]` is load-bearing, not decorative | `crates/victory-gpu/src/resource.rs:976` (`fn host_resource`), called unconditionally at `resource.rs:284` (upstream) / `:617` (ztrx) | This is what breaks the Linux build (§6). The whole GPU/HLE/loader layer is Windows-only by construction. **Verified.** |
| 2 | Shader-visible heap sized for 2^21 descriptors, with an explicit **NVIDIA** fallback path | `victory-shader/src/emit/shader.rs:25` `HEAP_VIEWS = 1<<21`; `victory-gpu/src/descriptor/host.rs:87` `PORTABLE_VIEWS = 1_000_000`, `:94` `DYNAMIC = 1<<18`, `:98` `MIN_DYNAMIC = 1<<16`, NVIDIA shortcut at `:154` and diagnostic at `:636` | On the 3070 the large heap may be refused and the heap capped at 1 M slots; translated shaders clamp indices below `HEAP_VIEWS` regardless (`descriptor/host.rs:140-142`). This is the only vendor-specific guard of its kind in the tree — and it is the 3070's problem, not AMD's. **Vendor-specific, must stay guarded.** |
| 3 | `GetWriteWatch` + `MEM_WRITE_WATCH` change tracking | `victory-gpu/src/watch.rs:234,240`; `victory-hle/src/modules/xmem.rs:69,136`; `victory-gpu/src/list.rs:947,964` | The entire "which pages did the title write" mechanism is a Windows kernel facility. Under Wine/vkd3d-proton its fidelity is unknown → every host copy may fall back to copying whole. Marked **UNVERIFIED**: needs a Wine run. |
| 4 | Page-guard + vectored exception handler | `victory-gpu/src/watch.rs:589-623` (`AddVectoredExceptionHandler`), `:275-281`, `:406-419` | Title memory is made read-only and the first write is caught by the VEH. If Wine does not deliver these faults as expected, tracking degrades or the title crashes. **UNVERIFIED.** |
| 5 | `VirtualAlloc2` + `MEM_RESERVE_PLACEHOLDER` + `MapViewOfFile3` | `victory-hle/src/modules/xmem.rs:123-142, 787` | Windows 10 1803+ placeholder semantics; Wine implements them but their interaction with write-watching (`xmem.rs:135-137`) is untested here. **UNVERIFIED.** |
| 6 | DRED / device-removed reporting | `victory-gpu/src/host.rs:172` (`ID3D12DeviceRemovedExtendedDataSettings`), `:1039` (`…ExtendedData1`) | vkd3d-proton supports DRED partially; diagnostics-only, must never be on the hot path. |
| 7 | `OpenExistingHeapFromAddress1` / `OpenExistingHeapFromFileMapping` | ztrx/allforks `victory-gpu/src/inplace.rs` | Newest heap APIs. ztrx's header notes the driver/runtime rules measured with the **software adapter**, and warns that a tile mapping into such a heap **removes the device**. vkd3d-proton support unknown → **UNVERIFIED**, keep `VICTORY_INPLACE` off. |
| 8 | Wave64 → host wave size | `victory-shader/src/emit/wave.rs:133` (`if p.wave64 {64} else {32}`), `emit/lower.rs:528`, `ir.rs:44,129` | The console is AMD/RDNA wave64; the 3070 is warp-32. Every lane-mask fix is a correctness fix that only shows on a warp-32 host — i.e. exactly this machine. AMD-only concerns belong in Phase 5. |
| 9 | FidelityFX host DLL | `victory-hle/src/modules/fidelityfx.rs:33` (`amd_fidelityfx_upscaler_dx12.dll`), config `victory-core/src/config.rs:25-27,103` | AMD-branded but runs on NVIDIA; needs `VICTORY_FIDELITYFX_DIR` pointing at the user's own FidelityFX SDK folder, else the title's own DLLs run (`fidelityfx.rs:149-167`). |
| 10 | Image mapped *away* from its preferred base | `victory-loader/src/prepare.rs:98` — "the loader maps the copy away from its preferred base (**Wine always does for DYNAMIC_BASE images**)" | Already handled by neutralising the TLS callback relocation; this is the single most useful existing Wine note in the tree. **Do not regress it.** |
| 11 | Crash unwinding via `RtlVirtualUnwind` / `RtlLookupFunctionEntry` | `victory-loader/src/crash.rs:23-24` | ntdll-level unwinding; Wine provides it, but the quality of `module+rva` names on Wine is unverified. |
| 12 | `windows` / `windows-sys` are target-gated | `crates/victory-loader/Cargo.toml:18` `[target.'cfg(windows)'.dependencies]` | Any `use windows_sys::…` outside a `cfg(windows)` item is a Linux build break — the pattern behind every failure in §6. |

No `NVAPI`, no vendor DLL loading, no adapter-name branching was found anywhere:
`grep -rn "NVAPI|nvapi|nvidia|NVIDIA"` hits only comments in
`descriptor/host.rs`, `draw.rs:1086` ("1,000,000 views on NVIDIA") and two shader
lowering notes (`emit/lower.rs:2287,7291`). Vendor honesty is therefore
comment-level, not capability-probed.

---

## 5. Memory map: where the ~24 GB goes

All figures **structural** (read off the code, not measured — see the honesty
note at the top). Anchor measurement from a fork's own log is quoted at the end.

### 5.1 Title memory (the title's own)

| Component | Where | Size |
|---|---|---|
| Console budget the title is told | `victory-gpu/src/console.rs:22-26` | Series X: 10 GiB GPU-optimal / 3.5 GiB standard; Series S: 7,776 MiB |
| `XMemVirtualAlloc` → `VirtualAlloc2`, 64 KiB pages, write-watched when the address is ours | `victory-hle/src/modules/xmem.rs:87-171`, `:142` (`VirtualAlloc2`), `:135-137` (adds `MEM_WRITE_WATCH`), `:358` `PAGE = 64 KiB` | Address window 4 GiB … 2^40 (1 TiB): `xmem.rs:78` (`address_range`) |
| Physical page pool | `xmem.rs:461` `XMemAllocatePhysicalPages` | A pagefile-backed section, and the comment at `xmem.rs:475-476` records the title asking for **6.1 GiB at once** ("which a busy host often cannot commit (error 1450)") |

### 5.2 The layer's own memory (this is the part that doesn't exist on a console)

| Component | Where | Size |
|---|---|---|
| **Host copy ("shadow") of every title buffer a draw reads** — one full-size `D3D12_HEAP_TYPE_UPLOAD` buffer per buffer resource | `victory-gpu/src/shadow.rs:807` `register`, `:826` `find`, `:983` `all`; allocation `victory-gpu/src/host.rs:2215-2217` (`upload_buffer`, `D3D12_HEAP_TYPE_UPLOAD`) | 1:1 with every title buffer used, **plus** BAR/visible-memory cost of an upload heap |
| Snapshot pool for copy-back comparison | `victory-gpu/src/shadow.rs:89` `POOL_BYTES = 2 << 30` | **2 GiB** retained by design |
| **Texture staging** — one full-size upload buffer per texture, sized by `GetCopyableFootprints` | `victory-gpu/src/texture.rs:418` `staging`, `:450-461` | 1:1 with every texture uploaded (detiled), kept for the texture's life |
| Title-memory page table per view heap | `victory-gpu/src/memory.rs:45-50` (`BLOCK 4096`, `LEVEL1 4096`, `CAPACITY 512`), allocated in `memory.rs` `Shared::new` | `(4096 + 513·4096·2)` dwords ≈ **16.0 MiB** per view heap |
| Per-list written-page bitmap | `memory.rs:361-378` (`bits = (CAPACITY+1)·BLOCK`) | 2,101,248 bits ≈ **256 KiB per command list** |
| Views' written-pages bitmap | `victory-shader/src/emit/shader.rs:42` `VIEW_WRITE_BITS = 1<<22`; `shadow.rs` `bitmap()` | 512 KiB, global |
| Descriptor heap, view | `descriptor/host.rs:87-99, 114` | `max(count+2^18, 2^21)` descriptors × 32 B = **64 MiB VRAM** per view heap (32 MiB at the 1 M NVIDIA cap) |
| Stride + mark tables for that heap | `descriptor/host.rs:122-135` | `2^21·4` = 8 MiB + `2^21·8` = 16 MiB **per view heap**, upload heaps |
| Shader IR / DXIL blobs after PSO creation | `victory-gpu/src/shader_cache.rs` (disk cache), `pipeline/library.rs` (PSO library on disk) | Not resident by design; in-RAM retention UNVERIFIED (no measurement) |

### 5.3 The arithmetic that produces ~24 GB

`title memory (6–10 GiB)` + `host copy of every buffer (up to 1:1)` +
`staging of every texture (up to 1:1)` + `2 GiB snapshot pool` +
`descriptor/table overhead` + `the title's own 6.1 GiB page-pool section`
comfortably exceeds 16 GB of RAM before VRAM is counted. The 64 MiB/heap
descriptor heaps and 24 MiB/heap tables hit **8 GB of VRAM**, not RAM.

**Recorded measurement (a fork's own log, not mine):**
`.trees/ztrx/crates/victory-hle/src/modules/xmem.rs:883-901` — process commit
**27 GB** against a title limit of **13.5 GB** during gameplay. That line is the
only hard number any of the three trees contains for the RAM wall, and it is
consistent with the structural map above.

**Consequence for Phase 2:** the two 1:1 relationships (buffer copies and texture
staging) are the lever; the 2 GiB `POOL_BYTES` and the `HEAP_VIEWS`-sized
descriptor/strides/marks allocations are fixed costs that do not scale with the
title's data and should be sized from the real budget.

---

## 6. What builds and tests on Linux today (actually run)

Environment: `rustc 1.98.1`, targets installed `x86_64-unknown-linux-gnu`,
`x86_64-pc-windows-msvc`, `x86_64-pc-windows-gnu` (I installed the gnu std this
session). `cargo-xwin 0.24.1`. `x86_64-w64-mingw32-dlltool` **is not
installed**.

### `x86_64-unknown-linux-gnu` — `cargo check --workspace`

| tree | exit | first failure |
|---|---|---|
| upstream `940d32f` | **101 FAIL** | `error[E0425]: cannot find function host_resource in this scope` → `crates/victory-gpu/src/resource.rs:284:16`; the function is gated `#[cfg(windows)]` at `resource.rs:976`. `error: could not compile victory-gpu (lib) due to 1 previous error; 9 warnings` |
| allforks `ef7f036` | **101 FAIL** | `error[E0433]: cannot find module or crate windows_sys` at `crates/victory-loader/src/crash.rs:14:5`, `:19:5`, `:23:5`, `:27:5`, `:625:9` (the dep is `[target.'cfg(windows)'.dependencies]`, `victory-loader/Cargo.toml:18`); `E0433 cannot find console_insn in crate`; `cannot find texture` / `cannot find host` at `crates/victory-gpu/src/pipeline.rs:21:29`. 11 error lines, `could not compile victory-gpu (lib) due to 3 previous errors` |
| ztrx `90b529f` | **101 FAIL** | `E0425 cannot find function host_resource` at `crates/victory-gpu/src/resource.rs:617:16` (same class as upstream), plus the `windows_sys` errors in `victory-loader/src/crash.rs`; `could not compile victory-gpu (lib) due to 3 previous errors` |

Crates that *do* reach the compiler cleanly on Linux: `victory-core`,
`victory-pe`, `victory-shader` (lib, warnings only), `victory-formats`,
`victory-pipeline`. Crates that cannot: `victory-gpu`, `victory-loader`,
`victory-game`, `apps/victory`. So: **no tree has ever been built for Linux, and
the breakage is concentrated in exactly the three platform crates that matter.**

### `x86_64-unknown-linux-gnu` — `cargo test --workspace`

| tree | exit | note |
|---|---|---|
| upstream | **101 FAIL** | identical `E0425` at `resource.rs:284`; tests never start |
| allforks | **101 FAIL** | loader/gpu as above **plus a genuine test-target break**: `error[E0063]: missing field packed in initializer of emit::container::SigElement` → `could not compile victory-shader (lib test)`, and `could not compile victory-game (lib test) due to 3 previous errors`. This is an allforks merge artifact — the struct gained `packed` and a test constructor was not updated. |
| ztrx | **101 FAIL** | `windows_sys`/`console_insn` in `victory-loader` only (7 error lines); no `SigElement` break |

### Windows cross-compilation

| target | command | exit | result |
|---|---|---|---|
| `x86_64-pc-windows-gnu` | `cargo build -p victory --target x86_64-pc-windows-gnu` (allforks) | **101 FAIL** | `error calling dlltool 'x86_64-w64-mingw32-dlltool': No such file or directory (os error 2)` while building `windows-result`, `windows-strings`, `windows-sys`. **Toolchain gap, not a code defect** — the mingw-w64 binutils are absent on this machine |
| `x86_64-pc-windows-msvc` via `cargo xwin` | `cargo xwin build -p victory --target x86_64-pc-windows-msvc` (allforks) | **0 PASS** | `Finished dev profile ... in 44.77s`; produced `target/x86_64-pc-windows-msvc/debug/victory.exe`, **19,373,056 bytes** |

**Conclusion for Phase 1:** the Windows PE is buildable from Linux *today* with
`cargo-xwin`; the `-gnu` route needs `mingw-w64` installed; the native Linux
target needs the `cfg(windows)` leakage fixed before `cargo test` can run
anything.

---

## 7. Recommended merge base and ordered plan

### Merge base

**Common base: `ffe310eb2098e52169f4c44db5ffdabf43a72622`** — the only commit both
forks agree on, and the point where upstream's 319 later commits diverge.

**Trunk for the unified tree: `allforks/main` = `ef7f036a1ffa`**, not a merge of
all three, for three checkable reasons:

1. It has real per-author history and a merge graph (20 merges, `ALL-FORKS.md`
   names every upstream fork and hash), so every ported fix can be attributed —
   which rule 2 (keep attribution) and rule 4 (small reviewable changes) require.
2. ztrx's body is one squashed commit `578d459`; merging it would force a
   ~36 k-line conflict with no attribution. Its genuinely unique work is
   *file-additive* (`inplace.rs`, `bvh.rs`, `intersect.rs`, `rect.rs`,
   `own_bits.rs`, `bitcode/opt.rs`, `census.rs`, `threading.rs`, `spill.rs`,
   `console_insn*.rs`), so it can be ported file by file later.
3. allforks already contains the fxceless line that ztrx also descends from
   (`2119b0e`, merged as `2d3f43c`), so the shared ancestry is preserved by
   starting from allforks.

Upstream's 319 commits should arrive as a **separate, reviewed merge** after
Phase 1 — they are large in `victory-hle` (+4277) and `victory-pe` (+902), i.e.
areas the forks barely touched, so they conflict little but must not be rushed
into the first reviewable step.

### Ordered plan (proposal, needs your approval before any code change)

| Step | Work | Gate |
|---|---|---|
| 0.1 | Make the tree compile on `x86_64-unknown-linux-gnu`: gate `loader::crash`, `gpu::pipeline`, and `gpu::resource::view_format` behind `cfg(windows)`, or provide Linux stubs. Expected edits: `victory-loader/src/crash.rs` (module decl), `victory-gpu/src/resource.rs:284/617`, `victory-gpu/src/pipeline.rs:21`, `victory-loader/src/lib.rs` (`console_insn`). | `cargo check --workspace` and `cargo test --workspace` green on Linux |
| 0.2 | Fix the allforks test-only break `SigElement { packed }` so `cargo test` is meaningful. | `cargo test -p victory-shader` green |
| 0.3 | Add `scripts/build-linux.sh` around `cargo xwin build -p victory --target x86_64-pc-windows-msvc` (verified working, 44.8 s), with `-gnu` accepted only if `x86_64-w64-mingw32-dlltool` exists. | script produces `victory.exe` from a clean target dir |
| 0.4 | Add `scripts/play-linux.sh`: detect Proton (`~/.steam/steam/compatibilitytools.d/Proton-CachyOS Latest`, `GE-Proton11-12`, `UMU-Proton-11.0-2e` all present) or `wine`; `VKD3D_CONFIG`, caches under `$XDG_CACHE_HOME`, saves under `$XDG_DATA_HOME`, `--console series-x|series-s`. | runs `victory --help` under Proton |
| 0.5 | Record the Phase 1 baseline with `VICTORY_MEM_STATS`-style instrumentation only (no behaviour change): RSS, commit, swap, VRAM budget/usage, shader-cache warm-up. **Cannot be done without your game files; needs you to run it.** | numbers in `CHANGELOG-UNIFIED.md` |

Phase 2 order suggested by §5: bound and recycle texture staging first (1:1,
`texture.rs:418`), then buffer copies (`shadow.rs`), then size the fixed
allocations (`POOL_BYTES 2 GiB`, `HEAP_VIEWS` 2^21) from a real
`QueryVideoMemoryInfo` budget — upstream has none, allforks has one in
`diagstream.rs:639-650` that can be lifted.

---

## 8. What I could not verify (explicit)

- **Any runtime behaviour**: no title was run (rule 1). No fps, RSS, swap, VRAM
  or warm-up number is mine.
- **ztrx's 8 GB stability claim** — see §2; the commits do not contain the
  mechanism, and paging is the plausible one (UNVERIFIED).
- **Wine/vkd3d-proton fidelity of** `GetWriteWatch`, `MEM_WRITE_WATCH`,
  page guards + VEH, `VirtualAlloc2` placeholders, `MapViewOfFile3`,
  `OpenExistingHeapFromAddress1`, DRED, and `RtlVirtualUnwind` — all listed as
  UNVERIFIED in §4; Phase 1 is where they get tested.
- **`x86_64-pc-windows-gnu` buildability** — blocked by missing mingw-w64
  binutils on this machine, not by the code. Not attempted further.
- **VRAM and RAM measured split** of the §5 map — structural only.
- **Optional reference repos** (Belobug/VIctory-Belobug-AMD, brcly/TuxBox):
  not cloned, no licence check performed, nothing used from them.
