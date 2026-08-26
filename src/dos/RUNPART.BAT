@echo off
rem ===========================================================================
rem  Psycho Neurosis -- run one reconstructed part.
rem
rem  THE HARNESS IS OUT HERE NOW, NOT LINKED INTO THE PART. It used to be a
rem  generated Pascal program that called the part through a driver unit, and
rem  those two segments have no counterpart in the 1994 binaries -- the
rem  original's main body IS its program. Carrying them put Turbo Pascal's
rem  runtime on a different paragraph, so every far call into it differed from
rem  the original's. Part 007 went from 99.7% to 100.0% the moment they went.
rem
rem  A batch file rather than a Pascal launcher on purpose: DOS Exec would have
rem  to stay resident while the part runs, and these parts want the memory.
rem
rem  Usage, from the folder holding the parts and NEUROSIS.DAT:
rem
rem      RUNPART 7
rem ===========================================================================

if "%1" == "" goto usage
if not exist NEUR%1.EXE goto nopart
if not exist NEUROSIS.DAT goto nodata

NEUR%1.EXE
goto end

:usage
echo RUNPART - run one reconstructed part of Psycho Neurosis.
echo.
echo   Usage:  RUNPART n        where n is the part number
echo.
echo Run it from the folder holding the parts and NEUROSIS.DAT.
goto end

:nopart
echo RUNPART: NEUR%1.EXE is not here.
echo          Only parts rebuilt as real programs have one; the rest are
echo          still TPARTn.EXE test harnesses.
goto end

:nodata
echo RUNPART: NEUROSIS.DAT not found in the current directory.
echo          Every part reads its assets from it. Run this from run\.
goto end

:end
