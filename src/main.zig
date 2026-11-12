const std = @import("std");
const reader = @import("reader.zig");
const report = @import("report.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buf: [4096]u8 = undefined;
    var stdout_impl = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_impl.interface;

    var stderr_buf: [1024]u8 = undefined;
    var stderr_impl = std.Io.File.stderr().writer(io, &stderr_buf);
    const stderr = &stderr_impl.interface;

    if (args.len != 2) {
        try stderr.print("Uso: mbrcli <caminho/para/disco.img>\n", .{});
        try stderr.flush();
        std.process.exit(1);
    }

    const loaded = reader.load(io, args[1]) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print(
                "Erro: arquivo '{s}' não encontrado.\n",
                .{args[1]},
            ),
            error.AccessDenied => try stderr.print(
                "Erro: sem permissão para acessar '{s}'.\n",
                .{args[1]},
            ),
            error.NotRegularFile => try stderr.print(
                "Erro: '{s}' não é um arquivo regular.\n",
                .{args[1]},
            ),
            error.FileTooSmall => try stderr.print(
                "Erro: '{s}' tem menos de 512 bytes; não contém um MBR completo.\n",
                .{args[1]},
            ),
            error.InvalidSignature => try stderr.print(
                "Erro: assinatura MBR inválida em '{s}'; esperado 55 AA nos offsets 510-511.\n",
                .{args[1]},
            ),
            else => try stderr.print(
                "Erro ao ler '{s}': {s}\n",
                .{ args[1], @errorName(err) },
            ),
        }
        try stderr.flush();
        std.process.exit(1);
    };

    try report.writeReport(stdout, args[1], &loaded.mbr, loaded.image_size);
    try stdout.flush();
}
