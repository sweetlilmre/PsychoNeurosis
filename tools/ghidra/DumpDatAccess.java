//Recovers the NEUROSIS.DAT access map: which routine seeks where and reads how much.
//
//The demo has no asset directory -- every part Assigns 'neurosis.dat', Seeks to a
//hardcoded absolute offset and BlockReads a fixed count. Those constants are the
//only asset map that exists, and they are pushed as immediates right before each
//RTL call, so a short backward scan recovers them.
//
//Borland pushes arguments left to right, so the immediates nearest the CALLF are
//the trailing parameters: Seek(f, n) pushes n as high word then low word.
//@category Psycho
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.SegmentedAddress;
import ghidra.program.model.address.SegmentedAddressSpace;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.function.BiConsumer;

public class DumpDatAccess extends GhidraScript {

    private final Map<String, List<String>> rows = new TreeMap<>();

    @Override
    public void run() throws Exception {
        forEachCall("RTL_FileAssign", (site, host) -> add(host, site, "Assign('" + fileName(site, host) + "')"));

        forEachCall("RTL_FileSeek", (site, host) -> {
            List<Integer> imm = pushImms(site, 2);
            String v = "?";
            if (imm.size() == 2 && imm.get(0) != null && imm.get(1) != null) {
                long n = ((long) imm.get(0) << 16) | imm.get(1);
                v = String.format("$%06X = %,d", n, n);
            }
            add(host, site, "Seek(" + v + ")");
        });

        forEachCall("RTL_FileBlockRead", (site, host) -> {
            List<Integer> imm = pushImms(site, 3);
            String v = (!imm.isEmpty() && imm.get(0) != null)
                ? String.format("%,d bytes", imm.get(0)) : "?";
            add(host, site, "BlockRead(" + v + ")");
        });

        println("=== " + currentProgram.getName() + " ===");
        if (rows.isEmpty()) { println("  no neurosis.dat access"); return; }
        for (Map.Entry<String, List<String>> e : rows.entrySet()) {
            println("  " + e.getKey() + ":");
            Collections.sort(e.getValue());
            for (String s : e.getValue()) println("     " + s);
        }
    }

    private void add(Function host, Address site, String what) {
        rows.computeIfAbsent(host == null ? "?" : host.getName(), k -> new ArrayList<>())
            .add(String.format("%-13s %s", site, what));
    }

    /** Immediates from the PUSHes immediately preceding a call, in push order. */
    private List<Integer> pushImms(Address site, int want) {
        List<Integer> out = new ArrayList<>();
        Instruction in = getInstructionAt(site);
        for (int i = 0; i < 12 && in != null && out.size() < want; i++) {
            in = in.getPrevious();
            if (in == null) break;
            if (!in.getMnemonicString().equalsIgnoreCase("PUSH")) continue;
            Object[] ops = in.getOpObjects(0);
            out.add(0, (ops.length == 1 && ops[0] instanceof Scalar)
                ? (int) (((Scalar) ops[0]).getUnsignedValue() & 0xffff) : null);
        }
        return out;
    }

    /** Assign's name argument is a Pascal shortstring at CS:<imm> of the caller. */
    private String fileName(Address site, Function host) {
        if (host == null) return "?";
        try {
            Instruction in = getInstructionAt(site);
            for (int i = 0; i < 10 && in != null; i++) {
                in = in.getPrevious();
                if (in == null) break;
                if (!in.getMnemonicString().equalsIgnoreCase("MOV")) continue;
                if (!in.toString().contains("DI,")) continue;
                Object[] o = in.getOpObjects(1);
                if (o.length != 1 || !(o[0] instanceof Scalar)) continue;
                long off = ((Scalar) o[0]).getUnsignedValue();
                // The literal lives at CS:<off>, i.e. the call site's own
                // segment. Build that address explicitly -- getOffset() on a
                // segmented address is linear, so arithmetic on it lands wrong.
                SegmentedAddress sa = (SegmentedAddress) site;
                SegmentedAddressSpace sp = (SegmentedAddressSpace) sa.getAddressSpace();
                Address base = sp.getAddress(sa.getSegment(), (int) off);
                int len = getByte(base) & 0xff;
                if (len <= 0 || len >= 60) return "?";
                StringBuilder sb = new StringBuilder();
                for (int k = 1; k <= len; k++) sb.append((char) (getByte(base.add(k)) & 0xff));
                return sb.toString();
            }
        } catch (Exception e) {
            return "<err>";
        }
        return "?";
    }

    private void forEachCall(String target, BiConsumer<Address, Function> fn) {
        Function f = null;
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext()) {
            Function c = it.next();
            if (c.getName().equals(target)) { f = c; break; }
        }
        if (f == null) return;
        ReferenceIterator ri =
            currentProgram.getReferenceManager().getReferencesTo(f.getEntryPoint());
        while (ri.hasNext()) {
            Reference r = ri.next();
            if (!r.getReferenceType().isCall()) continue;
            fn.accept(r.getFromAddress(), getFunctionContaining(r.getFromAddress()));
        }
    }
}
