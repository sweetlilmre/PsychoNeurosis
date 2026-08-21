# The same bytes answer to two different addresses

* [The same bytes answer to two different addresses](observation.md) - the discriminator: which artefact are you holding?
* [Two names from a disassembler's segment listing](disassembler-listing.md) - the address came from the tool's segment map -- a routine listed under two segments, or sitting at or past a segment's computed end
* [Two names from a far-call or far-pointer operand](far-operand.md) - the address is encoded in an instruction or data, and it disagrees with the segment map's name for the same target
