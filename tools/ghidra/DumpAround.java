//Dumps instruction context around each INT in a given vector range.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import java.util.ArrayList;
import java.util.List;

public class DumpAround extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        long lo = a.length > 0 ? Long.decode(a[0]) : 0x34;
        long hi = a.length > 1 ? Long.decode(a[1]) : 0x3e;
        int want = a.length > 2 ? Integer.parseInt(a[2]) : 4;

        println("=== " + currentProgram.getName() + " INT " + lo + ".." + hi + " ===");
        List<Instruction> window = new ArrayList<>();
        int shown = 0;
        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext() && shown < want) {
            Instruction in = ii.next();
            window.add(in);
            if (window.size() > 4) window.remove(0);

            if (!in.getMnemonicString().equalsIgnoreCase("INT")) continue;
            long v;
            try { v = in.getScalar(0).getUnsignedValue(); } catch (Exception e) { continue; }
            if (v < lo || v > hi) continue;

            println("--- at " + in.getAddress());
            for (Instruction w : window) {
                println(String.format("    %s  %-24s %s",
                    w.getAddress(), w.toString(), bytesOf(w)));
            }
            Instruction nx = in.getNext();
            for (int k = 0; k < 2 && nx != null; k++, nx = nx.getNext()) {
                println(String.format("    %s  %-24s %s",
                    nx.getAddress(), nx.toString(), bytesOf(nx)));
            }
            shown++;
        }
    }

    private String bytesOf(Instruction in) throws Exception {
        StringBuilder sb = new StringBuilder();
        for (byte b : in.getBytes()) sb.append(String.format("%02x ", b));
        return sb.toString();
    }
}
