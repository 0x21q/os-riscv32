const std = @import("std");
const user = @import("user.zig");

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
        try user.io.writeAll("$ ");
        var buf = [_]u8{0} ** 1024;

        for (0..buf.len) |i| {
            const c = user.getchar();
            try user.io.writeByte(c);

            if (i == buf.len - 1) {
                try user.io.writeAll("command too long\n");
                continue;
            } else if (c == '\r') { // qemu's debug console newline is \r
                try user.io.writeByte('\n');
                buf[i] = 0x0;
                break;
            } else {
                buf[i] = c;
            }
        }

        interpret_cmd(&buf) catch {
            try user.io.writeAll("error while interpreting command\n");
        };
    }
}

fn interpret_cmd(line_buffer: []u8) !void {
    if (std.mem.eql(u8, line_buffer[0..5], "hello")) {
        try user.io.writeAll("Hello world!\n");
    } else if (std.mem.eql(u8, line_buffer[0..4], "exit")) {
        user.exit();
    } else if (std.mem.eql(u8, line_buffer[0..8], "readfile")) {
        var buffer = [_]u8{0} ** 512;
        _ = user.readfile("./hello.txt", buffer[0..]);
        try user.io.print("{s}\n", .{buffer});
    } else if (std.mem.eql(u8, line_buffer[0..9], "writefile")) {
        var value = "Hello from shell!";
        _ = user.writefile("./hello.txt", value[0..]);
    } else {
        try user.io.writeAll("unknown command\n");
    }
}
