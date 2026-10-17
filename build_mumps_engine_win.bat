@echo off
setlocal
REM ============================================================================
REM  build_mumps_engine_win.bat
REM  Build a MUMPS-enabled OpenCourant engine (Windows x64, Intel oneAPI + Intel MPI).
REM  Produces  exec\engine_win64_impi.exe : double precision, MPI, implicit (/IMPL).
REM
REM  Mirrors the aarch64 VPS build (build_mumps_engine.sh): drive CMake directly
REM  (the repo's root build_windows.bat has an arg-parsing bug -> use engine/ directly).
REM  Prereqs: Intel oneAPI HPC Toolkit (ifx/icx/Intel MPI/MKL), CMake, Ninja,
REM  Python, VS Build Tools (MSVC).  MUMPS 5.5.1 source at engine\extlib\MUMPS_5.5.1.
REM
REM  Usage:  build_mumps_engine_win.bat [source_dir]
REM ============================================================================

set "SRC=%~dp0"
if not "%~1"=="" set "SRC=%~1"
set "ONEAPI=C:\Program Files (x86)\Intel\oneAPI"
set "VSROOT=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
set "CMAKE_DIR=C:\Program Files\CMake\bin"
set "NINJA_DIR=C:\Users\j0sua\AppData\Local\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe"

echo == MSVC environment ==
call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || goto :err

echo == Intel oneAPI environment ==
set "VS2022INSTALLDIR=%VSROOT%"
call "%ONEAPI%\setvars.bat" intel64 >nul || goto :err
set "PATH=%CMAKE_DIR%;%NINJA_DIR%;%PATH%"

where ifx  >nul || goto :err
where icx  >nul || goto :err

cd /d "%SRC%" || goto :err

echo == 1/2 extlib ==
python Compiling_tools\script\load_extlib.py || goto :err

echo == 2/2 engine (dp, impi, MUMPS) ==
cmake -S engine -B engine\cbuild_win64_impi -G Ninja ^
  -Darch=win64 -Dprecision=dp -Ddebug=0 -DMPI=impi ^
  -DEXEC_NAME=engine_win64_impi -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_Fortran_COMPILER=ifx.exe -DCMAKE_C_COMPILER=icx.exe -DCMAKE_CXX_COMPILER=icx.exe || goto :err

cmake --build engine\cbuild_win64_impi --parallel %NUMBER_OF_PROCESSORS% || goto :err

echo.
echo OK -^> %SRC%engine\cbuild_win64_impi\engine_win64_impi.exe
goto :eof

:err
echo.
echo *** BUILD FAILED ***
exit /b 1
