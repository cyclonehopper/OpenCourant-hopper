# TYPE24 energy diagnostic: build-loop and instrumentation recipe

Companion to `type24-damping-energy.md`. Written 2026-10-18 after the first engine builds
from the fork, when the ~+60 % mechanical-book drift of the toy model was attacked with
code-level A/B experiments.

## 1. The build loop (works, ~25 s per iteration)

```
%TEMP%\opencode\CAL0002\toy\build_hopper_engine.bat    # SMP, dp, no MUMPS
%TEMP%\opencode\CAL0002\hopper_exec\engine_hopper.exe  # patched  (+ libiomp5md.dll)
%TEMP%\opencode\CAL0002\hopper_exec\engine_hopper_ctl.exe  # unpatched control
```
The control build reproduces the shipped `engine_win64.exe` bit-for-bit on the toy deck
(IE 240224 mJ, KE+RKE 27232 mJ, PW 119246.9 mJ, contact 0.65 mJ, ERR +60.61 %), so any
difference measured against it is attributable to the source change.

Practical notes learned the hard way:

* **Run the deck from the model directory.** `setenv.bat` plus relative `-i` paths means a
  `cd` in the same command silently runs the wrong directory and produces no outputs.
* Ninja's WinGet shim (`...\WinGet\Links\ninja.exe`) is a dangling symlink; use the real
  binary at `%TEMP%\opencode\tools\ninja\ninja.exe`.
* `ifx` rebuilds only the changed object, but if the object's timestamp ends up newer than
  the source (can happen after copy/restore cycles) ninja will *not* recompile. Delete
  `CMakeFiles\engine_hopper.dir\source\interfaces\int24\i24for3.F*` to force it.

## 2. Instrumentation recipe (and its traps)

Add to `I24FOR3` (see `%TEMP%\opencode\CAL0002\toy\instrument_i24_stdout.py`):

```fortran
* declare:   my_real ECONW1,ECONW2,ECONW3 / SAVE ECONW1,ECONW2,ECONW3
* reset when NCYCLE==1
* before the "SAUVEGARDE DE L'IMPULSION NORMALE" section:
      DO I=1,JLT
        IF(PENE(I).EQ.ZERO)CYCLE
        ECONW1 = ECONW1 + FNI(I)*VN(I)*DT1          ! normal contact force work
        ECONW2 = ECONW2 + HALF*STIF(I)*PENE(I)**2   ! stored penalty energy
        ECONW3 = ECONW3 + ABS(FNI(I))               ! force magnitude
      ENDDO
      IF (MOD(NCYCLE,10).EQ.0) THEN
        WRITE(6,'(A,1X,I8,1X,1PE12.5,3(1X,1PE12.5))')
     .   'I24DIAG',NCYCLE,TT,ECONW1,ECONW2,ECONW3
      ENDIF
```

Traps that cost real time here:

1. **Fixed form: keep every inserted line <= 72 columns**, and put continuation lines with a
   character in column 6 (`.`) - long list-directed writes get truncated otherwise.
2. **`OPEN` statements inserted into this routine were dropped by `ifx /O3`** (the literal
   never reached the object) while `WRITE(6,...)` survived - so route diagnostics to stdout
   (unit 6) and capture the engine's stdout to a file. Do not rely on `OPEN`.
3. **List-directed `WRITE(6,*)` wraps at the console record length** (~65-80 chars), so the
   trailing values silently appear on the next line - use an explicit format.
4. `I24FOR3` is only *called* while the interface has candidates: in the toy that is cycles
   0-3370 (0-3.7 ms), 2201 calls. A diagnostic written at the routine end is fine, but do
   not expect it to fire all run.
5. The buffer is only guaranteed on normal termination; capture stdout to a file and parse it.

## 3. Measurements from the code-side bisect

Deck-side levers, control engine, single domain, base = **+60.61 %**:

| variant | ERR book | note |
|---|---|---|
| base (4/5e-7 CST, `/DT/INTER/V5`, Ish3n=1, Ishell=24) | +60.61 % | |
| `/DT/INTER/V5` removed | +51.19 % | the V5 interface-damping formulation is worth ~9 pts |
| `/DT/NODA/CST` removed (adaptive dt) | +59.29 % | constant-dt machinery ~1.3 pts |
| both removed | +48.67 % | bulk of the drift survives |
| `Ish3n = 2` (triangle formulation) | +60.86 % | no effect |
| `Ishell = 12` (BATOZ) | +61.78 % | no effect |
| `Ishell = 1` (Belytschko + hourglass) | +86.29 % | HG energy 587 mJ appears; drift persists |

Instrumented interface (patched engine + diagnostic), normal-force work integral
`W = SUM FNI*VN*DT1` vs the phantom:

| Stfac | W (J) | phantom (J) |
|---|---|---|
| 0.2 | 6.0 | 62 |
| 1.0 | 44.1 | 101 |
| 5.0 | 265.2 | 1629 |

`W` scales about linearly with the contact stiffness (~K^1.05) while the phantom scales
super-linearly (K^1.5+) - so the interface's own force work does **not** explain the drift.

Timeline at the base setting (T01 mechanical gain vs the interface work):

| t (ms) | mech gain (J) | W (J) |
|---|---|---|
| 0.65 | 63.6 | 33.9 |
| 1.32 | 82.3 | 37.9 |
| 2.4 | 89.6 | 41.9 |
| 3.3 | 92.6 | 44.0 |
| 20 | 100.9 | 44.1 (interface inactive after 3.7 ms) |

The mechanical books gain ~63 J by 0.65 ms while the interface work integral is only ~34 J,
and the gain continues (+8 J) after the interface has stopped producing candidates. With
no external loads in the model, neither the interface work nor the elements explain the
whole gain yet - the next experiments should split the work between the secondary nodes and
the main facets (the shape-function reaction), and instrument the applied-vs-booked
stiffness in the live `/DT/INTER/V5` branch (it contains `MAX(STIF0, FAC*sqrt(VISCFFRIC)*
VIS2)*DT1INV`, i.e. a stiffness floor that scales as 1/dt).
