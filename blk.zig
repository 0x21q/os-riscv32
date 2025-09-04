const std = @import("std");
const mem = @import("memory.zig");
const trap = @import("trap.zig");

pub const SECTOR_SIZE: u32 = 512;
pub const VIRTQ_ENTRY_NUM: u32 = 16;
pub const VIRTIO_BLK_PADDR: u32 = 0x1000_1000;

pub var blk_req_vq: *Virtq = undefined;
pub var blk_req: *VirtioBlkReq = undefined;
pub var blk_req_paddr: usize = 0;
pub var blk_cap: u64 = 0;

// virtio register
pub const VirtioReg = struct {
    const Offset = enum(u32) {
        // register offsets
        magic = 0x00,
        version = 0x04,
        device_id = 0x08,
        guest_page_size = 0x28,
        queue_sel = 0x30,
        queue_num_max = 0x34,
        queue_num = 0x38,
        queue_align = 0x3c,
        queue_pfn = 0x40,
        queue_ready = 0x44,
        queue_notify = 0x50,
        device_status = 0x70,
        device_config = 0x100,
    };

    fn read32(_: *const VirtioReg, off_enum: Offset) u32 {
        const ptr: *volatile u32 = @ptrFromInt(
            VIRTIO_BLK_PADDR + @intFromEnum(off_enum),
        );
        return ptr.*;
    }

    fn read64(_: *const VirtioReg, off_enum: Offset) u64 {
        const ptr: *volatile u64 = @ptrFromInt(
            VIRTIO_BLK_PADDR + @intFromEnum(off_enum),
        );
        return ptr.*;
    }

    fn write32(
        _: *const VirtioReg,
        off_enum: Offset,
        value: u32,
    ) void {
        const offset = @intFromEnum(off_enum);
        const addr: *volatile u32 = @ptrFromInt(VIRTIO_BLK_PADDR + offset);
        addr.* = value;
    }

    fn fetch_or32(
        self: *const VirtioReg,
        off_enum: Offset,
        status_struct: VirtioDevStatus,
    ) void {
        const stat: u7 = @bitCast(status_struct);
        const status: u32 = @as(u32, stat);
        self.write32(off_enum, self.read32(off_enum) | status);
    }
};

// virtio device status bits
pub const VirtioDevStatus = packed struct {
    ack: bool = false,
    driver: bool = false,
    driver_ok: bool = false,
    feat_ok: bool = false,
    _: bool = false,
    needs_reset: bool = false,
    failed: bool = false,
};

// virtqueue descriptor area entry
pub const VirtqDesc = extern struct {
    addr: u64,
    len: u32,
    flags: Flags,
    next: u16,

    // virtqueue descriptor flags
    const Flags = packed struct(u16) {
        f_next: bool = false,
        f_write: bool = false,
        _: u14 = 0,
    };
};

// virtqueue available ring
pub const VirtqAvailRing = extern struct {
    flags: Flags,
    index: u16,
    ring: [VIRTQ_ENTRY_NUM]u16,

    // virtqueue available ring flags
    const Flags = packed struct(u16) {
        no_int: bool = false,
        _: u15 = 0,
    };
};

// virtqueue used ring
pub const VirtqUsedRing = extern struct {
    flags: u16,
    index: u16,
    ring: [VIRTQ_ENTRY_NUM]Elem,

    // virtqueue used ring entry
    const Elem = extern struct {
        id: u32,
        len: u32,
    };
};

// virtqueue device layout
pub const VirtioVirtqLayout = extern struct {
    descs: [VIRTQ_ENTRY_NUM]VirtqDesc,
    avail: VirtqAvailRing,
    used: VirtqUsedRing align(mem.PAGE_SIZE),
};

// virtqueue
pub const Virtq = extern struct {
    base: *VirtioVirtqLayout,
    queue_index: u32,
    used_index: *volatile u16,
    last_used_index: u16,
};

// virtio-blk request
pub const VirtioBlkReq = extern struct {
    // first descriptor
    type: Type,
    reserved: u32,
    sector: u64,
    // second descriptor
    data: [SECTOR_SIZE]u8,
    // third descriptor
    status: u8,

    // virtio block request type
    const Type = enum(u32) {
        in = 0,
        out = 1,
    };
};

pub fn virtio_blk_init() void {
    const reg: VirtioReg = .{};

    if (reg.read32(.magic) != 0x74726976) {
        trap.kernel_panic("virtio: invalid magic value", .{}, @src());
    }
    if (reg.read32(.version) != 0x1) {
        trap.kernel_panic("virtio: invalid version", .{}, @src());
    }
    if (reg.read32(.device_id) != 0x2) {
        trap.kernel_panic("virtio: invalid device id", .{}, @src());
    }

    // virtio device initialization
    reg.write32(.device_status, 0);
    reg.fetch_or32(.device_status, VirtioDevStatus{ .ack = true });
    reg.fetch_or32(.device_status, VirtioDevStatus{ .driver = true });
    reg.fetch_or32(.device_status, VirtioDevStatus{ .feat_ok = true });

    // tells the device the page size to calculate the queue address
    // (PFN * page_size). if unused, the device assumes page_size=1,
    // so PFN value must be the full address
    reg.write32(.guest_page_size, @as(u32, mem.PAGE_SIZE));

    blk_req_vq = virtq_init(0);

    const dev_stat: u7 = @bitCast(VirtioDevStatus{ .driver_ok = true });
    reg.write32(.device_status, @as(u32, dev_stat));

    // get disk capacity
    blk_cap = reg.read64(.device_config) * SECTOR_SIZE;
    trap.io.print(
        "virtio-blk: cap is {d} sectors\n",
        .{blk_cap / SECTOR_SIZE},
    ) catch {};

    const blk_req_size = @sizeOf(VirtioBlkReq);
    const page_count = (blk_req_size + mem.PAGE_SIZE - 1) / mem.PAGE_SIZE;

    blk_req_paddr = (@intFromPtr(mem.kalloc_pages(page_count)));
    blk_req = @ptrFromInt(blk_req_paddr);
}

