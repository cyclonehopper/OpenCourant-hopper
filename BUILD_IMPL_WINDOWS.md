# Building a MUMPS-enabled OpenCourant engine on Windows (implicit `/IMPL`)

The **shipped** OpenCourant `win64` engines have MUMPS **stubbed out** (`MUMPS5` undefined).
They do still run `/IMPL` where MUMPS is not needed: the direct solver on a single domain
(`ISOLV=2` with `NSPMD=1`), or the iterative PCG solver (`ISOLV=1`) at any rank count — but
the configuration we need, the **direct solver across MPI ranks** (`ISOLV=2`, `NSPMD>1`), is
refused while the deck is read in:

```
Fatal error: MUMPS is required, but not available      :: engine/source/input/lectur.F
```

Two further paths are `#ifndef MUMPS5` and fail the same way: Navier-Stokes viscosity at
`NSPMD>1` (`Fatal error: MUMPS is required to solve Navier-Stokes viscosity`, `radioss2.F`)
and the Lagrange-multiplier solver (`Error: this feature requires the MUMPS library`,
`lag_mult_solv.F`). Single precision is rejected outright: `SINGLE PRECISION IS NOT
COMPATIBLE WITH IMPLICIT OPTION`. This document reproduces the local build that produced the
working engine; with MUMPS 5.5.1 linked in, all of the above run.

**Result:** `exec\engine_win64_impi.exe` — double precision, Intel MPI, MUMPS 5.5.1 compiled
in. (The original shipped engine is kept as `exec\engine_win64_impi_orig.exe`.)

> The build tools/artifacts (Intel oneAPI, CMake, Ninja, the source clone) can be deleted
> afterwards — the engine only needs, at run time, **`impi.dll`** and **`libiomp5md.dll`**,
> both already present in `exec\..\extlib\intelOneAPI_runtime\win64`. This file is all that
> is needed to rebuild.

---

## 1. Prerequisites (build-time only)

| Component | How | Notes |
|---|---|---|
| Intel oneAPI **HPC Toolkit** | `winget install --id Intel.OneAPI.HPCToolkit -e --source winget` | superset of the Base Toolkit → gives `ifx`, `icx`, **Intel MPI**, **MKL**. ~15 GB. Needs elevation. |
| CMake + Ninja | `winget install Kitware.CMake`, `winget install Ninja-build.Ninja` | Ninja generator |
| VS Build Tools (MSVC) | already present (VS 2026 Build Tools) | provides `link.exe` / MSVC libs |
| Python 3 | already present | for `load_extlib.py` |
| git | already present | |

## 2. Get the source and third-party pieces

```cmd
git clone --depth 1 https://github.com/OpenCourant/OpenCourant.git C:\Users\j0sua\OpenCourant-src
cd /d C:\Users\j0sua\OpenCourant-src
git fetch --depth 1 origin tag latest-20261006
git checkout latest-20261006                 :: match the installed release tag
python Compiling_tools\script\load_extlib.py :: fetches extlib - see 9.3: this tag's win64 reader is the v70-era one
```

Extract the **MUMPS 5.5.1** source into `engine\extlib\MUMPS_5.5.1`:

```cmd
curl.exe -L -o "%TEMP%\MUMPS_5.5.1.tar.gz" https://ftp.mcs.anl.gov/pub/petsc/externalpackages/MUMPS_5.5.1.tar.gz
tar.exe -xzf "%TEMP%\MUMPS_5.5.1.tar.gz" -C engine\extlib
```

## 3. Required local fixes (three)

The build fails on a stock checkout for three reasons — all fixed here:

