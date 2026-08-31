@echo off
rem ===========================================================================
rem  Psycho Neurosis -- run one reconstructed part.
rem
rem  THE HARNESS IS OUT HERE NOW, NOT LINKED INTO THE PART. It used to be a
rem  generated Pascal program that called the part through a driver unit, and
rem  those segments have no counterpart in the 1994 binaries -- the original's
rem  main body IS its program. Carrying them put Turbo Pascal's runtime on a
rem  different paragraph, so every far call into it differed. Parts 004 and 007
rem  reached 100.0% the moment they went.
rem
rem  AND THE TIDYING UP BELONGS HERE TOO. The demo ran under PSYCHO.EXE, which
rem  launched each part in turn, so a part may leave the adapter however the
rem  next one wants it. Part 004 sets mode 13h at 1000:001c and never restores
rem  text mode, because NEUROSIS.005 was going to run next. Running one part on
rem  its own is not how any of them were invoked, so VIDMODE puts the screen
rem  back afterwards rather than a part being given code the original lacks.
rem
rem  Nothing is set up BEFORE the part: every part sets its own video mode. That
rem  was learned the hard way -- NEUR4 was built without its SetMode13h and
rem  displayed nothing at all.
rem
rem  A batch file rather than a Pascal launcher on purpose: DOS Exec would have
rem  to stay resident while the part runs, and these parts want the memory.
rem
rem  THE PARTS CARRY THE ORIGINALS' NAMES NOW, so they are launched through
rem  LOADPART rather than by name. COMMAND.COM decides what is executable by
rem  extension alone -- .COM, .EXE, .BAT -- so `NEUROSIS.001` cannot be typed at
rem  a prompt however valid an executable it is. LOADPART is a ten-line EXEC,
rem  which is what the demo's own launcher does: PSYCHO.PAS EXECs
rem  `Neurosis.000` by that name. See src/test/LOADPART.PAS.
rem
rem  WHAT IS INSTALLED HERE IS THE LOAD IMAGE, not yet the shipped file. Parts
rem  001-007 each ship with a ProTracker module appended past the image, so
rem  there is no music until the packaging step appends it. Measured: image plus
rem  assets/partNNN/*.MOD is byte-identical to the shipped file for all seven.
rem
rem  IF A PART REPORTS "NEUROSIS.00n IS NOT IN THIS DIRECTORY" AND IT PLAINLY IS,
rem  TYPE `rescan` (or press Ctrl-F4). DOSBox-X caches the file listing of a
rem  mounted host drive, so a filename that appears while DOSBox is ALREADY
rem  RUNNING is invisible to `if not exist` until the cache is flushed. A file
rem  that was already there when DOSBox started is fine however often it is
rem  rebuilt -- the content is read on open -- so this only ever bites the first
rem  time a NEW part name exists. It bit NEUR5.EXE on 27 Aug 2026, the day part
rem  005 stopped being a harness.
rem
rem  THIS FILE MUST BE CRLF. It was written with bare LF once and DOSBox's shell
rem  mis-parsed the `if not exist` line below, reporting NEUR2.EXE as missing
rem  while it sat in the same directory. .gitattributes marks .BAT as -text, so
rem  git stores whatever is on disk and will not correct it -- which is why
rem  kit/tools/eolcheck.py now checks.
rem
rem  Usage, from the folder holding the parts and NEUROSIS.DAT:
rem
rem      RUNPART 4
rem ===========================================================================

if "%1" == "" goto usage
if not exist NEUROSIS.00%1 goto nopart
if not exist NEUROSIS.DAT goto nodata

LOADPART NEUROSIS.00%1

rem Back to a readable prompt. Harmless if the part restored text mode itself,
rem as part 007 does.
VIDMODE TEXT
goto end

:usage
echo RUNPART - run one reconstructed part of Psycho Neurosis.
echo.
echo   Usage:  RUNPART n        where n is the part number
echo.
echo Run it from the folder holding the parts and NEUROSIS.DAT.
goto end

:nopart
echo RUNPART: NEUROSIS.00%1 is not in this directory:
cd
echo.
echo          Every part has one: 1, 2, 3, 4, 5, 6 and 7.
goto end

:nodata
echo RUNPART: NEUROSIS.DAT not found in the current directory.
echo          Every part reads its assets from it. Run this from run\.
goto end

:end
