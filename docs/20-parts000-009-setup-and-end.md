# Parts 000 and 009 — setup and end screen

## NEUROSIS.000 — the setup program

`NEUR0.PAS` (name recovered from its Borland debug info). 70 functions.

This is the configuration front-end, and it is what **writes `NEUROSIS.CFG`**.
That closes the loop on the launcher: `PSYCHO.EXE` runs this first, then hands
the resulting `@neurosis.cfg` to DemoVT.

### Detection

```
DETECTED :
  VGA Card
  386/486
  Protected mode
  Real mode
```

Consistent with the NFO's warning that the demo needs a 386 and a VGA card, and
with `MEMAVAIL` / `MAXAVAIL` appearing in the debug symbols.

### The menus

```
Please Select your Sound Card:
    Sound Blaster (Mono)      -> /d:DMA-SB-Mono
    Sound Blaster Pro (Stereo)-> /d:DMA-SB-Stereo
    Gravis UltraSound         -> /d:GUS
    SB Pas 16
    No Music                  -> /d:Silence
    Previous Setup
    Exit

Please Select your IRQ setting:   IRQ 7 -> /irq:7,  IRQ 5 -> /irq:5
                                  DMA 0/1/3/5/7 -> /dma:n
                                  210H..270H    -> /port:$nnn
Please Select your Sampling rate:
```

The shipped `NEUROSIS.CFG` begins `/d:Silence`, so whoever last ran setup on
this copy chose **No Music**.

Also present: `Hit 'Y' or 'N'`, `Later, dudes!`, and the banner
`Psycho Neurosis     by ASPHYXIA`.

## NEUROSIS.009 — the end screen

`NEUR9.PAS`. 38 functions, and the smallest part.

Its debug info gives the variable names directly:

| Symbol | Meaning |
|---|---|
| `IMAGEDATA` | the picture |
| `IMAGEDATA_WIDTH` | |
| `IMAGEDATA_LENGTH` | |
| `IMAGEDATA_DEPTH` | |

So the sign-off image is a **typed constant compiled into the executable** —
consistent with the part reading nothing from `NEUROSIS.DAT` (it has no entry
in the asset map) and with its 3,044 bytes of appended debug info.

Uses `INT 10h` once, `INT 21h` nine times, and no port I/O at all — it sets a
mode through the BIOS, draws, waits, and exits.
