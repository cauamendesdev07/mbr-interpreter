const std = @import("std");
const mbr = @import("../src/mbr.zig");
const report = @import("../src/report.zig");
const helpers = @import("helpers.zig");

const one_mib: u64 = 1024 * 1024;
const image_100_mib: u64 = 206_848 * mbr.sector_size;

fn render(parsed: *const mbr.Mbr, image_size: u64) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    errdefer allocating.deinit();
    try report.writeReport(&allocating.writer, "disco.img", parsed, image_size);
    return allocating.toOwnedSlice();
}

fn parseEntries(entries: []const [mbr.partition_entry_size]u8) !mbr.Mbr {
    const bytes = helpers.makeMbr(entries, .{ 0x55, 0xAA }, 0xA1B2C3D4);
    return mbr.parse(&bytes);
}

test "relatório de MBR válido sem partições" {
    const parsed = try parseEntries(&.{});
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "MBR Inspector") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Assinatura: válida (55 AA)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Identificador do disco: 0xA1B2C3D4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Capacidade da imagem: 1048576 bytes (1.00 MiB)") != null);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, output, "vazia"));
}

test "relatório de uma partição com tamanho em MiB e término em bytes" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x80, 0x83, 2048, 204_800),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, image_100_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Partição 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Inicializável: sim") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Tipo: 0x83 (Linux)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA inicial: 2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Setores: 204800") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset inicial: 1048576 bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Tamanho: 104857600 bytes (100.00 MiB)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA final: 206847") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset final: 105906175 bytes") != null);
}

test "relatório de quatro entradas" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 1, 10),
        helpers.makeEntry(0x00, 0x07, 20, 10),
        helpers.makeEntry(0x00, 0x0B, 40, 10),
        helpers.makeEntry(0x00, 0x0C, 60, 10),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Partição 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Partição 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA inicial: 60") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Tipo: 0x0C (FAT32 (LBA))") != null);
}

test "relatório de MBR protetor de GPT mostra campos e aviso" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0xEE, 1, 2047),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Tipo: 0xEE (MBR protetor de GPT)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Observação: entrada de MBR protetor de GPT") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA inicial: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Setores: 2047") != null);
}

test "relatório de partição estendida identifica o contêiner" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x0F, 1, 10),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Tipo: 0x0F (Partição estendida (LBA))") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Observação: partição estendida") != null);
}

test "relatório de entrada não vazia com setores zero" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 5, 0),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Setores: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA final: n/a") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset final: n/a") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ERRO: entrada não vazia com número de setores igual a zero.") != null);
}

test "relatório de intervalo que inclui o setor 0" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 0, 10),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "ERRO: intervalo LBA inclui o setor 0.") != null);
}

test "relatório de flag de boot inesperada" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x81, 0x83, 1, 10),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Inicializável: flag inválida") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "AVISO: flag de boot inesperada (0x81)") != null);
}

test "relatório mantém cálculos quando a partição ultrapassa a imagem" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 2000, 100),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "ERRO: partição ultrapassa o fim da imagem") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset inicial: 1024000 bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Tamanho: 51200 bytes (0.05 MiB)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "LBA final: 2099") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset final: 1075199 bytes") != null);
}

test "relatório de sobreposição entre partições de dados" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 1, 100),
        helpers.makeEntry(0x00, 0x83, 50, 100),
    };
    const parsed = try parseEntries(&entries);
    const output = try render(&parsed, one_mib);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(
        u8,
        output,
        "AVISO: partições 1 e 2 se sobrepõem (LBAs 1..100 e 50..149).",
    ) != null);
}

test "relatório avisa quando o tamanho não é múltiplo de 512" {
    const parsed = try parseEntries(&.{});
    const output = try render(&parsed, 600);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(
        u8,
        output,
        "Aviso: o tamanho da imagem não é múltiplo de 512 bytes; usando apenas os setores completos (1).",
    ) != null);
}
