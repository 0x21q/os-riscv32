const std = @import("std");
const user = @import("user.zig");
const shdr = @import("scheduler.zig");

pub fn kernel_panic(
    comptime fmt: []const u8,
    args: anytype,
    loc: std.builtin.SourceLocation,
) noreturn {
    var buf: [1024]u8 = undefined;
    const user_msg = std.fmt.bufPrint(&buf, fmt, args) catch {
        io.print(
            "panic: {s}:{d}:{d}: (message formatting failed)",
            .{ loc.file, loc.line, loc.column },
        ) catch {};

        while (true) asm volatile ("wfi");
    };

    io.print("panic: {s}:{d}:{d}: {s}", .{
        loc.file,
        loc.line,
        loc.column,
        user_msg,
    }) catch {};

    while (true) asm volatile ("nop");
}

pub fn kernel_trap_entry() align(4) callconv(.naked) void {
    asm volatile (
        \\csrrw sp, sscratch, sp
        \\addi sp, sp, 4 * -31
        \\sw ra, 4 * 0(sp)
        \\sw gp, 4 * 1(sp)
        \\sw tp, 4 * 2(sp)
        \\sw t0, 4 * 3(sp)
        \\sw t1, 4 * 4(sp)
        \\sw t2, 4 * 5(sp)
        \\sw t3, 4 * 6(sp)
        \\sw t4, 4 * 7(sp)
        \\sw t5, 4 * 8(sp)
        \\sw t6, 4 * 9(sp)
        \\sw a0, 4 * 10(sp)
        \\sw a1, 4 * 11(sp)
        \\sw a2, 4 * 12(sp)
        \\sw a3, 4 * 13(sp)
        \\sw a4, 4 * 14(sp)
        \\sw a5, 4 * 15(sp)
        \\sw a6, 4 * 16(sp)
        \\sw a7, 4 * 17(sp)
        \\sw s0, 4 * 18(sp)
        \\sw s1, 4 * 19(sp)
        \\sw s2, 4 * 20(sp)
        \\sw s3, 4 * 21(sp)
        \\sw s4, 4 * 22(sp)
        \\sw s5, 4 * 23(sp)
        \\sw s6, 4 * 24(sp)
        \\sw s7, 4 * 25(sp)
        \\sw s8, 4 * 26(sp)
        \\sw s9, 4 * 27(sp)
        \\sw s10, 4 * 28(sp)
        \\sw s11, 4 * 29(sp)
        \\
        \\csrr a0, sscratch
        \\sw a0, 4 * 30(sp)
        \\
        \\addi a0, sp, 4 * 31
        \\csrw sscratch, a0
        \\
        \\mv a0, sp
        \\call handle_trap
        \\
        \\lw ra, 4 * 0(sp)
        \\lw gp, 4 * 1(sp)
        \\lw tp, 4 * 2(sp)
        \\lw t0, 4 * 3(sp)
        \\lw t1, 4 * 4(sp)
        \\lw t2, 4 * 5(sp)
        \\lw t3, 4 * 6(sp)
        \\lw t4, 4 * 7(sp)
        \\lw t5, 4 * 8(sp)
        \\lw t6, 4 * 9(sp)
        \\lw a0, 4 * 10(sp)
        \\lw a1, 4 * 11(sp)
        \\lw a2, 4 * 12(sp)
        \\lw a3, 4 * 13(sp)
        \\lw a4, 4 * 14(sp)
        \\lw a5, 4 * 15(sp)
        \\lw a6, 4 * 16(sp)
        \\lw a7, 4 * 17(sp)
        \\lw s0, 4 * 18(sp)
        \\lw s1, 4 * 19(sp)
        \\lw s2, 4 * 20(sp)
        \\lw s3, 4 * 21(sp)
        \\lw s4, 4 * 22(sp)
        \\lw s5, 4 * 23(sp)
        \\lw s6, 4 * 24(sp)
        \\lw s7, 4 * 25(sp)
        \\lw s8, 4 * 26(sp)
        \\lw s9, 4 * 27(sp)
        \\lw s10, 4 * 28(sp)
        \\lw s11, 4 * 29(sp)
        \\lw sp, 4 * 30(sp)
        \\sret
    );
}

const SbiResult = packed struct {
    err: isize,
    value: isize,
};

