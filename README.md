# Psycho Neurosis — a source reconstruction

*Psycho Neurosis* is Asphyxia's first megademo, released in 1994: real-mode DOS, VGA, Borland Pascal 7 with hand-written assembler for the parts that had to be fast. This repository recovers the source. Not a rewrite and not a port — source that a period Turbo Pascal compiles into **the same bytes the demo shipped as**.

That claim is measured rather than asserted, and the measurement is the point of most of what is here:

| | |
|---|---|
| **10 of 10** targets rebuild byte-identical | the seven effect parts, the setup program, the end screen, and the launcher |
| **85 of 85** routines byte-locked | each one recorded against an address in the original, and a shortened match fails the build |
| **12 of 12** packaged files match what shipped | parts 001–007 whole, `NEUROSIS.DAT` whole, `PSYCHO.EXE` whole; parts 000 and 009 to the end of their load images |
| 40 sources, 22 scene harnesses, 7 compiler probes | `src/`, `src/test/`, `probe/` |

Where the rebuild deliberately differs from the original, it is written down: `docs/23-deviations.md` for behaviour, and `status.toml` for every claim the instruments make. Parts 000 and 009 ship with an appended Borland debug tail this reconstruction does not reproduce, which is why those two are compared to the end of their load image rather than whole.

**One file here is not ours.** `NEUROSIS.008` is JCAB's DemoVT, a third-party MOD player that the demo shipped as one of its parts. It is copied, never built; the client side every part links against is reconstructed as `src/DEMOVT.PAS`.

The reusable half of the work lives in [`kit/`](kit), a submodule shared with a second reconstruction: the programs that measure, and the field manual they came out of. Read [`kit/WORKING.md`](kit/WORKING.md) before changing anything, and [`CLAUDE.md`](CLAUDE.md) for how the four jobs in this repository relate.

---

## TL;DR — just watch the demo

Nothing below this section is needed to *look* at it. You need DOSBox-X, twelve of the fifteen files in [`bin/`](bin), and about two minutes.

