# Host-side GDB script: attach to the QEMU process and watch the emulated MMU.
#
# Usage (inside the lab2 code directory):
#   qemu-system-riscv64 ... -gdb tcp::43210 -S &
#   gdb -q <qemu-binary> -p <qemu-pid> -x tools/gdb/host.gdb
#
# QEMU 4.1.1 source locations:
#   target/riscv/cpu_helper.c : get_physical_address / riscv_cpu_tlb_fill
#   accel/tcg/cputlb.c        : tlb_fill / tlb_set_page_with_attrs
#
# Addresses below are for the current lab2 default (best_fit) build: kern_init
# fetch VA 0xffffffffc02000d6 and the first memset store VA 0xffffffffc0206018
# (edata).  Both are served by the 1 GiB leaf PTE[511] of the boot page table
# (VA 0xffffffffc0205ff8, PA 0x80205ff8).
set pagination off
set confirm off
set breakpoint pending on
set debuginfod enabled off

# QEMU writes to the terminal; do not stop on SIGPIPE caused by a closed reader.
handle SIGPIPE nostop noprint pass

# One-shot logging flags: the same page may be refilled several times.
set $bare_seen = 0
set $code_fill_logged = 0
set $data_fill_logged = 0

# ---------------------------------------------------------------------------
# 1. Bare mode: the first instruction fetch at kern_entry (physical 0x80200000).
#    satp.MODE is still 0, so get_physical_address() returns *physical = addr.
# ---------------------------------------------------------------------------
break tlb_fill if addr == 0x80200000
commands
  silent
  printf "\n[HOST] TLB MISS (Bare fetch): tlb_fill(addr=0x%lx, size=%d, access_type=%d, mmu_idx=%d)\n", (unsigned long)addr, size, access_type, mmu_idx
  bt 3
  continue
end

break riscv_cpu_tlb_fill if address == 0x80200000
commands
  silent
  set $bare_seen = 1
  printf "[HOST] riscv_cpu_tlb_fill(address=0x%lx, access_type=%d, mmu_idx=%d)\n", (unsigned long)address, access_type, mmu_idx
  printf "       satp.MODE is still Bare here; the next branch returns PA=VA\n"
  continue
end

break cpu_helper.c:197 if addr == 0x80200000 && $bare_seen == 1
commands
  silent
  printf "[HOST] Bare branch: satp.MODE=0 -> *physical = addr = 0x%lx (no page walk)\n", (unsigned long)addr
  set $bare_seen = 0
  continue
end

# ---------------------------------------------------------------------------
# 2. Sv39 instruction fetch of kern_init (VA 0xffffffffc02000d6).
#    TLB miss -> tlb_fill -> riscv_cpu_tlb_fill -> get_physical_address
#    -> one-level walk (1 GiB leaf) -> tlb_set_page_with_attrs.
# ---------------------------------------------------------------------------
break tlb_fill if addr == 0xffffffffc02000d6
commands
  silent
  printf "\n[HOST] TLB MISS (Sv39 fetch): tlb_fill(addr=0x%lx, size=%d, access_type=%d, mmu_idx=%d)\n", (unsigned long)addr, size, access_type, mmu_idx
  bt 4
  continue
end

break riscv_cpu_tlb_fill if address == 0xffffffffc02000d6
commands
  silent
  printf "[HOST] riscv_cpu_tlb_fill(address=0x%lx, access_type=%d, mmu_idx=%d)\n", (unsigned long)address, access_type, mmu_idx
  continue
end

break get_physical_address if addr == 0xffffffffc02000d6
commands
  silent
  printf "[HOST] Sv39 walk: get_physical_address(addr=0x%lx, access_type=%d)\n", (unsigned long)addr, access_type
  printf "       satp=0x%lx priv=%d\n", (unsigned long)env->satp, env->priv
  continue
end

break cpu_helper.c:256 if addr == 0xffffffffc02000d6
commands
  silent
  printf "[HOST] level i=%d idx=VPN%d=%ld pte_addr=0x%lx pte=0x%lx (PTE>>10=0x%lx) ptshift=%d\n", i, i, (unsigned long)idx, (unsigned long)pte_addr, (unsigned long)pte, (unsigned long)(pte >> 10), ptshift
  continue
end

break cpu_helper.c:336 if addr == 0xffffffffc02000d6
commands
  silent
  printf "[HOST] leaf: vpn=0x%lx ppn=0x%lx ptshift=%d physical=0x%lx\n", (unsigned long)vpn, (unsigned long)ppn, ptshift, (unsigned long)*physical
  continue
end

break cputlb.c:836 if vaddr_page == 0xffffffffc0200000
commands
  silent
  if $code_fill_logged == 0
    set $code_fill_logged = 1
    printf "[HOST] TLB FILL: vaddr_page=0x%lx paddr=0x%lx index=%d\n", (unsigned long)vaddr_page, (unsigned long)paddr, index
    printf "       tn.addr_read=0x%lx tn.addr_write=0x%lx tn.addr_code=0x%lx tn.addend=0x%lx\n", (unsigned long)tn.addr_read, (unsigned long)tn.addr_write, (unsigned long)tn.addr_code, (unsigned long)tn.addend
  end
  continue
end

# ---------------------------------------------------------------------------
# 3. Sv39 data store to edata (VA 0xffffffffc0206018).  This is another page,
#    so it misses the soft TLB and walks the page table again.
# ---------------------------------------------------------------------------
break tlb_fill if addr == 0xffffffffc0206018
commands
  silent
  printf "\n[HOST] TLB MISS (data store): tlb_fill(addr=0x%lx, size=%d, access_type=%d, mmu_idx=%d)\n", (unsigned long)addr, size, access_type, mmu_idx
  bt 4
  continue
end

break get_physical_address if addr == 0xffffffffc0206018
commands
  silent
  printf "[HOST] Sv39 walk (data): addr=0x%lx access_type=%d satp=0x%lx\n", (unsigned long)addr, access_type, (unsigned long)env->satp
  continue
end

break cpu_helper.c:256 if addr == 0xffffffffc0206018
commands
  silent
  printf "[HOST] level i=%d idx=VPN%d=%ld pte_addr=0x%lx pte=0x%lx (PTE>>10=0x%lx) ptshift=%d\n", i, i, (unsigned long)idx, (unsigned long)pte_addr, (unsigned long)pte, (unsigned long)(pte >> 10), ptshift
  continue
end

break cpu_helper.c:336 if addr == 0xffffffffc0206018
commands
  silent
  printf "[HOST] leaf: vpn=0x%lx ppn=0x%lx ptshift=%d physical=0x%lx\n", (unsigned long)vpn, (unsigned long)ppn, ptshift, (unsigned long)*physical
  continue
end

break cputlb.c:836 if vaddr_page == 0xffffffffc0206000
commands
  silent
  if $data_fill_logged == 0
    set $data_fill_logged = 1
    printf "[HOST] TLB FILL: vaddr_page=0x%lx paddr=0x%lx index=%d\n", (unsigned long)vaddr_page, (unsigned long)paddr, index
    printf "       tn.addr_read=0x%lx tn.addr_write=0x%lx tn.addr_code=0x%lx tn.addend=0x%lx\n", (unsigned long)tn.addr_read, (unsigned long)tn.addr_write, (unsigned long)tn.addr_code, (unsigned long)tn.addend
  end
  continue
end

# Tell the guest-side script that the host breakpoints are installed, then let
# the stopped QEMU process run.  The guest gdb is waiting at kern_entry.
shell touch /tmp/host_ready
continue
