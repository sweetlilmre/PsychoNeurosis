//Reports memory blocks, functions and interrupt usage for a 16-bit DOS part.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.mem.MemoryBlock;
import java.util.Map;
import java.util.TreeMap;

public class ReportLayout extends GhidraScript {

    @Override
    public void run() throws Exception {
        println("=== " + currentProgram.getName() + " ===");
        println("language: " + currentProgram.getLanguageID());
        println("image base: " + currentProgram.getImageBase());

        for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
            println(String.format("  block %-12s %s - %s  %d bytes",
                b.getName(), b.getStart(), b.getEnd(), b.getSize()));
        }

        int nfunc = 0;
        FunctionIterator fi = currentProgram.getFunctionManager().getFunctions(true);
        while (fi.hasNext()) { fi.next(); nfunc++; }
        println("functions: " + nfunc);

        // Real-mode demo code talks to hardware through INTs and port I/O;
        // tallying them is the fastest read on what a part actually does.
        Map<String, Integer> ints = new TreeMap<>();
        Map<String, Integer> ports = new TreeMap<>();
        long ninstr = 0;
        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext()) {
            Instruction in = ii.next();
            ninstr++;
            String m = in.getMnemonicString().toUpperCase();
            if (m.equals("INT")) {
                ints.merge(in.getDefaultOperandRepresentation(0), 1, Integer::sum);
            } else if (m.equals("IN") || m.equals("OUT")) {
                ports.merge(m + " " + in.getDefaultOperandRepresentation(m.equals("OUT") ? 0 : 1),
                            1, Integer::sum);
            }
        }
        println("instructions: " + ninstr);
        println("INT calls: " + ints);
        println("port I/O: " + ports);
    }
}