**1. Get [DOSBox-X](https://dosbox-x.com/).** It is what every run in this repository was watched under, and the configuration below is written for it — `cputype = 486_prefetch` and `gustype` are DOSBox-X options and plain DOSBox will reject them. The demo itself runs under plain DOSBox; you would drop those two lines and use `cputype = 486`.

**2. Copy the demo into a folder of its own — do not run it from `bin/`.** The setup program writes `NEUROSIS.CFG` into whatever directory it is run from, and `bin/` is the 1994 release, which several checks in this repository compare against. Running the demo there silently rewrites one of its files; that has happened once already. From `bin/` you need twelve files:

```
PSYCHO.EXE   NEUROSIS.000 .. NEUROSIS.009   NEUROSIS.DAT
```

`NEUROSIS.CFG` is written by the setup program, so do not bother copying it. `PSYCHO.NFO` and `FILE_ID.DIZ` are the release notes.

**3. Save this as `psycho.conf` next to it**, changing only the mount line:

```ini
[dosbox]
machine  = svga_s3
memsize  = 16

[cpu]
core    = normal
cputype = 486_prefetch
cycles  = 10000

[dos]
xms              = true
ems              = true
umb              = true
minimum mcb free = 1

[mixer]
rate      = 44100
blocksize = 1024
prebuffer = 50

[sblaster]
sbtype = sbpro2
sbbase = 220
irq    = 7
dma    = 1

[gus]
gus     = true
gustype = classic
gusrate = 48000
gusbase = 240
gusirq  = 5
gusdma  = 3

[autoexec]
mount C /the/folder/you/put/the/demo/in
C:
PSYCHO.EXE
```

Then `dosbox-x -conf psycho.conf`.

**`minimum mcb free = 1` is not optional**, and it is the one line worth understanding. Without it the setup program stops with *"You do not have enough memory to run this demo. You need: 4272 extra bytes free"* and goes no further. DOS reports free conventional memory from the first memory control block, and DOSBox-X's default leaves that block higher than a 1994 program expects; setting it to 1 hands back 11,008 bytes. Measured, not guessed: the setup wants `MemAvail` of at least 591,056 bytes, the configuration above without this line gives it 586,048, and with it 597,056. `shellhigh = true` adds another 3,216 if you want more headroom, but it is not needed.

**`cycles = 10000` with `486_prefetch` is not a guess** — every part of this demo has been watched at that setting and reported indistinguishable from the original. Faster is not better here: these are timing-sensitive effects written for a 486, and `cycles = max` makes several of them run wrong.

**4. Answer the setup, and mind these four answers.** `PSYCHO.EXE` runs a setup program first, which asks for your sound card and then its hardware settings. **Its menu defaults do not match what DOSBox emulates, and accepting them is why the music plays for a moment and then stops.** Pick:

| card | port | IRQ | DMA | rate |
|---|---|---|---|---|
| Sound Blaster, mono or Pro stereo | `$220` | 7 | 1 | `28000` or lower |
| Gravis UltraSound | `$240` | 5 | 3 | `28000` or lower |

Both work. If the music still cuts out, drop the rate to `16000` or `8000`: the mixing is done in software, and at 10000 cycles a 486 has only so much to spare underneath a 320x200 effect.

That is all. The demo runs its seven parts in order and returns you to DOS.

## Building it

You need a real Turbo Pascal. Nothing here emulates the compiler — the whole method rests on running the one the authors ran, so the build stages the sources into a directory, mounts it in DOSBox-X, and drives `TPC.EXE` over it.

**What must already be on the machine**

* **DOSBox-X.**
* **A DOS drive image** holding **Turbo Pascal 7.00** — the default, and a measured choice rather than a preference: 7.01 inserts an 8086 check into the runtime's coprocessor block that the 1994 binaries do not carry. 7.01, 6.01 and 6.00 are optional; the probes compile against all four to settle whether a claimed difference is really the compiler's. Turbo Assembler too — `DEMOMATH.ASM` needs 386 instructions TP7's built-in assembler will not emit.
* **Python 3.11 or later**, and [uv](https://docs.astral.sh/uv/).

**Setting up**

```
git submodule update --init kit
uv venv .venv
uv pip install --python .venv/Scripts/python.exe pyyaml capstone
.venv/Scripts/python.exe kit/tools/wizard.py --write
```

The last line is the kit's setup wizard. It proposes every answer, confirms each one, and writes two files: `kit.toml`, which says where things are in this repository and is committed; and `kit.local.toml`, which holds the paths to *your* DOSBox-X, *your* drive image and *your* compilers, and which git ignores. **No machine path belongs in a committed file** — that rule is why the DOSBox configuration is generated rather than kept.

**Building**

```
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml          everything
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml NEUR3    one target
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml --selftest
```

Start with `--selftest`: it compiles a ten-line program and proves the toolchain is reachable. It exists because DOS does not set an error level when it cannot find a command, so a build whose compiler path is wrong will otherwise report success having compiled nothing.

**Read the exit code before you read a byte.** The build lints first and refuses before compiling, and a refusal installs nothing — which means the previous build's executables are still sitting in `run/` and will compare byte-identical. That has produced a clean-looking pass over stale output twice in this repository.

Where things land:

```
build/          the sources the build was given, staged flat under 8.3 names
build/ASM/      src/asm copied verbatim; TASM is run over it
build/GEN/      the generated includes
build/BIN/      what the build made: .OBJ .TPU .MAP .EXE
run/            the load images, installed under the originals' names,
                plus the 22 scene harnesses
```

The switch line in `build.toml` is the part to be careful with, because getting it wrong does not fail — it produces a build that *measures* wrong. `/$S-` is the one that bites: with stack checking on, every framed procedure opens with seven extra bytes and every hand-transcribed routine differs from the binary in its opening bytes.

**Checking it**

```
.venv/Scripts/python.exe kit/tools/pascal/artefact.py status.toml --check
.venv/Scripts/python.exe kit/tools/pascal/routines.py
.venv/Scripts/python.exe kit/tools/pascal/spans.py spans.toml
.venv/Scripts/python.exe kit/tools/pascal/unitorder.py spans.toml
.venv/Scripts/python.exe tools/package.py --check
```

`kit/WORKING.md` section 4 has the full list and the order to run it in. **Run a full build first.** Several of these read what the build made -- `unitorder` reads the compiler's `.MAP` files out of `build/BIN` -- and `--selftest`, `codegen.py` and `probecheck.py` all share the staging directory and empty it on entry. A check that finds nothing there says `NOT MEASURED`, which is the honest answer and not a defect in the sources.

---

## Running it

Building produces load images. The demo shipped as those images with a ProTracker module appended past each one, so there is a packaging step:

```
.venv/Scripts/python.exe tools/mkdat.py --out run --out dist
.venv/Scripts/python.exe tools/package.py
```

`mkdat.py` builds `NEUROSIS.DAT` from `assets/NEUROSIS.MAN` — it is never copied from the original, and it comes out identical to the shipped blob, all 1,718,189 bytes. `package.py` assembles `dist/`: each part with its module appended, `NEUROSIS.008` copied, `PSYCHO.EXE`, and the three tools below. It then compares every file against `bin/` and says so.

**Starting a session**

```
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml --interactive
```

This writes `tools/dosbox/MOUNTS.CFG` — the drives, the DOS-side `PATH`, and a banner — and prints the DOSBox-X command. The mounts are generated so that `tools/dosbox/interactive.conf`, which is a few hundred hand-tuned settings and *is* committed, holds no machine path. Pass both files:

```
dosbox-x -conf tools/dosbox/interactive.conf -conf tools/dosbox/MOUNTS.CFG
```

The overlay goes second. `run.bat` at the root does this for you; it is not in source control, because it holds this machine's paths deliberately.

You land on `E:`:

```
C:  the compilers
D:  build   the staging directory
E:  dist    the packaged demo
R:  run     the load images and the scene harnesses
```

| type this | and you get |
|---|---|
| `PSYCHO` | the launcher, as it shipped: setup, then the demo, then the end screen |
| `RUNPART n` | one part on its own, `n` = 1 to 7, with its music |
| `LOADPART f` | any file DOS will not start by name |
| `R:` then `TP1S1` | one scene on its own, through its harness |

`LOADPART` earns its place: `COMMAND.COM` decides what is executable by extension alone, so `NEUROSIS.001` cannot be typed at a prompt however valid an executable it is. `PSYCHO.EXE` has the same problem and solves it the same way — it EXECs its children by name through `INT 21h/4B00h`, which reads the MZ header and does not care what the file is called.

### Sound

**Run the setup once.** `NEUROSIS.CFG` is an input, not a saved preference: it names the device, the hardware settings, and the byte offset of each part's music inside its own file. Nothing plays until it exists, and the original shipped it saying `/d:Silence`. `PSYCHO.EXE` runs the setup for you; `LOADPART NEUROSIS.000` goes straight to it. The file is written into the current directory, so run it from `E:`.

**The setup's menu defaults do not match what DOSBox emulates, and accepting them is why the music plays for a moment and then stops.** A wrong DMA channel means the completion interrupt never arrives, the buffer is never refilled, and the sound dies after one bufferful. A wrong port can fault outright. Choose:

| | port | IRQ | DMA |
|---|---|---|---|
| **Sound Blaster** (mono or Pro stereo) | `$220` | 7 | 1 |
| **Gravis UltraSound** | `$240` | 5 | 3 |

Those are the values `interactive.conf` emulates — `sbbase`/`irq`/`dma` and `gusbase`/`gusirq`/`gusdma`. The setup asks all four of its questions for GUS as well; only the Silence option skips them. **Confirmed by a watched run on 28 Aug 2026**: with these answers both Sound Blaster and GUS play, which is the only instrument there is for a sound path.

If it still breaks, the cheap discriminator is the mixing rate the setup offers last. Pick `/f:8000` or `/f:16000`. If a low rate survives where a high one does not, the emulated CPU cannot sustain the software mix and `[cpu] cycles` is the answer — it is set to 10000, which is low for a 486-era demo running a mixer under a 320×200 effect. **Raising it changes how fast the demo runs**, which is why it is left alone by default: the pacing work in `status.toml` was observed at this setting.

One setting looks alarming and is not: `gus master volume = 0.00` is in **decibels**, so it is unity gain.

---

## Layout

```
src/            the reconstruction. 8.3 names, part-prefixed and named for what
                they do -- P1BALLS, P3GLOBE, P6WHOOSH
src/asm/        hand-written assembler, and the includes shared between units
src/test/       22 scene harnesses, plus VIDMODE and LOADPART
src/gen/        generated includes, DATOFS.INC among them
probe/          single-question units a compiler answers -- a claimed compiler
                difference is cheap to assert and expensive to chase
assets/         the data, carved from the shipped binaries
bin/            the 1994 release
docs/           the reading, part by part, and the deviations
kit/            the reusable programs and the field manual (submodule)
status.toml     every claim the instruments make: locks, observations, the plan
```
