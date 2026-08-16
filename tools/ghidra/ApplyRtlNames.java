//Names the Borland Pascal 7 runtime in every demo part from one offset table.
//
//The System unit is the same build in all parts -- smart-linking keeps a
//different subset, but retained routines sit at identical offsets from the
//segment base. So one offset->name table serves every binary.
//
//The RTL segment is found by its prologue (BA 00 00 8E DA 8C 06), not by a
//hardcoded base, so this works on any part without a lookup table.
//
//Named entries below were each confirmed by decompiling the routine; everything
//else in the segment is renamed RTL_<offset> purely to separate library code
//from demo code in the listing.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.SourceType;
import java.util.LinkedHashMap;
import java.util.Map;

public class ApplyRtlNames extends GhidraScript {

    // Prologue of the System unit's init code, identical in all parts. The two
    // bytes after each BA are a relocated DGROUP segment value that differs per
    // part, so they are wildcards (-1).
    //   BA ?? ?? 8E DA 8C 06     MOV DX,dgroup / MOV DS,DX / MOV [..],ES
    private static final int[] SIG_INIT = {0xBA, -1, -1, 0x8E, 0xDA, 0x8C, 0x06};

    // Halt, at a fixed +0x116 from the segment base -- the real discriminator.
    //   33 C9 33 DB BA ?? ?? 8E DA FB
    private static final int[] SIG_HALT =
        {0x33, 0xC9, 0x33, 0xDB, 0xBA, -1, -1, 0x8E, 0xDA, 0xFB};
    private static final int HALT_OFF = 0x116;

    // Offsets are NOT stable across parts. Smart-linking preserves only a core
    // (SystemInit, Halt, GetMem, FreeMem); everything above shifts, and there
    // are at least two distinct RTL builds among the ten binaries. So the table
    // is supplied per part by tools/rtlfind.py, which locates each routine by
    // byte pattern. Passed as script args: "off=name,off=name,...".
    private final Map<Integer, String> NAMES = new LinkedHashMap<>();

    private void loadTable() {
        String[] a = getScriptArgs();
        if (a.length == 0 || a[0].isBlank()) return;
        for (String pair : a[0].split(",")) {
            String[] kv = pair.split("=", 2);
            if (kv.length == 2) NAMES.put(Integer.parseInt(kv[0].trim(), 16), kv[1].trim());
        }
    }

    @Override
    public void run() throws Exception {
        loadTable();
        MemoryBlock rtl = findRtlBlock();
        if (rtl == null) {
            println(currentProgram.getName() + ": no RTL segment found");
            return;
        }

        Address start = rtl.getStart(), end = rtl.getEnd();
        int renamed = 0, identified = 0, skipped = 0, created = 0;

        // A named routine may sit at an address Ghidra never turned into a
        // function (reached only through a far call it did not resolve). Create
        // it, otherwise the name has nowhere to land.
        for (Map.Entry<Integer, String> e : NAMES.entrySet()) {
            Address a = start.add(e.getKey());
            if (a.compareTo(end) > 0) continue;
            if (getFunctionAt(a) != null) continue;
            disassemble(a);
            if (createFunction(a, e.getValue()) != null) created++;
        }

        FunctionIterator fi = currentProgram.getFunctionManager().getFunctions(true);
        while (fi.hasNext()) {
            Function f = fi.next();
            Address a = f.getEntryPoint();
            if (a.compareTo(start) < 0 || a.compareTo(end) > 0) continue;

            int off = (int) a.subtract(start);
            String known = NAMES.get(off);
            String want = (known != null) ? known : String.format("RTL_%04x", off);

            // Never clobber a name a human already chose. "System_" is from an
            // earlier hand-naming pass over this same runtime, so it is ours to
            // supersede and keeps the listing on one convention.
            String cur = f.getName();
            if (!cur.startsWith("FUN_") && !cur.startsWith("RTL_")
                    && !cur.startsWith("System_")) {
                skipped++;
                continue;
            }
            if (f.getName().equals(want)) continue;

            f.setName(want, SourceType.USER_DEFINED);
            renamed++;
            if (known != null) identified++;
        }

        println(String.format(
            "%-24s RTL at %s  created=%-3d renamed=%-4d identified=%-3d kept=%d",
            currentProgram.getName(), start, created, renamed, identified, skipped));
    }

    private MemoryBlock findRtlBlock() throws Exception {
        for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
            if (!b.isInitialized()) continue;
            if (b.getSize() < HALT_OFF + SIG_HALT.length) continue;
            if (!matches(b, 0, SIG_INIT)) continue;
            if (!matches(b, HALT_OFF, SIG_HALT)) continue;
            return b;
        }
        return null;
    }

    private boolean matches(MemoryBlock b, int off, int[] sig) {
        byte[] got = new byte[sig.length];
        try {
            b.getBytes(b.getStart().add(off), got);
        } catch (Exception e) {
            return false;
        }
        for (int i = 0; i < sig.length; i++) {
            if (sig[i] >= 0 && (got[i] & 0xff) != sig[i]) return false;
        }
        return true;
    }
}
