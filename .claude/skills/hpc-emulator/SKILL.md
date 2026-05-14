---
name: hpc-emulator
description: >-
  Single-node HPC emulator: TCP-fabric MPI + netem latency on lo + dm-delay
  block device on tmpfs, layered together so a dev workstation behaves enough
  like a cluster to A/B test parallel-I/O and async-MPI code before booking
  real cluster time. Use when the user says "emulate a cluster", "HPC
  emulator", "set up the slow rig", "validate parallel I/O locally", "test
  async MPI locally", "before booking cluster time", or invokes
  `/hpc-emulator setup|teardown|verify`. Also a fit when a dev-box A/B test
  shows no win because shared-memory MPI + local NVMe are too fast/free to
  expose the bottleneck the code targets.
argument-hint: "setup | teardown | verify"
allowed-tools:
  - Bash
  - Read
---

# hpc-emulator — synthetic cluster on one workstation

## What it is

A three-layer emulator that adds independently-tunable slowdowns to a single Linux box so a local A/B benchmark predicts cluster behavior:

| Layer | What it emulates | Mechanism |
|---|---|---|
| 1. TCP MPI | Inter-node MPI fabric (vs free shared-memory) | `MPIR_CVAR_NOLOCAL=1`, `FI_PROVIDER=tcp` env vars at `mpiexec` |
| 2. netem on `lo` | Cluster-grade fabric latency / jitter | `tc qdisc add dev lo root netem delay <X>us <jitter>us` |
| 3. dm-delay block device | Parallel-FS first-byte latency | loop device on **tmpfs** + `dmsetup create ... delay` |

Each layer is provable independently — that's what `emulator_verify.sh` does, and the cache file at `~/.cache/hpc-emulator/verified-<host>-<kernel>` records that the layers measured correctly on this kernel.

Scripts live in `<skill_dir>/scripts/`. The skill itself is generic; project-specific data staging (which files to copy onto the slow mount) goes in a thin per-project wrapper that exports `HPC_EMU_STAGE_SRC` before exec-ing `emulator_setup.sh`.

## The two critical gotchas

Both were learned the hard way. Don't relitigate them.

**1. Back the loop image with `/dev/shm`, NOT real disk.**
If the loop file lives on NVMe, the test result is dominated by kernel page-cache writeback backpressure: the first large write fills the page cache, kernel hits `vm.dirty_background_ratio`, all subsequent writes block on writeback through dm-delay. This produces ridiculous timings (parallel I/O often looks **worse** than legacy by 3-4×). `tmpfs` backing eliminates writeback artifacts; dm-delay's first-byte latency still applies cleanly. The default `HPC_EMU_IMG=/dev/shm/hpc_emu.img` is correct — do not override to `/var/tmp/...`.

**2. Leave one core free for the kernel.**
Running `mpiexec -n N ... taskset -c 0-(N-1)` on an N-core machine leaves no CPU for the kernel writeback thread, and writes serialize hard. Drop to `mpiexec -n (N-1) ... taskset -c 0-(N-2)` for a clean signal. Pattern generalizes: always leave at least one core free for kernel threads when running a synthetic-slow test.

## When to fire

Use the skill when the user is about to A/B test code on this workstation and the dev-box environment is too generous to expose what they're trying to measure:
- Parallel ensemble I/O (does the parallel reader beat serial when reads are slow?)
- Async vs sync collectives (does `Igatherv` beat `Gatherv` when fabric is slow?)
- Page-cache eviction strategies, prefetch ordering, anything I/O-shape-dependent

Don't fire when:
- The user is iterating on correctness / unit tests — emulator slows everything down and obscures stack traces.
- The user is profiling on a real cluster already — the emulator is a substitute, not a complement.

## Setup / verify / teardown

All scripts are in `<skill_dir>/scripts/`.

**First use on a new machine — user-driven, in a real terminal window.**

The skill needs passwordless sudo for a handful of tightly-scoped commands (`losetup` on our images, `dmsetup` on our two device names, `mount`/`umount` at our two paths, `tc` on `lo` only, etc.). The one-time install of that sudoers fragment requires the user's sudo password — by definition it can't be done unattended, since NOPASSWD isn't wired yet. **The user must run the bootstrap script themselves, in a real terminal window** (not via Claude Code's `!` prefix — that runs commands in a non-interactive subshell, so the y/N confirmation and the sudo password prompt both fail silently). Writing to `/etc/sudoers.d/` is a deliberate security boundary the user should cross explicitly.

