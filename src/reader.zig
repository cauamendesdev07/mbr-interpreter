const std = @import("std");
const mbr = @import("mbr.zig");

pub const Loaded = struct {
    mbr: mbr.Mbr,
    image_size: u64,
};

/// Lê somente os primeiros 512 bytes da imagem, sem carregar o arquivo inteiro.
/// Rejeita diretórios, dispositivos e outros tipos que não sejam arquivo regular.
pub fn load(io: std.Io, path: []const u8) !Loaded {
    const cwd = std.Io.Dir.cwd();

    const path_stat = try cwd.statFile(io, path, .{});
    if (path_stat.kind != .file) return error.NotRegularFile;
    if (path_stat.size < mbr.mbr_size) return error.FileTooSmall;

    const file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    const file_stat = try file.stat(io);
    if (file_stat.kind != .file) return error.NotRegularFile;
    if (file_stat.size < mbr.mbr_size) return error.FileTooSmall;

    var bytes: [mbr.mbr_size]u8 = undefined;
    const read = try file.readPositionalAll(io, &bytes, 0);
    if (read != mbr.mbr_size) return error.FileTooSmall;

    return .{
        .mbr = try mbr.parse(&bytes),
        .image_size = file_stat.size,
    };
}
