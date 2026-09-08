#!/usr/bin/env python3
"""Read and annotate arm64 Simulator UIKit code without copying Apple binaries."""
import argparse, bisect, mmap, re, struct
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_REG, ARM64_OP_MEM

parser=argparse.ArgumentParser()
parser.add_argument('binary')
parser.add_argument('pattern',help='Regex matching symbol names')
parser.add_argument('--names',action='store_true')
args=parser.parse_args()
f=open(args.binary,'rb'); data=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
assert struct.unpack_from('<I',data)[0]==0xfeedfacf, 'Expected a thin arm64 Mach-O'
segments=[]; symbols={}; symbol_names=[]; stub_sections=[]; indirect_offset=None; pos=32
for _ in range(struct.unpack_from('<I',data,16)[0]):
    cmd,size=struct.unpack_from('<II',data,pos)
    if cmd==0x19:
        vm,vmsize,off,filesize=struct.unpack_from('<QQQQ',data,pos+24)
        segments.append((vm,vm+filesize,off))
        for si in range(struct.unpack_from('<I',data,pos+64)[0]):
            section=pos+72+si*80
            addr,length=struct.unpack_from('<QQ',data,section+32)
            flags,first,stride=struct.unpack_from('<III',data,section+64)
            if flags&0xff==8:stub_sections.append((addr,length,first,stride))
    if cmd==0xb:indirect_offset=struct.unpack_from('<I',data,pos+56)[0]
    if cmd==2:
        off,n,stroff,strsize=struct.unpack_from('<IIII',data,pos+8)
        for i in range(n):
            sx,t,se,de,addr=struct.unpack_from('<IBBHQ',data,off+i*16)
            name=data[stroff+sx:data.find(b'\0',stroff+sx)].decode(errors='replace')
            symbol_names.append(name)
            if not se: continue
            symbols.setdefault(addr,[]).append(name)
    pos+=size
if indirect_offset is not None:
    for addr,length,first,stride in stub_sections:
        for i in range(length//stride):
            index=struct.unpack_from('<I',data,indirect_offset+4*(first+i))[0]
            if index<len(symbol_names):symbols.setdefault(addr+i*stride,[]).append('stub:'+symbol_names[index])
addresses=sorted(symbols)
def read(addr,n):
    for start,end,off in segments:
        if start<=addr and addr+n<=end:return data[off+addr-start:off+addr-start+n]
    return b''
def label(addr):return ' | '.join(symbols.get(addr,[]))
md=Cs(CS_ARCH_ARM64,CS_MODE_ARM); md.detail=True
for idx,start in enumerate(addresses):
    names=symbols[start]
    if not any(re.search(args.pattern,s) for s in names): continue
    print(f'\n{start:#x} {" | ".join(names)}')
    if args.names: continue
    end=addresses[idx+1] if idx+1<len(addresses) else start+4
    if end-start>65536: continue
    regs={}
    for ins in md.disasm(read(start,end-start),start):
        annotations=[]; op=ins.operands
        previous=regs.copy()
        _,written=ins.regs_access()
        for reg in written:regs.pop(reg,None)
        if ins.mnemonic in ('bl','b') and op[0].type==ARM64_OP_IMM:
            annotations.append(label(op[0].imm))
        if ins.mnemonic in ('adrp','adr') and len(op)==2:
            regs[op[0].reg]=op[1].imm
        elif ins.mnemonic=='add' and len(op)==3 and op[2].type==ARM64_OP_IMM and op[1].reg in previous:
            regs[op[0].reg]=previous[op[1].reg]+op[2].imm
            annotations.append(label(regs[op[0].reg]))
        elif ins.mnemonic.startswith(('ldr','ldur')) and len(op)>=2 and op[1].type==ARM64_OP_MEM:
            mem=op[1].mem
            if mem.base in previous and mem.index==0:
                addr=previous[mem.base]+mem.disp
                annotations.append(f'[{addr:#x}] '+label(addr))
                b=read(addr,8)
                if b and ins.reg_name(op[0].reg).startswith('d'):
                    annotations.append('double='+str(struct.unpack('<d',b)[0]))
                elif b and ins.reg_name(op[0].reg).startswith('s'):
                    annotations.append('float='+str(struct.unpack('<f',b[:4])[0]))
        if ins.mnemonic=='bl':
            for r in list(regs):
                if ins.reg_name(r) in ['x'+str(i) for i in range(19)]:regs.pop(r,None)
        print(f' {ins.address:#010x} +{ins.address-start:4d} {ins.mnemonic:8s} {ins.op_str:40s}'+(' ; '+'; '.join(x for x in annotations if x) if any(annotations) else ''))
