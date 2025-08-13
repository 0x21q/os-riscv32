const std = @import("std");

pub fn build(b: *std.Build) void {
    // configure build of an executrable
    const exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("kernel.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        }),
        .optimize = .ReleaseSmall,
        .strip = false,
    });

    exe.entry = .disabled;
    exe.setLinkerScript(b.path("kernel.ld"));
    b.installArtifact(exe);

    // configure run command
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv32",
    });

    run_cmd.addArgs(&.{
        "-machine",    "virt",
        "-bios",       "default",
        "-serial",     "mon:stdio",
        "--no-reboot", "-nographic",
        "-kernel",
    });

    // add kernel.elf as argument for -kernel flag
    run_cmd.addArtifactArg(exe);

    const run_step = b.step("run", "run qemu");
    run_step.dependOn(&run_cmd.step);
}
