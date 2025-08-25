const mem = @import("memory.zig");

// getting addresses of symbols defined in user linker script
pub const user_stack_top = @extern([*]u8, .{ .name = "__user_stack_top" });

export fn start() linksection(".text.start") callconv(.naked) void {
    asm volatile (
        \\mv sp, %[user_stack_top]
        \\call user_main
        \\call exit
        :
        : [user_stack_top] "r" (user_stack_top),
    );
}

export fn exit() noreturn {
    while (true) asm volatile ("nop");
}

export fn user_main() void {
    while (true) asm volatile ("nop");
}
