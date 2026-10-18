# TYPE24 damping-contact-energy: provenance and build/measurement record

Companion notes for commit `76602e9e0` ("book viscous damping energy for the live IVIS2
branches"), which activates the five `ECONTDT` lines in
`engine/source/interfaces/int24/i24for3.F`. Written 2026-10-18.

## 1. When and why the lines were commented (full-history trace)

The clone used for the trace is a full-history clone (5184 commits); the repository's
oldest commit is the open-sourcing import.

| Question | Answer |
|---|---|
| When were the lines commented? | Before the first public commit. They are already `C`-commented in `df38c951b` (2022-05-10, "OpenRadioss", Olivier Wienholtz), which adds the whole 4767-line file at once with an "Altair Engineering Inc. 1986-2022" header. The decision therefore predates the public repo (Altair/Simcenter internal Radioss). |
| Did any later commit change them? | Only one: `b2abd109f` (2023-08-03, qiangRadioss, "remove useless coding block in int24") deleted a dead, unreachable `ELSEIF(IVIS2==2)` branch that contained one of them. No commit ever enabled them (verified with `git log -S` on both `ECONVT = ECONVT` and `ECONTDT = ECONTDT`). |
| Why? | Deliberate scoping, and it is documented by Altair: `/TH/INTER` help states *"Damping energy is computed only for Interfaces TYPE2, 10, 18, 21, 23, and 25. Thus, for other interfaces, it is not taken into account in global contact energy. This is not crucial as damping energy remains small compared to elastic and frictional energy."* (`CE_DAMP: Damping contact energy. Only calculated for Interfaces TYPE2, 10, 18, 21, 23 and 25.`) |
| Corroboration in code | At the same first commit the siblings book the same quantity in **active** lines: `i23for3.F` -> `ECONTDT = ECONTDT + C(I)*VN(I)*VN(I)*DT1`; `int25/i25for3.F` -> `ECONTDT = ECONTDT + PENE_OLD(3,N)*VN(I)*DT1`; `int07/i7for3.F` -> `ECONTDT = ... MIN(ZERO,FF-FNI(I))*VN(I)*DT1`. TYPE24's lines are the only ones left commented in the VISC branches. |
| Code fossil | `FFO = FF` is assigned in exactly the branches that needed the pre-scaling coefficient and is used nowhere else in the file - evidence that the energy line was authored and then muted without cleanup. (Note: the active lines use `FF` *after* velocity scaling, which is the correct `c*VN**2` power.) |

## 2. Build record (first successful fork build, 2026-10-18)

Toolchain (installed this session, user-level, no admin needed for CMake/Ninja):

* Intel oneAPI HPC Toolkit 2025.1 (`winget install --id Intel.OneAPI.HPCToolkit`) -
  provides `ifx`, `icx`, MKL, Intel MPI; landed in `C:\Program Files (x86)\Intel\oneAPI`.
* VS 2026 Build Tools already present (`...\Microsoft Visual Studio\18\BuildTools`);
  needs `VS2022INSTALLDIR` set before `setvars.bat` (oneAPI does not auto-detect VS 18).
* CMake 4.4.4 portable zip and Ninja 1.13.2 unpacked under
  `%TEMP%\opencode\tools\` (the WinGet ninja shim was a dangling symlink).
* `python Compiling_tools\script\load_extlib.py` fetched extlib v82 into
  `engine\extlib` (SHA-256 verified).
* Build (SMP, dp, no MUMPS - the toy is explicit):
  `cmake -S engine -B engine\cbuild_hopper -G Ninja -Darch=win64 -Dprecision=dp -Ddebug=0
  -DMPI=smp -DEXEC_NAME=engine_hopper -DCMAKE_BUILD_TYPE=Release ...` then
  `cmake --build engine\cbuild_hopper`. Incremental relink of an `int24` change
  takes ~25 s, which makes code experiments cheap.
* Script: `%TEMP%\opencode\CAL0002\toy\build_hopper_engine.bat`.

Validation: the **control** engine built from the unpatched file reproduces the shipped
`engine_win64.exe` **bit-for-bit** on the same deck (IE 240224 mJ, KE+RKE 27232 mJ,
PW 119246.9 mJ, contact 0.65 mJ, engine ERR +60.61 % - identical).

## 3. Patch verification (measured)

Same deck (toy: 2 kg-class cube vs steel plate, MM_TON_S_C, `/DT/NODA/CST` fixed dt):

| run | engine | IE | KE+RKE | PW | contact | elastic | **damping** | ERR book |
|---|---|---|---|---|---|---|---|---|
| `s1-hops` | shipped | 240224 | 27232 | 119246.9 | 0.65 | 0.00 | **0.00** | +60.61 % |
| `s1-hopc` | fork control | 240224 | 27232 | 119246.9 | 0.65 | 0.00 | **0.00** | +60.61 % |
| `s1-hopp` | fork patched | 240224 | 27232 | 119246.9 | 13.09 | 0.00 | **12.44 mJ** | +60.61 % |
| `s1-hopvp` | fork patched, ViscS=0 | 221638 | 27168 | 118798.6 | 4699.73 | 0.00 | **4699.11 mJ** | +49.41 % |

* The patch books the missing channel: damping 0 -> 12.44 mJ (cumulative; `ECONTD` is a
  running total in a serial run - `ecrit.F` only zeroes it on non-zero MPI ranks).
* Mechanical books are **bit-identical** with and without the patch, confirming that
  contact energies sit outside the ERR equation - the patch is completeness, not a fix.

## 4. Card gotcha discovered while measuring

**`ViscS = 0` on `/INTER/TYPE24` means "use the default 0.05", not "no damping".** The
starter prints `CRITICAL DAMPING FACTOR = 5.0000000000000E-02` for that card (vs
`1.0000000000000E-04` when ViscS=1e-4). An earlier experiment that compared
"ViscS=1e-4 vs ViscS=0" was therefore comparing 1e-4 against 5e-2 (500x more damping):
the mechanical drift moved +62 % -> +49 % because of that *physics* change, not because
of bookkeeping. The booked damping dissipation measured with the patched engine is only
**12.4 mJ** at the deck's 1e-4, versus a ~100 J mechanical drift - i.e. at this working
point the unbooked damping channel is negligible.
