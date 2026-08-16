//Reports function count, surviving emulator traps and recovered x87 instructions.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import java.util.Map;
import java.util.TreeMap;

public class FpReport extends GhidraScript {

    @Override
    public void run() throws Exception {
        int nfunc = 0;
        FunctionIterator fi = currentProgram.getFunctionManager().getFunctions(true);
        while (fi.hasNext()) { fi.next(); nfunc++; }

        int traps = 0, fpu = 0;
        long ninstr = 0;
        Map<String, Integer> kinds = new TreeMap<>();

        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext()) {
            Instruction in = ii.next();
            ninstr++;
            String m = in.getMnemonicString().toUpperCase();

            if (m.equals("INT")) {
                try {
                    long v = in.getScalar(0).getUnsignedValue();
                    if (v >= 0x34 && v <= 0x3e) traps++;
                } catch (Exception ignored) { }
            }
            // x87 mnemonics all start with F; WAIT is the paired prefix.
            if (m.startsWith("F") && !m.equals("FS") || m.equals("WAIT")) {
                fpu++;
                kinds.merge(m, 1, Integer::sum);
            }
        }

        println(String.format("%-24s funcs=%-5d instrs=%-6d traps_left=%-4d x87=%d",
            currentProgram.getName(), nfunc, ninstr, traps, fpu));
        if (!kinds.isEmpty()) println("    " + kinds);
    }
}
