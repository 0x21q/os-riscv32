const std = @import("std");

pub const Syscall_id = enum(usize) {
    putchar = 1,
    getchar = 2,
    exit = 3,
    readfile = 4,
    writefile = 5,
};

pub fn syscall(
    number: Syscall_id,
    arg0: usize,
    arg1: usize,
    arg2: usize,
) usize {
    return asm volatile ("ecall"
        : [ret] "={a0}" (-> usize),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [number] "{a3}" (number),
        : "memory"
    );
}

pub const io: std.io.AnyWriter = .{
    .context = undefined,
    .writeFn = write_fn,
};

fn putchar(ch: u8) void {
    _ = syscall(.putchar, @intCast(ch), 0, 0);
}

pub fn getchar() u8 {
    return @intCast(syscall(.getchar, 0, 0, 0));
}

fn write_fn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
    for (bytes) |b| {
        putchar(b);
    }
    return bytes.len;
}

pub fn exit() noreturn {
    _ = syscall(.exit, 0, 0, 0);
    while (true) asm volatile ("nop");
}

pub fn readfile(filename: []const u8, buffer: []u8) usize {
    const name_addr: usize = @intFromPtr(filename.ptr);
    const buf_addr: usize = @intFromPtr(buffer.ptr);
    return syscall(.readfile, name_addr, buf_addr, buffer.len);
}

pub fn writefile(filename: []const u8, buffer: []const u8) usize {
    const name_addr: usize = @intFromPtr(filename.ptr);
    const buf_addr: usize = @intFromPtr(buffer.ptr);
    return syscall(.writefile, name_addr, buf_addr, buffer.len);
}