const RWMode = enum {
    read,
    write,
};

pub fn read_write_sector(buf: []u8, sector: u32, mode: RWMode) void {
    if (sector >= blk_cap / SECTOR_SIZE) {
        trap.io.print(
            "virtio: tried read/write sector={d} to capacity {d}",
            .{ sector, blk_cap / SECTOR_SIZE },
        ) catch {};
        return;
    }

    // setup request
    blk_req.sector = sector;
    blk_req.type =
        if (mode == .write) VirtioBlkReq.Type.out else VirtioBlkReq.Type.in;

    // handle write
    if (mode == .write) {
        const dest = blk_req.data[0..SECTOR_SIZE];
        const src = buf[0..SECTOR_SIZE];
        @memcpy(dest, src);
    }

    // setup all descriptors
    const vq: *Virtq = blk_req_vq;
    const descs = &vq.base.descs;

    descs[0].addr = @as(u64, blk_req_paddr);
    descs[0].len = @sizeOf(u32) * 2 + @sizeOf(u64);
    descs[0].flags = VirtqDesc.Flags{ .f_next = true };
    descs[0].next = 1;

    const data_off = @offsetOf(VirtioBlkReq, "data");
    descs[1].addr = @as(u64, blk_req_paddr + data_off);
    descs[1].len = SECTOR_SIZE;
    const f_next_int: u16 = @bitCast(VirtqDesc.Flags{ .f_next = true });
    const f_write_int: u16 = @bitCast(VirtqDesc.Flags{ .f_write = true });
    descs[1].flags = @bitCast(
        f_next_int | (if (mode == .write) 0 else f_write_int),
    );
    descs[1].next = 2;

    const status_off = @offsetOf(VirtioBlkReq, "status");
    descs[2].addr = @as(u64, blk_req_paddr + status_off);
    descs[2].len = @sizeOf(u8);
    descs[2].flags = VirtqDesc.Flags{ .f_write = true };

    // notify device for new requets
    virtq_kick(vq, 0);

    // busy wait until finished
    while (vq.last_used_index != vq.used_index.*) {
        asm volatile ("nop");
    }

    if (blk_req.status != 0) {
        trap.io.print(
            "virtio: failed read/write sector={d} status={d}",
            .{ sector, blk_req.status },
        ) catch {};
        return;
    }

    // handle read
    if (mode == .read) {
        const dest = buf[0..SECTOR_SIZE];
        const src = blk_req.data[0..SECTOR_SIZE];
        @memcpy(dest, src);
    }
}

fn virtq_init(index: u32) *Virtq {
    const layout_size = @sizeOf(VirtioVirtqLayout);
    const page_count = (layout_size + mem.PAGE_SIZE - 1) / mem.PAGE_SIZE;

    const virtq_paddr: u32 = @intFromPtr(mem.kalloc_pages(page_count));
    const layout: *VirtioVirtqLayout = @ptrFromInt(virtq_paddr);

    const vq_paddr: u32 = @intFromPtr(mem.kalloc_page());
    const vq: *Virtq = @ptrFromInt(vq_paddr);

    vq.* = Virtq{
        .base = layout,
        .queue_index = index,
        .used_index = @ptrCast(&layout.used.index),
        .last_used_index = 0,
    };

    const reg: VirtioReg = .{};
    reg.write32(.queue_sel, index);

    const ret = reg.read32(.queue_pfn);
    if (ret != 0) {
        trap.kernel_panic("virtq already in use", .{}, @src());
    }

    const max: u32 = reg.read32(.queue_num_max);
    if (max == 0) {
        trap.kernel_panic("virtio: queue not available", .{}, @src());
    }

    const actual = if (VIRTQ_ENTRY_NUM <= max) VIRTQ_ENTRY_NUM else max;
    reg.write32(.queue_num, actual);
    reg.write32(.queue_align, @as(u32, 0));
    reg.write32(.queue_pfn, virtq_paddr >> 12);

    return vq;
}

fn virtq_kick(vq: *Virtq, desc_idx: u16) void {
    const avail = &vq.base.avail;
    avail.ring[avail.index % VIRTQ_ENTRY_NUM] = desc_idx;

    avail.index += 1;
    asm volatile ("fence iorw, iorw" ::: "memory");

    const reg: VirtioReg = .{};
    reg.write32(.queue_notify, vq.queue_index);
    vq.last_used_index += 1;
}
