const std = @import("std");
const blk = @import("blk.zig");
const trap = @import("trap.zig");

const FILES_MAX = 8;
const DISK_SIZE_MAX = align_up(@sizeOf(File) * FILES_MAX, blk.SECTOR_SIZE);

const TarHeader = extern struct {
    name: [100]u8 align(1),
    mode: [8]u8 align(1),
    uid: [8]u8 align(1),
    gid: [8]u8 align(1),
    size: [12]u8 align(1),
    mtime: [12]u8 align(1),
    checksum: [8]u8 align(1),
    type: u8 align(1),
    linkname: [100]u8 align(1),
    magic: [6]u8 align(1),
    version: [2]u8 align(1),
    uname: [32]u8 align(1),
    gname: [32]u8 align(1),
    devmajor: [8]u8 align(1),
    devminor: [8]u8 align(1),
    prefix: [155]u8 align(1),
    padding: [12]u8 align(1),
};

const File = struct {
    used: bool = false,
    name: [100]u8 = [_]u8{0} ** 100,
    data: [1024]u8 = [_]u8{0} ** 1024,
    size: usize = 0,
};

var files = [_]File{.{}} ** FILES_MAX;
var mem_disk_buf = [_]u8{0} ** DISK_SIZE_MAX;

pub fn init(blk_ctx: *blk.VirtioBlkCtx) void {
    // load disk data into the buffer
    for (0..mem_disk_buf.len / blk.SECTOR_SIZE) |sector_id| {
        const sector_offset = sector_id * blk.SECTOR_SIZE;
        blk_ctx.read_write_disk(
            mem_disk_buf[sector_offset..][0..blk.SECTOR_SIZE],
            sector_id,
            .read,
        );
    }

    var offset: usize = 0;
    for (&files) |*file| {
        const hdr: *const TarHeader = @ptrCast(mem_disk_buf[offset..].ptr);

        if (hdr.name[0] == 0x0) break;

        // check magic value
        const ustar = [_]u8{ 'u', 's', 't', 'a', 'r', 0 };
        if (!std.mem.eql(u8, &hdr.magic, &ustar)) {
            trap.kernel_panic(
                "invalid tar header, magic={s}",
                .{hdr.magic},
                @src(),
            );
        }

        // fill file struct
        const size = oct2dec(&hdr.size);
        file.* = .{
            .used = true,
            .name = hdr.name,
            .size = size,
        };
        const tar_data = mem_disk_buf[mem_disk_buf.len..][0..size];
        @memcpy(&file.data, tar_data);

        trap.io.print(
            "file: {s} size={d}\n",
            .{ file.name, file.size },
        ) catch {};

        offset += align_up(@sizeOf(TarHeader) + size, blk.SECTOR_SIZE);
    }
}

fn oct2dec(oct_chars: *const [12]u8) usize {
    var dec: usize = 0;
    for (oct_chars) |char| {
        if (char < '0' or char > '7') break;
        dec = dec * 8 + (char - '0');
    }
    return dec;
}

fn align_up(value: usize, alignment: usize) usize {
    if (alignment == 0) return value;
    if (@popCount(alignment) != 1) {
        trap.kernel_panic("alignment must be power of two", .{}, @src());
    }
    return (value + alignment - 1) & ~(alignment - 1);
}
