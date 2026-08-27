@echo off
rem ===========================================================================
rem  Compile and run MKDAT -- rebuild NEUROSIS.DAT from its manifest.
rem
rem  MKDAT is NOT part of the demo and is deliberately NOT in build.toml. That
rem  file's output is what the ten byte-identical artefacts are measured from,
rem  and a build tool has no business in it: `build.py build.toml` means "build
rem  the demo" and should go on meaning exactly that.
rem
rem  WHAT YOU NEED MOUNTED. The assets do not travel with the staged build --
rem  they are 1.7 MB and change about once a year -- so point this at wherever
rem  the repository is mounted:
rem
rem      MKDAT E:\ASSETS
rem
rem  where E: is the checkout. It expects E:\ASSETS\NEUROSIS.MAN and the
rem  PART001..PART007 directories beside it, which is how the tree is laid out.
rem
rem  EVERY ASSET FILENAME IS 8.3. That is not tidiness, it is the reason this
rem  can be a real-mode DOS program at all: DOS cannot open asphyxia_logo.raw.
rem  The names were shortened for this, and tools/build_assets.py is what
rem  produces them, so a regeneration keeps them 8.3.
rem
rem  WHAT IT WRITES, in the current directory:
rem      NEUROSIS.DAT   the blob
rem      DATOFS.INC     the offsets, as untyped Pascal constants
rem
rem  and it compares the blob against the 1994 file if you give it one, which
rem  is the check worth having: a manifest in the wrong ORDER produces a blob
rem  of exactly the right LENGTH that every part then misreads.
rem
rem  THIS FILE MUST BE CRLF, like every other DOS file here -- .gitattributes
rem  says so and kit/tools/pascal/eolcheck.py checks it. RUNPART.BAT was
rem  written with bare LF once and DOSBox mis-parsed its `if not exist`.
rem ===========================================================================

if "%1"=="" goto usage
if not exist %1\NEUROSIS.MAN goto nomanifest

echo Compiling MKDAT...
tpc MKDAT.PAS
if errorlevel 1 goto failed

echo.
MKDAT %1\NEUROSIS.MAN NEUROSIS.DAT DATOFS.INC %1\..\BIN\NEUROSIS.DAT
goto end

:usage
echo usage: MKDAT ^<assets-directory^>
echo.
echo   e.g.  MKDAT E:\ASSETS
echo.
echo   Rebuilds NEUROSIS.DAT and DATOFS.INC from ^<assets^>\NEUROSIS.MAN,
echo   then compares the result against ^<assets^>\..\BIN\NEUROSIS.DAT.
goto end

:nomanifest
echo MKDAT: no NEUROSIS.MAN in %1
echo   That directory should hold the manifest and PART001..PART007 beside it.
goto end

:failed
echo MKDAT: TPC could not compile MKDAT.PAS -- nothing was built.

:end
