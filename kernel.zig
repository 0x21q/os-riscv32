const cmn = @import("common.zig");
const shdr = @import("scheduler.zig");
const trap = @import("trap.zig");

// getting addresses of symbols defined in linker script
const bss_start = @extern([*]u8, .{ .name = "__bss" });
const bss_end = @extern([*]u8, .{ .name = "__bss_end" });
const stack_top = @extern([*]u8, .{ .name = "__stack_top" });
const heap_start = @extern([*]u8, .{ .name = "__heap" });
const heap_end = @extern([*]u8, .{ .name = "__heap_end" });

export fn kernel_main() noreturn {
    // inner main for error handling
    kernel_internal() catch |err| {
        trap.k_panic("caught error: {s}", .{@errorName(err)}, @src());
    };
    while (true) asm volatile ("wfi");
}

fn kernel_internal() anyerror!void {
    const bss = bss_start[0..(bss_end - bss_start)];
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
        : [stack_top] "r" (stack_top),
    );
}

const PAGE_SIZE = 4096;
var used_bytes: usize = 0;

pub fn alloc_pages(n_pages: usize) []u8 {
    const heap = heap_start[0..(heap_end - heap_start)];
    const alloc_size = n_pages * PAGE_SIZE;

    if (used_bytes + alloc_size > heap.len) {
        trap.k_panic("out of heap memory", .{}, @src());
    }

    const allocated = heap[used_bytes..(used_bytes + alloc_size)];
    used_bytes += alloc_size;

    @memset(allocated, 0);
    return allocated;
}
