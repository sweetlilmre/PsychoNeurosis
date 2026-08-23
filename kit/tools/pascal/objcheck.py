"""Measure a `{$L}` object module STRICTLY, against the object's own relocations.

WHY A SEPARATE INSTRUMENT. A `.TPU`'s model of an unresolved reference is "the
byte is zero" -- the compiler leaves a hole and the linker fills it. **That is
not true of an assembled module.** TASM resolves what it can and leaves an
ADDEND: `DW OFFSET @@Table` inside the module comes out as the offset from the
module's own start, and `MOV AX,Volumes[2]` comes out as the displacement 2 --
both correct, both waiting on a base the linker adds, and both a flat mismatch
against a binary where the linker already ran.

So the fixup mask cannot be guessed from the bytes. It is READ from the object
file, which records it exactly, and that makes this measurement STRICTER than
the zero rule rather than looser: a byte is excused only because the assembler
said it was a relocation, never because it happens to be zero.

    python kit/tools/pascal/objcheck.py CONFIG.toml
    python kit/tools/pascal/objcheck.py CONFIG.toml --only SOUNDDEV

EVERY RELOCATION FIELD MUST FALL INTO EXACTLY ONE OF THREE CASES, and anything
that falls into none of them is unexplained and fails:

    self-ref      a CODE self-reference. TASM wrote the offset relative to the
                  module, so the original must hold exactly that plus the base.
                  The ARITHMETIC is checked; no zero rule is involved.
    pending       an EXTERNAL or DGROUP symbol our side left as zero. The byte
                  comparison can say nothing about these -- the original holds
                  the variable's DGROUP offset, and where we put that variable
                  is a different risk. Counted and reported, never excused as
                  agreement.
    symbol+addend the same, but with a non-zero addend: `OFFSET Something + n`.
                  Our side holds n alone, so the implied symbol is `orig - ours`
                  and those are grouped. They cannot be verified from the bytes
                  either, but they ARE checkable by hand against the declared
                  variables, and one symbol serving several fields shows as one
                  repeated offset.

A byte that differs and is OUTSIDE every relocation is a stray, and fails. The
tail past the module is linker padding: it is checked to be zero rather than
compared, because there is nothing of ours there to compare.
"""
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[0]))
import project                                    # noqa: E402
import staged                                     # noqa: E402
from substrate import align, omf                  # noqa: E402

try:
    import tomllib
except ModuleNotFoundError:                       # pragma: no cover -- 3.11+
    import tomli as tomllib                       # type: ignore

# An addend is small; a DGROUP offset is not. Anything below this on our side is
# read as `symbol + n` rather than as a value in its own right.
ADDEND_MAX = 0x100


def segment_bytes(original, seg, length, first_para):
    blob = pathlib.Path(original).read_bytes()
    image, _ = align.load_image(blob)
    base = (seg - first_para) * 16
    return image[base:base + length]


def check(name, spec, build, original, first_para, out=sys.stdout):
    """One module. Returns True when every field is explained."""
    seg, size = spec["segment"], spec["length"]
    base, end = spec["from"], spec["to"]

    orig = segment_bytes(original, seg, size, first_para)
    unit = build / (spec.get("unit") or (name + ".TPU"))
    obj = build / (spec.get("object") or (name + ".OBJ"))
    if not unit.exists():
        out.write("  %-9s no %s -- build it first\n" % (name, unit.name))
        return False
    if not obj.exists():
        out.write("  %-9s no %s -- build it first\n" % (name, obj.name))
        return False

    image = unit.read_bytes()
    at, _ = align.locate(orig, image, align.pending)
    if at < 0:
        out.write("  %-9s %s does not contain the segment\n"
                  % (name, unit.name))
        return False
    ours = image[at:at + len(orig) + 256]

    fields = omf.fields(obj)
    covered = {base + off + i
               for off, length in fields.items() for i in range(length)}

    self_refs = pending = 0
    implied = {}
    unexplained = []
    for off in sorted(fields):
        a = base + off
        o = orig[a] | (orig[a + 1] << 8)
        u = ours[a] | (ours[a + 1] << 8)
        if o == (u + base) & 0xFFFF:
            self_refs += 1
        elif u == 0:
            pending += 1
        elif u < ADDEND_MAX:
            implied.setdefault((o - u) & 0xFFFF, []).append(a)
        else:
            unexplained.append((a, o, u))

    stray = [a for a in range(base, end)
             if orig[a] != ours[a] and a not in covered]
    pad = orig[end:size]
    pad_ok = not pad or set(pad) == {0}
    ok = not unexplained and not stray and pad_ok

    out.write("  %-9s %04x  module %04x..%04x  %3d field(s): %3d self-ref, "
              "%3d pending, %2d symbol+addend  %s\n"
              % (name, seg, base, end - 1, len(fields), self_refs, pending,
                 sum(len(v) for v in implied.values()),
                 "OK" if ok else "FAILED"))
    for sym in sorted(implied):
        out.write("      implies a DGROUP symbol at %04x, used by %d field(s): "
                  "%s\n" % (sym, len(implied[sym]),
                            " ".join("%04x" % a for a in implied[sym])))
    for a, o, u in unexplained:
        out.write("      %04x  UNEXPLAINED: orig %04x, ours %04x -- neither "
                  "ours+base (%04x) nor a zero our side left pending\n"
                  % (a, o, u, (u + base) & 0xFFFF))
    for a in stray:
        out.write("      %04x  orig %02x  ours %02x  -- OUTSIDE any "
                  "relocation\n" % (a, orig[a], ours[a]))
    if not pad_ok:
        out.write("      %04x..%04x  tail is not all zero\n" % (end, size - 1))
    elif pad:
        out.write("      %04x..%04x  %d byte(s) of linker padding, all zero\n"
                  % (end, size - 1, len(pad)))
    return ok


def main(argv):
    args = project.positionals(argv[1:], ("--only", "--build", "--original",
                                          "--sources"))

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    if not args:
        sys.stdout.write("usage: objcheck.py CONFIG.toml [--only NAME] "
                         "[--build DIR] [--original FILE]\n")
        return 2
    with io.open(args[0], "rb") as fh:
        cfg = tomllib.load(fh)
    try:
        build = pathlib.Path(opt("build") or project.path("layout.build"))
        original = opt("original") or project.path("target.image")
        first = project.get("target.first_para", quiet=True)
    except project.Missing as exc:
        return project.complain(exc)

    only = opt("only")
    sources = opt("sources") or cfg.get("sources")
    bad = 0
    for name, spec in sorted(cfg.get("module", {}).items()):
        if only and only.upper() not in name.upper():
            continue
        # A stale unit reports on code that is no longer the source, so it is
        # refused rather than measured -- see staged.py.
        if sources:
            state = staged.state(pathlib.Path(sources) / (name + ".PAS"),
                                 build / (name + ".PAS"),
                                 cfg.get("rewrites", ()))
            if state == "stale":
                sys.stdout.write("  %-9s STALE -- source changed since the "
                                 "build; rebuild\n" % name)
                bad += 1
                continue
        if not check(name, spec, build, original, first):
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
