const std = @import("std");
const cmn = @import("common.zig");

// getting addresses of symbols defined in user linker script
const _sym_user_stack_top = @extern([*]u8, .{ .name = "__user_stack_top" });

export fn start() linksection(".text.start") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[user_stack_top]
        \\call %[shell]
        :
        : [user_stack_top] "r" (_sym_user_stack_top),
          [shell] "X" (&shell),
    );
}

fn shell() !void {
    while (true) {
        try cmn.io.writeAll("$ ");
        var buf = [_]u8{0} ** 1024;

        for (0..buf.len) |i| {
            const c = cmn.getchar();
            try cmn.io.writeByte(c);

            if (i == buf.len - 1) {
                try cmn.io.writeAll("command too long\n");
                continue;
            } else if (c == '\r') { // qemu's debug console newline is \r
                try cmn.io.writeByte('\n');
                buf[i] = 0x0;
                break;
            } else {
                buf[i] = c;
            }
        }

        interpret_cmd(&buf) catch {
            try cmn.io.writeAll("error while interpreting command\n");
        };
    }
}

fn interpret_cmd(line_buffer: []u8) !void {
    if (std.mem.eql(u8, line_buffer[0..5], "hello")) {
        try cmn.io.writeAll("Hello world!\n");
    } else if (std.mem.eql(u8, line_buffer[0..4], "exit")) {
        cmn.exit();
    } else {
        try cmn.io.writeAll("unknown command\n");
    }
}
