const cmn = @import("common.zig");
const trap = @import("trap.zig");

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
    sp: *usize = undefined,
    k_stack: [16 * 1024]u8 align(4) = undefined,
};

const Context = struct {
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

pub fn create_process(entry_point: *const anyopaque) *PCB {
    // find unused PCB
    var pid: usize = 0;
    const p = for (&procs, 1..) |*p, i| {
        if (p.state == .unused) {
            pid = i;
            break p;
        }
    } else trap.k_panic("No PCB available", .{}, @src());

    // initialize stack pointer
    const k_stack_top: *u8 = &p.k_stack[p.k_stack.len - 1];
    const ctf_offset: usize = @intFromPtr(k_stack_top) - @sizeOf(Context);
    const ctx_ptr: *Context = @ptrFromInt(ctf_offset);
    ctx_ptr.* = .{};

    // when switch_context restores 'ra' and does 'ret'
    ctx_ptr.ra = @intFromPtr(entry_point);

    p.pid = pid;
    p.state = .ready;
    p.sp = @ptrCast(ctx_ptr);
    return p;
}

pub fn yield() void {
    const next_p = for (&procs) |*p| {
        if (p.state == .ready and p.pid > 0) {
            break p;
        }
    } else idle_p;

    asm volatile (
        \\csrw sscratch, %[sscratch]
        :
        : [sscratch] "r" (&next_p.k_stack[next_p.k_stack.len - 1]),
    );

    if (next_p != curr_p) {
        const prev_p = curr_p;
        prev_p.state = .ready;
        next_p.state = .running;
        curr_p = next_p;
        switch_context(&prev_p.sp, &next_p.sp);
    }
}

pub fn proc_A_entry() void {
    cmn.io.print("starting proc A\n", .{}) catch {};
    while (true) {
        cmn.io.print("A\n", .{}) catch {};
        yield();
        for (0..3_000_000_000) |_| asm volatile ("nop");
    }
}

pub fn proc_B_entry() void {
    cmn.io.print("starting proc B\n", .{}) catch {};
    while (true) {
        cmn.io.print("B\n", .{}) catch {};
        yield();
        for (0..3_000_000_000) |_| asm volatile ("nop");
    }
}

// needs to be noinline otherwise compiler breaks this
noinline fn switch_context(prev_sp: **usize, next_sp: **usize) void {
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
