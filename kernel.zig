const trap = @import("trap.zig");
const mem = @import("memory.zig");

export fn kernel_main() noreturn {
    // inner main for error handling
    kernel_internal() catch |err| {
        trap.kernel_panic("caught error: {s}", .{@errorName(err)}, @src());
    };
    while (true) asm volatile ("wfi");
}

fn kernel_internal() anyerror!void {
    const bss_start: usize = @intFromPtr(mem._sym_bss_start);
    const bss_end: usize = @intFromPtr(mem._sym_bss_end);
    const bss = mem._sym_bss_start[0..(bss_end - bss_start)];
    @memset(bss, 0);

    // initialize trap handler function
    trap.write_csr("stvec", @intFromPtr(&trap.kernel_trap_entry));

    const fs = @import("fs.zig");
    const tar_header = fs.TarHeader{};
    trap.io.write("{s}", tar_header.name);
    const blk = @import("blk.zig");
    var blk_ctx = blk.VirtioBlkCtx{};
    blk_ctx.virtio_blk_init();

    var buf_store: [mem.PAGE_SIZE]u8 = undefined;
    blk_ctx.read_write_disk((&buf_store)[0..], 0, false);
    try trap.io.print("first sector: {s}", .{buf_store});

    const shdr = @import("scheduler.zig");
    shdr.idle_p = shdr.create_process(undefined);
    shdr.idle_p.pid = 0;
    shdr.idle_p.state = .ready;

    shdr.curr_p = shdr.idle_p;

    const sh = @embedFile("shell.bin");
    _ = shdr.create_process(sh);

    shdr.yield();
    trap.kernel_panic("switched to idle process", .{}, @src());
}

export fn boot() linksection(".text.boot") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernel_main
        :
        : [stack_top] "r" (mem._sym_stack_top),
    );
}
