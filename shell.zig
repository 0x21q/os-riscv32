const cmn = @import("common.zig");

// getting addresses of symbols defined in user linker script
const user_stack_top = @extern([*]u8, .{ .name = "__user_stack_top" });

export fn start() linksection(".text.start") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[user_stack_top]
        \\call %[shell]
        :
        : [user_stack_top] "r" (user_stack_top),
          [shell] "X" (&shell),
    );
}

fn shell() void {
    while (true) {
        cmn.io.print("{c}", .{cmn.getchar()}) catch {};
    }
    while (true) asm volatile ("nop");
}
