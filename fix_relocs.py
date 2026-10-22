#!/usr/bin/env python3
"""Make x86-64 kernel modules loadable by Linux 3.10's module loader.

  fix_relocs.py module.ko [module.ko ...]

Modern binutils emit R_X86_64_PLT32 for `call foo`. Linux before 4.16 rejects that
type ("Unknown rela relocation: 4", insmod: "Invalid module format"). Kernel modules
have no PLT, so PLT32 resolves exactly like R_X86_64_PC32 (upstream commit
b21ebf2fb4cd "x86: Treat R_X86_64_PLT32 as R_X86_64_PC32"); this rewrites the type
in place. GOT-based relocations can't be rewritten this way, so they are an error:
build with -fno-pic/-fno-pie and without -fno-plt.

Standard library only (runs on the CentOS 7 image's Python 3.6).
"""

import struct
import sys

SHT_RELA = 4
R_X86_64_PC32 = 2
R_X86_64_PLT32 = 4
GOT_TYPES = {9: "GOTPCREL", 41: "GOTPCRELX", 42: "REX_GOTPCRELX"}


def fix(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        sys.exit("%s: not a 64-bit little-endian ELF file" % path)
    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x3A)

    fixed = 0
    bad = {}
    for i in range(e_shnum):
        sh = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", data, sh + 4)
        if sh_type != SHT_RELA:
            continue
        sh_offset, sh_size = struct.unpack_from("<QQ", data, sh + 0x18)
        sh_entsize, = struct.unpack_from("<Q", data, sh + 0x38)
        for off in range(sh_offset, sh_offset + sh_size, sh_entsize or 24):
            info, = struct.unpack_from("<Q", data, off + 8)
            rtype = info & 0xFFFFFFFF
            if rtype == R_X86_64_PLT32:
                struct.pack_into("<Q", data, off + 8, (info & ~0xFFFFFFFF) | R_X86_64_PC32)
                fixed += 1
            elif rtype in GOT_TYPES:
                bad[GOT_TYPES[rtype]] = bad.get(GOT_TYPES[rtype], 0) + 1

    if bad:
        sys.exit("%s: has GOT relocations Linux 3.10 can't load (%s); build without "
                 "-fno-plt and with -fno-pic" % (path, ", ".join("%d %s" % (n, t) for t, n in sorted(bad.items()))))
    with open(path, "wb") as f:
        f.write(data)
    print("%s: rewrote %d R_X86_64_PLT32 relocation(s) as R_X86_64_PC32" % (path, fixed))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for p in sys.argv[1:]:
        fix(p)
