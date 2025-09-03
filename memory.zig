const trap = @import("trap.zig");

// getting addresses of symbols defined in kernel linker script
pub const _sym_bss_start = @extern([*]u8, .{ .name = "__bss" });
pub const _sym_bss_end = @extern([*]u8, .{ .name = "__bss_end" });
pub const _sym_stack_top = @extern([*]u8, .{ .name = "__stack_top" });
pub const _sym_free_ram_start = @extern([*]u8, .{ .name = "__free_ram" });
pub const _sym_free_ram_end = @extern([*]u8, .{ .name = "__free_ram_end" });
pub const _sym_kernel_base = @extern([*]u8, .{ .name = "__kernel_base" });

// user executable virtual base address
pub const USER_BASE_ADR = 0x1000_0000;
// enables vmem with write to satp
pub const SATP_SV32 = 1 << 31;
// enables hw ints in U-mode (although not handled yet)
pub const SSTATUS_SPIE = 1 << 5;
// common page size
pub const PAGE_SIZE = 0x1000;

// track of used physical ram bytes for kalloc
var used_phys_bytes: usize = 0;

// returns physical address!
pub fn kalloc_page() *anyopaque {
    const free_ram_start: usize = @intFromPtr(_sym_free_ram_start);
    const free_ram_end: usize = @intFromPtr(_sym_free_ram_end);

    if (used_phys_bytes + PAGE_SIZE > free_ram_start - free_ram_end) {
        trap.kernel_panic("out of heap memory", .{}, @src());
    }

    // get address and update used_phys_bytes
    const alloc_paddr = free_ram_start + used_phys_bytes;
    used_phys_bytes += PAGE_SIZE;

    // set allocated memory to 0
    const page_ptr: [*]u8 = @ptrFromInt(alloc_paddr);
    @memset(page_ptr[0..PAGE_SIZE], 0);

    return @ptrFromInt(alloc_paddr);
}

// returns physical address!
pub fn kalloc_pages(count: usize) *anyopaque {
    const free_ram_start: usize = @intFromPtr(_sym_free_ram_start);
    const free_ram_end: usize = @intFromPtr(_sym_free_ram_end);

    const alloc_size = PAGE_SIZE * count;

    if (used_phys_bytes + alloc_size > free_ram_end - free_ram_start) {
        trap.kernel_panic("out of heap memory", .{}, @src());
    }

    // get address and update used_phys_bytes
    const alloc_paddr = free_ram_start + used_phys_bytes;
    used_phys_bytes += alloc_size;

    // set allocated memory to 0
    const page_ptr: [*]u8 = @ptrFromInt(alloc_paddr);
    @memset(page_ptr[0..alloc_size], 0);

    return @ptrFromInt(alloc_paddr);
}

// vmem structures and helper functions are based on the following
// article https://simonsungm.cool/2019/10/20/RISC-V-Page-Table-I/
pub const PTFlags = packed struct(u10) {
    V: bool = false,
    R: bool = false,
    W: bool = false,
    X: bool = false,
    U: bool = false,
    G: bool = false,
    A: bool = false,
    D: bool = false,
    RSW: u2 = 0,
};

pub const PTEntry = packed struct(u32) {
    flags: PTFlags,
    ppn0: u10,
    ppn1: u12,
};

pub const VAddr = packed struct(u32) {
    offset: u12,
    vpn0: u10,
    vpn1: u10,
};

// typically paddr is 34-bit in Sv32 spec, however 16 GB range
// is not necessary for virt device, thus paddr is 32-bit
pub const PAddr = packed struct(u32) {
    offset: u12,
    ppn0: u10,
    ppn1: u10,
};

pub fn map_page(pt1: [*]PTEntry, virt_addr: usize, phys_addr: usize, flags: PTFlags) void {
    if (virt_addr % PAGE_SIZE != 0) {
        trap.kernel_panic("vaddr not aligned", .{}, @src());
    }
    if (phys_addr % PAGE_SIZE != 0) {
        trap.kernel_panic("paddr not aligned", .{}, @src());
    }

    const vaddr: VAddr = @bitCast(virt_addr);

    // check if page table entry is not mapped
    // pt1 pte has no flags since it's not physical page
    if (!pt1[vaddr.vpn1].flags.V) {
        const pt_paddr: PAddr = @bitCast(@intFromPtr(kalloc_page()));
        const pte: PTEntry = pte_from_paddr(pt_paddr, .{});
        pt1[vaddr.vpn1] = pte;
    }

    const pt0_usize = usize_from_pte(pt1[vaddr.vpn1]);
    const pt0: [*]PTEntry = @ptrFromInt(pt0_usize);

    // skip mapped pages
    if (pt0[vaddr.vpn0].flags.V) return;

    const paddr: PAddr = @bitCast(phys_addr);
    pt0[vaddr.vpn0] = pte_from_paddr(paddr, flags);
}

fn pte_from_paddr(paddr: PAddr, flags: PTFlags) PTEntry {
    var pte: PTEntry = undefined;
    pte.flags = flags;
    pte.flags.V = true;

    // map 20-bit ppn from paddr into 22-bit ppn field in pte
    pte.ppn0 = paddr.ppn0;
    pte.ppn1 = @as(u12, paddr.ppn1);
    return pte;
}

fn usize_from_pte(pte: PTEntry) usize {
    const ppn = (@as(u22, pte.ppn1) << 10) | pte.ppn0;
    return @as(usize, ppn) << 12;
}
