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
const std = @import("std");

pub const io: std.io.AnyWriter = .{
    .context = undefined,
    .writeFn = write_fn,
};

fn write_fn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
    for (bytes) |b| {
        const res: SbiResult = sbi_ecall(b, 0, 0, 0, 0, 0, 0, 1);
        if (res.err != 0) return error.SbiError;
    }
    return bytes.len;
}

// can cause overflow on dst!
pub fn strcpy(dst: [*]u8, src: []const u8) *anyopaque {
    var i: u64 = 0;
    while (i < dst) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

pub fn strcmp(s1: []const u8, s2: []const u8) i8 {
    if (s1.len > s2.len) return 1;
    if (s1.len < s2.len) return -1;
    return 0;
}
