const cmn = @import("common.zig");
const trap = @import("trap.zig");
const mem = @import("memory.zig");
const blk = @import("blk.zig");

pub var procs = [_]PCB{.{}} ** 8; // available pcbs
pub var curr_p: *PCB = undefined; // running process
pub var idle_p: *PCB = undefined; // idle process

const PCB = struct {
    pid: usize = 0,
    state: enum {
        unused,
        ready,
        running,
    } = .unused,
    sp: [*]usize = undefined, // stack pointer
    pt: [*]mem.PTEntry = undefined, // page table pointer
    kernel_stack: [16 * 1024]u8 align(4) = undefined,
};

const Context = packed struct {
    ra: usize = 0,
    s0: usize = 0,
    s1: usize = 0,
    s2: usize = 0,
    s3: usize = 0,
    s4: usize = 0,
    s5: usize = 0,
    s6: usize = 0,
    s7: usize = 0,
    s8: usize = 0,
    s9: usize = 0,
    s10: usize = 0,
    s11: usize = 0,
};

pub fn create_process(image: []const u8) *PCB {
    // find unused PCB
    var pid: usize = 0;
    const p = for (&procs, 1..) |*p, i| {
        if (p.state == .unused) {
            pid = i;
            break p;
        }
    } else trap.kernel_panic("No PCB available", .{}, @src());

    // initialize stack pointer
    const kernel_stack_top: *u8 = &p.kernel_stack[p.kernel_stack.len - 1];
    const ctx_offset: usize = @intFromPtr(kernel_stack_top) - @sizeOf(Context);
    const ctx_ptr: *Context = @ptrFromInt(ctx_offset);
    ctx_ptr.* = .{};

    // when switch_context restores 'ra' and does 'ret'
    ctx_ptr.ra = @intFromPtr(&user_entry);

    // map kernel pages
    const pt: [*]mem.PTEntry = @alignCast(@ptrCast(mem.kalloc_page()));
    var page_paddr: usize = @intFromPtr(mem.kernel_base);
    const heap_end_u: usize = @intFromPtr(mem.heap_end);

    while (page_paddr < heap_end_u) : (page_paddr += mem.PAGE_SIZE) {
        mem.map_page(
            pt,
            page_paddr,
            page_paddr,
            mem.PTFlags{ .R = true, .W = true, .X = true },
        );
    }

    // map mmio page
    mem.map_page(
        pt,
        blk.VIRTIO_BLK_PADDR,
        blk.VIRTIO_BLK_PADDR,
        mem.PTFlags{ .R = true, .W = true },
    );

    // map image pages
    var off: usize = 0;
    while (off < image.len) : (off += mem.PAGE_SIZE) {
        const page_paddr_ptr: [*]u8 = @ptrCast(mem.kalloc_page());

        // handle the end of the image
        const remain = image.len - off;
        const copy_size =
            if (mem.PAGE_SIZE <= remain) mem.PAGE_SIZE else remain;

        // copy pages of image from kernel's memory into newly allocated
        // physical pages which are mapped to virtual pages right after
        @memcpy(
            page_paddr_ptr[0..copy_size],
            image[off..(off + copy_size)],
        );
        mem.map_page(
            pt,
            mem.USER_BASE_ADR + off,
            @intFromPtr(page_paddr_ptr),
            // defined as user page (U flag)
            .{ .R = true, .W = true, .X = true, .U = true },
        );
    }

    p.pid = pid;
    p.state = .ready;
    p.sp = @ptrCast(&ctx_ptr.ra);
    p.pt = pt;
    return p;
}

pub fn destroy_process() void {
    curr_p.pid = 0;
    curr_p.state = .unused;
    curr_p.sp = undefined;
    curr_p.kernel_stack = undefined;
    curr_p.pt = undefined;
}

pub fn yield() void {
    // look for another process or continue current
    const next_p = for (&procs) |*p| {
        if (p.state == .ready and p.pid > 0) {
            break p;
        }
    } else if (curr_p.state == .unused) idle_p else curr_p;

    // (>> 12) == (/ PAGE_SIZE)
    const next_satp = mem.SATP_SV32 | (@intFromPtr(next_p.pt) >> 12);
    const next_kernel_sp =
        &next_p.kernel_stack[0..].ptr[next_p.kernel_stack.len];

    // sfence.vma clears tlb
    // writing to satp SATP_SV32 enables vmem
    asm volatile (
        \\sfence.vma
        \\csrw satp, %[satp]
        \\sfence.vma
        \\csrw sscratch, %[sscratch]
        :
        : [satp] "r" (next_satp),
          [sscratch] "r" (next_kernel_sp),
    );

    const prev_p = curr_p;
    prev_p.state = .ready;
    next_p.state = .running;
    curr_p = next_p;
    switch_context(&prev_p.sp, &next_p.sp);
}

fn user_entry() callconv(.naked) void {
    asm volatile (
        \\csrw sepc, %[sepc]
        \\csrw sstatus, %[sstatus]
        \\sret
        :
        : [sepc] "r" (mem.USER_BASE_ADR),
          [sstatus] "r" (mem.SSTATUS_SPIE),
    );
}

// needs to be noinline otherwise compiler breaks this
noinline fn switch_context(prev_sp: *[*]usize, next_sp: *[*]usize) void {
    asm volatile (
        \\
        // save ctx registers of current process
        \\addi sp, sp, 4 * -13
        \\sw ra,  4 * 0(sp)
        \\sw s0,  4 * 1(sp)
        \\sw s1,  4 * 2(sp)
        \\sw s2,  4 * 3(sp)
        \\sw s3,  4 * 4(sp)
        \\sw s4,  4 * 5(sp)
        \\sw s5,  4 * 6(sp)
        \\sw s6,  4 * 7(sp)
        \\sw s7,  4 * 8(sp)
        \\sw s8,  4 * 9(sp)
        \\sw s9,  4 * 10(sp)
        \\sw s10, 4 * 11(sp)
        \\sw s11, 4 * 12(sp)
        // change sp to next process
        \\sw sp, (%[prev_sp])
        \\lw sp, (%[next_sp])
        // restore ctx registers of next process
        \\lw ra,  4 * 0(sp)
        \\lw s0,  4 * 1(sp)
        \\lw s1,  4 * 2(sp)
        \\lw s2,  4 * 3(sp)
        \\lw s3,  4 * 4(sp)
        \\lw s4,  4 * 5(sp)
        \\lw s5,  4 * 6(sp)
        \\lw s6,  4 * 7(sp)
        \\lw s7,  4 * 8(sp)
        \\lw s8,  4 * 9(sp)
        \\lw s9,  4 * 10(sp)
        \\lw s10, 4 * 11(sp)
        \\lw s11, 4 * 12(sp)
        \\addi sp, sp, 13 * 4
        \\ret
        :
        : [prev_sp] "r" (prev_sp),
          [next_sp] "r" (next_sp),
    );
}
