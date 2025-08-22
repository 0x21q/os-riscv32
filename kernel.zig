const cmn = @import("common.zig");
const shdr = @import("scheduler.zig");
const trap = @import("trap.zig");
const mem = @import("memory.zig");

export fn kernel_main() noreturn {
    // inner main for error handling
    kernel_internal() catch |err| {
        trap.k_panic("caught error: {s}", .{@errorName(err)}, @src());
    };
    while (true) asm volatile ("wfi");
}

fn kernel_internal() anyerror!void {
    const bss = mem.bss_start[0..(mem.bss_end - mem.bss_start)];
    @memset(bss, 0);

    // initialize trap handler function
    trap.write_csr("stvec", @intFromPtr(&trap.k_trap_entry));

    shdr.idle_p = shdr.create_process(undefined);
    shdr.idle_p.pid = 0;
    shdr.idle_p.state = .ready;

    shdr.curr_p = shdr.idle_p;

    _ = shdr.create_process(&shdr.proc_A_entry);
    _ = shdr.create_process(&shdr.proc_B_entry);

    shdr.yield();
    trap.k_panic("switched to idle process", .{}, @src());
}

export fn boot() linksection(".text.boot") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernel_main
        :
        : [stack_top] "r" (mem.stack_top),
    );
}