1. **MKL 2025.1 layout.** MKL now puts its `.lib` files in a **flat** `%MKLROOT%\lib\`
   (there is **no** `lib\intel64\`). In `engine\CMake_Compilers\cmake_win64.txt`, remove the
   `/intel64` from `MKL_LDIR` (else the link can't find `mkl_scalapack_lp64.lib` /
   `mkl_blacs_intelmpi_lp64.lib`):

   ```cmake
   set(MKL_LDIR "$ENV{MKLROOT}/lib")                                          # was: .../lib/intel64
   set(MKL_LDIR "C:/Program Files (x86)/Intel/oneAPI/mkl/latest/lib")         # was: .../lib/intel64
   ```

2. **VS 2026 is not auto-detected** by oneAPI's `setvars.bat`. Set `VS2022INSTALLDIR` to the
   Build Tools dir *before* calling `setvars.bat` so it configures the MSVC env
   (`link.exe`, `LIB`, `INCLUDE`):

   ```cmd
   set "VS2022INSTALLDIR=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
   ```

3. **The repo's root `build_windows.bat` is buggy.** Its `-nt` block has a stray `)` →
   `The syntax of the command is incorrect.`, which leaves `MPI=SMP` and produces
   `ninja: no work to do.` **Drive CMake directly instead** (as `build_mumps_engine_win.bat`
   does, shown in §4). MUMPS is **auto-enabled** when the Fortran compiler is `ifx`/`ifort`
   **and** `-DMPI=impi` **and** `-Dprecision=dp` **and** `engine\extlib\MUMPS_5.5.1` exists
   (see `engine\CMakeLists.txt`); it is compiled from source into the engine and linked
   against **static** MKL ScaLAPACK/BLACS.

## 4. Build

Run `build_mumps_engine_win.bat` (kept alongside this file), or by hand:

```cmd
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set "VS2022INSTALLDIR=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
call "C:\Program Files (x86)\Intel\oneAPI\setvars.bat" intel64
set "PATH=C:\Program Files\CMake\bin;<ninja-dir>;%PATH%"

cmake -S engine -B engine\cbuild_win64_impi -G Ninja ^
  -Darch=win64 -Dprecision=dp -Ddebug=0 -DMPI=impi ^
  -DEXEC_NAME=engine_win64_impi -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_Fortran_COMPILER=ifx.exe -DCMAKE_C_COMPILER=icx.exe -DCMAKE_CXX_COMPILER=icx.exe

cmake --build engine\cbuild_win64_impi --parallel %NUMBER_OF_PROCESSORS%
```

Expect **7777** targets and ~20 min on 14 cores. The linking step prints
`Linking Fortran executable engine_win64_impi.exe`. Confirm the configure log says
`MUMPS is enabled` and `mumps_root: …/engine/extlib/MUMPS_5.5.1`.

## 5. Install

```cmd
copy /y engine\cbuild_win64_impi\engine_win64_impi.exe ^
        C:\Users\j0sua\OpenCourant\exec\engine_win64_impi.exe
:: (back up the shipped one first, once):
:: copy C:\Users\j0sua\OpenCourant\exec\engine_win64_impi.exe ^
::      C:\Users\j0sua\OpenCourant\exec\engine_win64_impi_orig.exe
```

## 6. Run an implicit model

Double precision + MPI; the **starter and engine must use the same `-np`**:

```cmd
call C:\Users\j0sua\OpenCourant\setenv.bat
cd /d <model_dir>
starter_win64.exe -i model_0000.rad -np N
mpiexec -np N engine_win64_impi.exe -i model_0001.rad
```

Deck (`model_0001.rad`):

```
/IMPL/NONLIN/1
  0 2 0 0 0
/IMPL/SOLVER/2          ! 1 = PCG (clean); 2 = MUMPS direct
  0 0 0 0
