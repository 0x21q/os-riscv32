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
    size_oct: [12]u8 align(1),
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

pub var files = [_]File{.{}} ** FILES_MAX;
var disk_cache = [_]u8{0} ** DISK_SIZE_MAX;

pub fn init() void {
    // load disk data into the buffer
    for (0..disk_cache.len / blk.SECTOR_SIZE) |sector_id| {
        const sector_offset = sector_id * blk.SECTOR_SIZE;
        blk.read_write_sector(
            disk_cache[sector_offset..][0..blk.SECTOR_SIZE],
            sector_id,
            .read,
        );
    }

    var offset: usize = 0;

    for (&files) |*file| {
        const hdr: *const TarHeader = @ptrCast(disk_cache[offset..].ptr);

        if (hdr.name[0] == 0x0)
            break;

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
        const size = octstr2dec(&hdr.size_oct);
        file.* = .{
            .used = true,
            .name = hdr.name,
            .size = size,
        };
        const data_start = offset + @sizeOf(TarHeader);
        const tar_data = disk_cache[data_start .. data_start + size];
        const bytes_to_copy = @min(size, file.data.len);
        @memcpy(file.data[0..bytes_to_copy], tar_data);

        trap.io.print(
            "file: {s} size={d}\n",
            .{ file.name, file.size },
        ) catch {};

        offset += align_up(@sizeOf(TarHeader) + size, blk.SECTOR_SIZE);
    }
}

pub fn flush() void {
    var offset: usize = 0;

    for (&files) |file| {
        if (!file.used)
            continue;

        var hdr: *TarHeader = @ptrCast(disk_cache[offset..].ptr);
        hdr.* = std.mem.zeroInit(TarHeader, .{
            .name = file.name,
            .mode = [8]u8{ '0', '0', '0', '6', '4', '4', 0, 0 },
            .size_oct = dec2octstr(file.size).*,
            .magic = [6]u8{ 'u', 's', 't', 'a', 'r', 0 },
            .version = [2]u8{ '0', '0' },
            .type = '0',
            .checksum = [8]u8{ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
        });

        // checksum
        var sum: usize = 0;
        const hdr_bytes = std.mem.toBytes(hdr);
        for (hdr_bytes) |byte| sum += byte;
        var stream = std.io.fixedBufferStream(hdr.checksum[0..6]);
        std.fmt.formatInt(sum, 8, .upper, .{}, stream.writer()) catch {};
        hdr.checksum[6] = 0;
        hdr.checksum[7] = ' ';

        const data_start = offset + @sizeOf(TarHeader);
        const tar_data = disk_cache[data_start .. data_start + file.size];
        @memcpy(tar_data, file.data[0..file.size]);
        offset += align_up(@sizeOf(TarHeader) + file.size, blk.SECTOR_SIZE);
    }

    // load disk data into the buffer
    for (0..disk_cache.len / blk.SECTOR_SIZE) |sector_id| {
        const sector_offset = sector_id * blk.SECTOR_SIZE;
        blk.read_write_sector(
            disk_cache[sector_offset..][0..blk.SECTOR_SIZE],
            sector_id,
            .write,
        );
    }

    trap.io.print("wrote {d} bytes to disk\n", .{disk_cache.len}) catch {};
}

pub fn file_lookup(lookup: [*]u8) !*File {
    for (&files) |*file| {
        var i: usize = 0;
        while (lookup[i] != 0x0) : (i += 1) {}
        if (std.mem.eql(u8, file.name[0..i], lookup[0..i])) {
            return file;
        }
    }
    return error.FileNotFound;
}

fn octstr2dec(oct_chars: *const [12]u8) usize {
    var dec: usize = 0;
    for (oct_chars) |char| {
        if (char < '0' or char > '7') break;
        dec = dec * 8 + (char - '0');
    }
    return dec;
}

fn dec2octstr(dec: usize) *[12]u8 {
    var octstr: [12]u8 = [_]u8{0} ** 12;
    var i: usize = @sizeOf([12]u8);
    var digit = dec;

    while (i > 0) : (i -= 1) {
        octstr[i - 1] = @intCast((digit % 8) + '0');
        digit /= 8;
    }
    return @ptrCast(&octstr);
}

fn align_up(value: usize, alignment: usize) usize {
    if (alignment == 0) return value;
    if (@popCount(alignment) != 1) {
        trap.kernel_panic("alignment must be power of two", .{}, @src());
    }
    return (value + alignment - 1) & ~(alignment - 1);
}