When `emulator_setup.sh` (or verify, or teardown) detects that NOPASSWD isn't wired, it exits with a clear message pointing at the bootstrap. Claude's job in that case is: **relay the bootstrap instruction to the user, tell them to run it in a normal terminal (not `!` in Claude), and stop.** Tell the user to open their own terminal — gnome-terminal, tmux pane, ssh session, anything with an interactive TTY — and run:
```bash
<skill_dir>/scripts/emulator_bootstrap.sh
```
The bootstrap is interactive — it displays the rendered sudoers fragment (with `__USER__` replaced by their login), asks for y/N confirmation, prompts for the user's password once, runs `visudo -cf` to syntax-check, then installs to `/etc/sudoers.d/hpc-emulator`. After that one step, the rest of the skill is hands-off and the user can drive it via Claude as normal.

**Repeat use (NOPASSWD already wired).** Just:
```bash
<skill_dir>/scripts/emulator_setup.sh    # auto-runs emulator_verify.sh first if no cache, caches result
```
The verify step takes ~30 s and proves each of the three layers measurably exists on this kernel. After it passes, the cache file at `~/.cache/hpc-emulator/verified-<host>-<kernel>` lets subsequent setups skip verify.

**Repeat use.** Just:
```bash
<skill_dir>/scripts/emulator_setup.sh
```
Cache hit → straight to setup.

**Tear down.** When done benchmarking:
```bash
<skill_dir>/scripts/emulator_teardown.sh
```
Removes the netem qdisc, unmounts, removes the dm-delay device, detaches the loop, deletes the image. System returns to pristine state.

**Force re-verify** (e.g. after kernel upgrade or if you suspect drift):
```bash
HPC_EMU_FORCE_VERIFY=1 <skill_dir>/scripts/emulator_setup.sh
```
or just delete the cache file at `~/.cache/hpc-emulator/`.

## Configuration (env vars)

All of these have defaults that match what's known to work. Override only when you know why.

| Env var | Default | What it controls |
|---|---|---|
| `HPC_EMU_IMG` | `/dev/shm/hpc_emu.img` | Backing file for the loop device (**must be tmpfs**) |
| `HPC_EMU_IMG_GB` | `25` | Sparse size of the loop image |
| `HPC_EMU_MNT` | `/mnt/hpc_emu` | Mount point for the slow filesystem |
| `HPC_EMU_READ_MS` | `3` | dm-delay read latency (ms) |
| `HPC_EMU_WRITE_MS` | `5` | dm-delay write latency (ms) |
| `HPC_EMU_NETEM_DELAY` | `10us` | Fabric latency added to loopback |
| `HPC_EMU_NETEM_JITTER` | `2us` | Fabric jitter (normal distribution) |
| `HPC_EMU_STAGE_SRC` | (unset) | If set, contents of this directory are staged onto the slow mount before slow delays are applied. Files copied to `$HPC_EMU_MNT/$(basename $HPC_EMU_STAGE_SRC)/`. |
| `HPC_EMU_STAGE_GLOB` | `*` | Glob to filter which files within `HPC_EMU_STAGE_SRC` are staged |
| `HPC_EMU_SKIP_VERIFY` | (unset) | Set to `1` to skip the auto-verify even on a fresh host. Don't use unless you're debugging the verify itself. |
| `HPC_EMU_FORCE_VERIFY` | (unset) | Set to `1` to re-run verify even if cache says it already passed |

## Wiring an A/B run-matrix script

Once the emulator is up, the project's run-matrix script needs four things:

1. **Force MPI off shared-memory onto loopback TCP:**
   ```bash
   export MPIR_CVAR_NOLOCAL=1 FI_PROVIDER=tcp
   ```
