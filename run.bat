@ECHO OFF
REM ===========================================================================
REM  Psycho Neurosis -- open an interactive DOSBox-X on this checkout.
REM
REM  NO PATHS IN HERE, and that is the point. %~dp0 is the directory this batch
REM  file sits in, so the whole thing works from any checkout on any machine,
REM  and the two host paths it used to carry -- the emulator's and this
REM  repository's -- are gone. They live in kit.local.toml, which git ignores.
REM
REM  It also cannot go stale against the build any more. This used to pass ONE
REM  -conf, and the mounts have since moved out of that file into a generated
REM  overlay, so it would have started DOSBox with no drives at all. Now the
REM  same command that writes the overlay launches the emulator with both
REM  configs, so there is one place that knows how to do it.
REM
REM      run.bat              write the mounts and start DOSBox-X
REM
REM  To see the command without running it:
REM      .venv\Scripts\python.exe kit\tools\pascal\build.py build.toml --interactive
REM ===========================================================================
cd /d "%~dp0"
.venv\Scripts\python.exe kit\tools\pascal\build.py build.toml --interactive --launch
