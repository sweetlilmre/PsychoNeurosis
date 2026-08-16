//Prints surviving Borland x87-emulator trap sites as seg:off, one per line.
//Output is consumed by tools/fpfix.py to build the next patch round.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

public class DumpTraps extends GhidraScript {

    @Override
    public void run() throws Exception {
        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext()) {
            Instruction in = ii.next();
            if (!in.getMnemonicString().equalsIgnoreCase("INT")) continue;
            long v;
            try { v = in.getScalar(0).getUnsignedValue(); } catch (Exception e) { continue; }
            if (v < 0x34 || v > 0x3e) continue;
            Address a = in.getAddress();
            // Segmented listing renders as "seg:off"; that is what fpfix.py expects.
            println("TRAP " + a.toString());
        }
    }
}
