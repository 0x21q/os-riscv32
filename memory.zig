const trap = @import("trap.zig");

// getting addresses of symbols defined in linker script
pub const bss_start = @extern([*]u8, .{ .name = "__bss" });
pub const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
pub const stack_top = @extern([*]u8, .{ .name = "__stack_top" });
pub const heap_start = @extern([*]u8, .{ .name = "__heap" });
pub const heap_end = @extern([*]u8, .{ .name = "__heap_end" });
pub const kernel_base = @extern([*]u8, .{ .name = "__kernel_base" });

pub const SATP_SV32 = 1 << 31;
pub const PAGE_SIZE = 0x1000;
var used_bytes: usize = 0;

// returns physical address (but vaddr == paddr now)
pub fn kalloc_page() *anyopaque {
    const heap_start_u: usize = @intFromPtr(heap_start);
    const heap_end_u: usize = @intFromPtr(heap_end);

    if (used_bytes + PAGE_SIZE > heap_end_u - heap_start_u) {
        trap.k_panic("out of heap memory", .{}, @src());
    }

    // get address and update used_bytes
    const alloc_paddr = heap_start_u + used_bytes;
    used_bytes += PAGE_SIZE;

    // set allocated memory to 0
    const page_ptr: [*]u8 = @ptrFromInt(alloc_paddr);
    @memset(page_ptr[0..PAGE_SIZE], 0);

    return @ptrFromInt(alloc_paddr);
}

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

const VAddr = packed struct(u32) {
    offset: u12,
    vpn0: u10,
    vpn1: u10,
};

// typically paddr is 34-bit in Sv32 spec, however 16 GB range
// is not necessary for virt device, thus paddr is 32-bit
const PAddr = packed struct(u32) {
    offset: u12,
    ppn0: u10,
    ppn1: u10,
};

pub fn map_page(pt1: [*]PTEntry, virt_addr: usize, phys_addr: usize, flags: PTFlags) void {
    if (virt_addr % PAGE_SIZE != 0) {
        trap.k_panic("vaddr not aligned", .{}, @src());
    }
    if (phys_addr % PAGE_SIZE != 0) {
        trap.k_panic("paddr not aligned", .{}, @src());
    }

    const vaddr: VAddr = @bitCast(virt_addr);

    // check if page table entry is not mapped
    // pt1 pte has no flags since it's not physical page
    if (!pt1[vaddr.vpn1].flags.V) {
        const pt_paddr: PAddr = @bitCast(@intFromPtr((kalloc_page())));
        const pte: PTEntry = pte_from_paddr(pt_paddr, .{});
        pt1[vaddr.vpn1] = pte;
    }

    const pt0_usize = usize_from_pte(pt1[vaddr.vpn1]);
    const pt0: [*]PTEntry = @ptrFromInt(pt0_usize);

    if (pt0[vaddr.vpn0].flags.V) {
        trap.k_panic("page already mapped", .{}, @src());
    }

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