/IMPL/DT/1 ...
/IMPL/DTINI <end_time/1000>
/IMPL/DT/STOP <min> <2*dtini>
```

- `/IMPL/SOLVER/1` (PCG) works cleanly at any `-np`.
- `/IMPL/SOLVER/2` (MUMPS direct) works but prints `INFOG(1) = -19`
  *"MUMPS workspace too small. Retry"* a few times before succeeding — benign.

## 7. Verification done here

`impl_cc01_s355_e30` (DNV-RP-C208 CC01, QEPH `Ishell=24`, `Idrill=1`):

```
** IMPLICIT OPTION USED **
STIFFNESS MATRIX SETUP: ND = 982  NZ = 22851
IMPLICIT COMPUTATION TERMINATED ... 107 nonlinear iterations
NORMAL TERMINATION   26 cycles   0.56 s
```

## 8. After the build — what can be deleted

The engine statically links MKL, so at run time it needs only `impi.dll` +
`libiomp5md.dll` (already in `extlib\intelOneAPI_runtime\win64`, on PATH via `setenv.bat`).
Everything below is **build-time only** and can be removed to reclaim space:

| Path | Size |
|---|---|
| `C:\Program Files (x86)\Intel\oneAPI` (HPC Toolkit) | ~15 GB |
| `C:\Users\j0sua\OpenCourant-src` (source clone + build tree + MUMPS) | ~1.3 GB |
| `C:\Program Files\CMake` | ~137 MB |
| Ninja (`…\WinGet\Packages\Ninja-build.Ninja_*`) | ~0.6 MB |

Remove cleanly with `winget uninstall --id Intel.OneAPI.HPCToolkit`,
`winget uninstall Kitware.CMake`, `winget uninstall Ninja-build.Ninja`
(or just delete the folders). Do **not** delete `exec\engine_win64_impi.exe`.

---

## 9. Upstream baseline - what we are built on, and what we track

Reference for bug triage: what the upstream releases actually ship, versus what is installed
here. Recorded 2026-10-15.

### 9.1 The two baselines

| | Value |
|---|---|
| Installed tree `C:\Users\j0sua\OpenCourant` | upstream release **`latest-20261006`** (`33e68517`), asset `OpenCourant_win64.zip`, SHA-256 `8fa8d854b489b2732431c129107e0e846b89594f1bb3603da01ab24c0a98041c`. It is the **release package**, not a source clone (`README_WINDOWS.md` records it; 20261005 kept as `OpenCourant_20261005_bak`) |
| Our engine | built from that same tag's source + MUMPS 5.5.1, `ifx` 2026.1, Intel MPI, double precision |
| Latest upstream release checked | **`latest-20261011`** (`cb760c20`), published `2026-10-11T15:05:30Z` (11 Oct 23:05 local), 14 commits on. **Not adopted** - nothing in it touches `/IMPL` or MUMPS, and adopting it means refetching the extlib readers and rebuilding the engine |

### 9.2 Binaries: shipped vs ours (measured 2026-10-15)

| binary | bytes | `MUMPS` strings | MUMPS routine symbols |
|---|---|---|---|
| `exec\engine_win64_impi_orig.exe` (shipped) | 147,447,296 | 16 (interface text only) | none |
| `exec\engine_win64_impi.exe` (ours) | 159,236,096 | 550 | `DMUMPS_FAC2_LDLT`, `DMUMPS_ANA_DISTM`, ... |

The 16 strings in the shipped engine are messages, not code: `** LINEAR SOLVER MUMPS ERROR
CODE:`, `ERROR MPI EXEC FILE SHOULD BE USED FOR MUMPS SOLVER`, plus the refusals quoted in the
intro. PrePoMax will still *offer* "Direct (MUMPS)" on a stock engine - it aborts when the deck
is read. MUMPS is never vendored upstream: `engine/extlib/` ships only `get_mumps.sh` (wgets
`MUMPS_5.5.1.tar.gz` from MCS) and `engine/CMakeLists.txt` auto-enables MUMPS **only if**
`engine/extlib/MUMPS_5.5.1` exists. The official delivery workflow mentions mumps **0 times**.

### 9.3 The win64 reader we have is v70, dressed as v82

At `latest-20261006` the manifest is self-contradicting: top-level `"version": "82"`, while the
per-platform `reader_components.win64` block says

```json
"build_id": "20260710_d899773e",  "effective_extlib_era": "v70",
"source": ".../OpenRadioss/releases/tag/latest-20260728",
"reader_sha256": "ee7279ed3f5271217a8420358bbea69043470a08a6a9e641ba574f3b5d304eac",
"missing_symbols": ["cpp_get_include_file_by_index"]
```

Our `extlib\hm_reader\win64\hm_reader_win64.dll` hashes to **exactly** that `ee7279ed...`
(8,547,328 bytes) - so we are on the v70-era reader, imported from OpenRadioss, with one symbol
missing. `latest-20261011` ships a single reader for every platform, build
**`20260918_f907fe76`**, era **v82**, `missing_symbols: []`,
`HM_READER_LEGACY_INCLUDE_API` now defaults **OFF**.

**Bug relevance:** the release notes tie the v82 adoption to *"invalid node coordinates"*
observed with the **v70 win64 reader**. So if an `.h3d`/HM import ever fails that way on
Windows, the fix is to take the 20261011 reader - that is the only upstream delta that can
reach us without rebuilding the engine. Near-miss: `/ALE/STRUCTURED_MESH` produces degenerate
meshes (all nodes at one coordinate) under **both** v70 win64 and v82, so upstream keeps
`HM_READER_NO_STRUCTURED_ALE` **ON** - the feature is unfinished, and we do not use it.

### 9.4 What changed upstream, 20261006 - 20261011 (14 commits)

| Area | Commits | Relevance here |
|---|---|---|
| **extlib v82 on all platforms** | `cb760c20` (#50) | reader-only; see 9.3 |
| Rebrand to OpenCourant | `4b520479` (#49) | strings/docs only |
| OpenCourant notices enforced in CI | `3c2bfe86` | the bulk of the ~300-file diff: a `+3/-6` copyright-header pass on ~250 sources, no behaviour |
| Windows / MPI CI | `c71590e7` (#36), `4d3ce37d` (#37), `762e11da` (#39) | Windows toolchain now includes Intel MPI and exercises **impi** builds - the path we hand-rolled |
| Containers / packaging | `012df6f2` (#28), `e361d273` (#30), `b0a63f9b` (#32), `9e9c21c3` (#33) | none |
| Engine | `733c8d84` (#38) | "check to see if pointer exists in engine" - the only engine-code change |
| Housekeeping | `a0dd0dc9`, `a5e955ef`, `faa321f9` | none |

No commit in the range touches `/IMPL`, the implicit source tree, or MUMPS.

### 9.5 Upstream defects we track

| # | Defect | Upstream state | Effect on us |
|---|---|---|---|
| 1 | **`NKINE=0` heap overrun in `engine/source/implicit/ind_glob_k.F`** - five allocations left inside `IF (NKINE0>0) THEN` guards instead of unconditional `MAX(1,...)` sizing, so with no kinematic conditions they are never allocated and later written | **not fixed** in `main` or `latest-20261011` (verified: 4 guarded blocks, 0 `MAX(1,...)`). PR **OpenCourant/OpenCourant#53** (`KenpoYogi`, `7b75efb8`, 2026-10-11T16:26Z) is open, CI 7/7, mergeable, awaiting the maintainers' copyright-string question | our engine was built 11 Oct **16:56 local**, ~7.5 h *before* the fix commit, so it carries the old code. Trigger is a model with kinematic conditions absent - ours all set `/IMPDISP`, so the path is not taken. Failure mode is a **crash at the start of the solve** (`/O3` + `ifx 2026.1`), never wrong numbers |
| 2 | `/ALE/STRUCTURED_MESH` degenerate meshes (all nodes at one coordinate) | disabled upstream (`HM_READER_NO_STRUCTURED_ALE` stays ON), feature unfinished | not used |
| 3 | Lagrange-multiplier solver, Navier-Stokes viscosity at `NSPMD>1` need MUMPS | by design (`#ifndef MUMPS5`) | fine in our engine |

### 9.6 How to re-check, next time

```powershell
# newest release, and what commits it carries
gh release list --repo OpenCourant/OpenCourant --limit 5
gh api "repos/OpenCourant/OpenCourant/compare/<our-tag>...<new-tag>" `
  --jq '.commits[] | .sha[0:8] + "  " + (.commit.message | split("\n")[0])'

# what a tag's readers *really* are (top-level version can lie - read reader_components)
gh api "repos/OpenCourant/OpenCourant/contents/EXTLIB_VERSION.json?ref=<tag>" --jq '.content'

# is the NKINE=0 fix in yet? (expect 0 / nonzero while it is not)
#   contents/engine/source/implicit/ind_glob_k.F?ref=<tag>
#     -> count of ALLOCATE(ICOK(MAX(1 ,  and of  IF (NKINE0>0) THEN

# does a shipped engine have MUMPS at all? (compare against engine_win64_impi_orig.exe)
#   scan the .exe for "DMUMPS_" - 0 hits means MUMPS is stubbed
```
