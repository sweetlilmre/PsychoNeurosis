//Restores the CS: override on x87 instructions recovered from INT 3Ch traps.
//
//The first version of the emulator fixup rewrote `CD 3C <b>` as `90 9B <b+40>`
//(NOP, WAIT, ESC). That is the right length but drops the segment override, so
//code-segment floating-point literals silently resolved against DS and decoded
//as garbage. The correct form is `9B 2E <b+40>` (WAIT, CS:, ESC).
//
//Patching in place rather than re-importing keeps every name and comment.
//Pass the sites as script args: "seg:off,seg:off,...".
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;

public class FixCsOverride extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        if (a.length == 0 || a[0].isBlank()) { println("no sites given"); return; }

        int fixed = 0, already = 0, unexpected = 0;
        for (String s : a[0].split(",")) {
            Address addr = currentProgram.getAddressFactory().getAddress(s.trim());
            int b0 = getByte(addr) & 0xff;
            int b1 = getByte(addr.add(1)) & 0xff;
            int b2 = getByte(addr.add(2)) & 0xff;

            if (b0 == 0x9B && b1 == 0x2E) { already++; continue; }
            if (b0 != 0x90 || b1 != 0x9B || b2 < 0xD8 || b2 > 0xDF) {
                println(String.format("  unexpected at %s: %02X %02X %02X",
                    s, b0, b1, b2));
                unexpected++;
                continue;
            }

            clearListing(addr, addr.add(2));
            setByte(addr, (byte) 0x9B);
            setByte(addr.add(1), (byte) 0x2E);
            disassemble(addr);
            fixed++;
        }
        println(String.format("%-24s fixed=%-4d already=%-4d unexpected=%d",
            currentProgram.getName(), fixed, already, unexpected));
    }
}
