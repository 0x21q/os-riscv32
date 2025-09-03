const std = @import("std");

pub fn build(b: *std.Build) void {
    // build of kernel executable
    const kernel_exe = b.addExecutable(.{
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

    kernel_exe.entry = .disabled;
    kernel_exe.setLinkerScript(b.path("kernel.ld"));
    b.installArtifact(kernel_exe);

    // build of shell executable
    const shell_exe = b.addExecutable(.{
        .name = "shell.elf",
        .root_source_file = b.path("shell.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        }),
        .optimize = .ReleaseSmall,
        .strip = false,
    });

    shell_exe.entry = .disabled;
    shell_exe.setLinkerScript(b.path("user.ld"));
    b.installArtifact(shell_exe);

    // convert shell elf into raw executable (.bin)
    const elf2raw = b.addSystemCommand(&.{
        "llvm-objcopy",
        "--set-section-flags",
        ".bss=alloc,contents",
        "-O",
        "binary",
    });

    elf2raw.addArtifactArg(shell_exe);
    const shell_bin = elf2raw.addOutputFileArg("shell.bin");

    // adds raw executable as importable module in kernel
    // binary, this skips creation of object file from raw
    // exec and moves this from linker job into zig's build
    kernel_exe.root_module.addAnonymousImport(
        "shell.bin",
        .{ .root_source_file = shell_bin },
    );

    // create a tar file from the disk folder contents
    // and use it as load it to drive0 used by block device
    const tar_cmd = b.addSystemCommand(&.{ "tar", "cf" });
    const tar_file = tar_cmd.addOutputFileArg("disk.tar");
    tar_cmd.addArgs(&.{ "--format=ustar", "-C", "disk", "." });

    // configure run command
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv32",
    });

    run_cmd.addArgs(&.{
        "-machine",    "virt",
        "-m",          "256M",
        "-bios",       "default",
        "-serial",     "mon:stdio",
        "--no-reboot", "-nographic",
        "-drive",
    });
    run_cmd.addPrefixedFileArg("id=drive0,format=raw,if=none,file=", tar_file);

    run_cmd.addArgs(&.{
        "-device", "virtio-blk-device,drive=drive0,bus=virtio-mmio-bus.0",
        "-kernel",
    });
    run_cmd.addArtifactArg(kernel_exe);

    run_cmd.step.dependOn(&tar_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run qemu");
    run_step.dependOn(&run_cmd.step);
}