2. **Pin to `N-1` cores** (leave one for the kernel — see gotcha #2):
   ```bash
   taskset -c 0-$(($(nproc)-2)) mpiexec -n $(($(nproc)-1)) "$EXE" "$YAML"
   ```
3. **Drop the page cache between runs** so reads actually hit the slow disk:
   ```bash
   python3 -c 'import os,sys
   for p in sys.argv[1:]:
       fd=os.open(p,os.O_RDONLY); os.posix_fadvise(fd,0,0,os.POSIX_FADV_DONTNEED); os.close(fd)
   ' /mnt/hpc_emu/path/to/inputs/*
   ```
   (`posix_fadvise(DONTNEED)` evicts files you own — no sudo required, unlike `drop_caches`.)
4. **Drain prior writeback before each run** so a tail-write spike from the previous run doesn't bleed into the next wall-clock measurement:
   ```bash
   sync; sleep "${DRAIN_SECONDS:-30}"
   ```

## What the emulator does NOT capture

It's a single-node approximation, not a cluster simulator. Treat results as "did the SHAPE of the speedup flip from negative to positive" — not as a quantitative cluster forecast.

- Real Lustre has parallel OSTs and metadata servers; this rig is a single block device with a single ext4 journal. Don't use it to characterize OST contention or MDS load.
- Real cluster fabric has many NICs and switch hops; this rig is a single loopback link with a single netem qdisc. Doesn't model topology effects.
- Real HPC scheduling adds noise (other jobs sharing storage, etc.) that this rig doesn't have.
- 7-rank synthetic ≠ 200-rank real. Validate the **direction** of the change, not the magnitude.

## Cross-machine portability

The skill needs passwordless sudo for the **exact command lines** emulator_setup/verify/teardown invoke — not blanket access to `dmsetup`, `tc`, `mount`, etc. `scripts/sudoers.example` is scoped tightly:

- `losetup` / `blockdev` only on `/dev/shm/hpc_emu*.img` and `/dev/loop*`
- `dmsetup` only on the two specific dm-delay device names this skill creates (`hpc_emu`, `hpc_emu_verify`)
- `mkfs.ext4` only on `/dev/mapper/hpc_emu` and `/dev/mapper/hpc_emu_verify`
- `mount` / `umount` only at `/mnt/hpc_emu` and `/mnt/hpc_emu_verify`, only mounting our dm devices
- `tc` only on the loopback interface `lo`, only the netem delay variant — `eth0`/`wlan0`/etc. cannot be touched
- `chown` only to the current user, only on the two mount points

A bug or shell-injection inside a skill script can still only manipulate these specific resources, not gain general root.

`<skill_dir>/scripts/emulator_bootstrap.sh` walks the user through installing this fragment to `/etc/sudoers.d/hpc-emulator` (it renders `sudoers.example` with `__USER__` replaced by the current `$USER`, asks for confirmation, runs `visudo -cf` for syntax check, then uses `sudo install` to deploy it). **The user runs the bootstrap themselves**, not via Claude — see "Setup / verify / teardown" above.

To install manually instead of running bootstrap:
```bash
sed "s/__USER__/$USER/g" <skill_dir>/scripts/sudoers.example | sudo tee /etc/sudoers.d/hpc-emulator >/dev/null
sudo chmod 0440 /etc/sudoers.d/hpc-emulator
sudo visudo -cf /etc/sudoers.d/hpc-emulator   # syntax check
```

## Failure modes

- **`/dev/shm` too small for `HPC_EMU_IMG_GB`** — tmpfs is sized at half RAM by default; if `IMG_GB` exceeds free tmpfs space, `truncate` succeeds but writes fail. Lower `HPC_EMU_IMG_GB` or remount `/dev/shm` larger.
- **Verify reports layer 1 unchanged** — usually means MPI defaulted back to shm; check `MPIR_CVAR_NOLOCAL=1` made it into the env (some `mpiexec` wrappers strip env vars without `-genv`).
- **Verify reports layer 3 no slowdown** — usually means dm-delay didn't apply; check `dmsetup table hpc_emu_verify` shows the read/write delays. If table shows `0 ... delay <dev> 0 0 <dev> 0 0` you're at zero delays; the reload step probably failed silently.
- **Teardown leaves a stale loop device** — re-run teardown; it's idempotent.

## Manual invocation forms

- `/hpc-emulator setup` → exec `<skill_dir>/scripts/emulator_setup.sh`
- `/hpc-emulator teardown` → exec `<skill_dir>/scripts/emulator_teardown.sh`
- `/hpc-emulator verify` → exec `<skill_dir>/scripts/emulator_verify.sh` (always runs, ignores cache)