pub fn sbi_ecall(
    a0_arg: isize,
    a1_arg: isize,
    a2_arg: isize,
    a3_arg: isize,
    a4_arg: isize,
    a5_arg: isize,
    fid_arg: isize,
    eid_arg: isize,
) SbiResult {
    var err_a0: isize = undefined;
    var val_a1: isize = undefined;

    asm volatile ("ecall"
        : [err_a0] "={a0}" (err_a0),
          [val_a1] "={a1}" (val_a1),
        : [a0_arg] "{a0}" (a0_arg),
          [a1_arg] "{a1}" (a1_arg),
          [a2_arg] "{a2}" (a2_arg),
          [a3_arg] "{a3}" (a3_arg),
          [a4_arg] "{a4}" (a4_arg),
          [a5_arg] "{a5}" (a5_arg),
          [fid_arg] "{a6}" (fid_arg),
          [eid_arg] "{a7}" (eid_arg),
        : "memory"
    );

    return .{ .err = err_a0, .value = val_a1 };
}

// defining our own zig writer instead of reimplementing formatting
pub const io: std.io.AnyWriter = .{
    .context = undefined,
    .writeFn = write_fn,
};

fn kernel_putchar(ch: u8) SbiResult {
    return sbi_ecall(ch, 0, 0, 0, 0, 0, 0, 1);
}

fn write_fn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
    for (bytes) |b| {
        const res: SbiResult = kernel_putchar(b);
        if (res.err != 0) return error.SbiError;
    }
    return bytes.len;
}

fn kernel_getchar() isize {
    const res = sbi_ecall(0, 0, 0, 0, 0, 0, 0, 2);
    return res.err;
}

const TrapFrame = extern struct {
    ra: usize,
    gp: usize,
    tp: usize,
    t0: usize,
    t1: usize,
    t2: usize,
    t3: usize,
    t4: usize,
    t5: usize,
    t6: usize,
    a0: usize,
    a1: usize,
    a2: usize,
    a3: usize,
    a4: usize,
    a5: usize,
    a6: usize,
    a7: usize,
    s0: usize,
    s1: usize,
    s2: usize,
    s3: usize,
    s4: usize,
    s5: usize,
    s6: usize,
    s7: usize,
    s8: usize,
    s9: usize,
    s10: usize,
    s11: usize,
    sp: usize,
};

export fn handle_trap(tf: *TrapFrame) void {
    const scause = read_csr("scause");
    const stval = read_csr("stval");
    const user_pc = read_csr("sepc");

    // 0x8 is ecall
    if (scause == 0x8) {
        handle_syscall(tf) catch {};
        write_csr("sepc", user_pc + 4);
    } else {
        kernel_panic(
            "unexpected trap scause={x}, stval={x}, sepc={x}",
            .{ scause, stval, user_pc },
            @src(),
        );
    }
}

fn handle_syscall(tf: *TrapFrame) !void {
    const sysno: user.Syscall_id = @enumFromInt(tf.a3);

    switch (sysno) {
        .putchar => {
            const char: u8 = @intCast(tf.a0);
            try io.writeByte(char);
        },
        .getchar => {
            while (true) {
                const c = kernel_getchar();
                if (c >= 0) {
                    tf.a0 = @intCast(c);
                    break;
                }

                shdr.yield();
            }
        },
        .exit => {
            try io.print("process {d} exited", .{shdr.curr_p.pid});
            shdr.destroy_process();
            shdr.yield();
            kernel_panic("code unreachable", .{}, @src());
        },
        .readfile, .writefile => {
            const filename: [*]u8 = @ptrFromInt(tf.a0);
            const buffer: [*]u8 = @ptrFromInt(tf.a1);
            var len = tf.a2;

            var file = fs.file_lookup(filename) catch {
                io.print("file could not be found\n", .{}) catch {};
                return;
            };

            // sizeof file.data
            if (len > @sizeOf([1024]u8))
                len = @intCast(file.size);

            if (sysno == .writefile) {
                @memcpy(file.data[0..len], buffer);
                file.size = @intCast(len);
                fs.flush();
            } else {
                @memcpy(buffer, file.data[0..len]);
            }

            tf.a0 = len;
        },
    }
}

const fs = @import("fs.zig");

pub fn read_csr(comptime reg: []const u8) usize {
    return asm volatile ("csrr %[ret], " ++ reg
        : [ret] "=r" (-> usize),
    );
}

pub fn write_csr(comptime reg: []const u8, value: usize) void {
    asm volatile ("csrw " ++ reg ++ ", %[value]"
        :
        : [value] "r" (value),
    );
}
