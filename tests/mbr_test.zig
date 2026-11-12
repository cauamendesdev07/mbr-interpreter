const std = @import("std");
const mbr = @import("../src/mbr.zig");
const helpers = @import("helpers.zig");

test "assinatura válida e identificador do disco little-endian" {
    const bytes = helpers.makeMbr(&.{}, .{ 0x55, 0xAA }, 0xA1B2C3D4);
    const parsed = try mbr.parse(&bytes);

    try std.testing.expectEqual(@as(u32, 0xA1B2C3D4), parsed.disk_id);
}

test "assinatura inválida é rejeitada" {
    const bytes = helpers.makeMbr(&.{}, .{ 0xAA, 0x55 }, 0);
    try std.testing.expectError(error.InvalidSignature, mbr.parse(&bytes));
}

test "MBR válido sem partições" {
    const bytes = helpers.makeMbr(&.{}, .{ 0x55, 0xAA }, 0x12345678);
    const parsed = try mbr.parse(&bytes);

    for (parsed.entries) |entry| {
        try std.testing.expect(entry.isEmpty());
    }
}

test "uma partição válida" {
    const entry = helpers.makeEntry(0x80, 0x83, 2048, 204_800);
    const bytes = helpers.makeMbr(&.{entry}, .{ 0x55, 0xAA }, 0x12345678);
    const parsed = try mbr.parse(&bytes);
    const decoded = parsed.entries[0];

    try std.testing.expect(!decoded.isEmpty());
    try std.testing.expectEqual(@as(u8, 0x80), decoded.boot_flag);
    try std.testing.expectEqual(@as(u8, 0x83), decoded.partition_type);
    try std.testing.expectEqual(@as(u32, 2048), decoded.start_lba);
    try std.testing.expectEqual(@as(u32, 204_800), decoded.sector_count);
}

test "quatro entradas de partição" {
    const entries = [_][mbr.partition_entry_size]u8{
        helpers.makeEntry(0x00, 0x83, 1, 10),
        helpers.makeEntry(0x00, 0x07, 20, 10),
        helpers.makeEntry(0x00, 0x0B, 40, 10),
        helpers.makeEntry(0x00, 0x0C, 60, 10),
    };
    const bytes = helpers.makeMbr(&entries, .{ 0x55, 0xAA }, 0xDEADBEEF);
    const parsed = try mbr.parse(&bytes);

    try std.testing.expectEqual(@as(u32, 1), parsed.entries[0].start_lba);
    try std.testing.expectEqual(@as(u32, 20), parsed.entries[1].start_lba);
    try std.testing.expectEqual(@as(u32, 40), parsed.entries[2].start_lba);
    try std.testing.expectEqual(@as(u32, 60), parsed.entries[3].start_lba);
    try std.testing.expectEqual(@as(u8, 0x07), parsed.entries[1].partition_type);
    try std.testing.expectEqual(@as(u8, 0x0B), parsed.entries[2].partition_type);
    try std.testing.expectEqual(@as(u8, 0x0C), parsed.entries[3].partition_type);
}

test "entrada vazia não é confundida com partição de tamanho zero" {
    const empty_bytes = helpers.makeMbr(&.{}, .{ 0x55, 0xAA }, 0);
    const empty = try mbr.parse(&empty_bytes);
    try std.testing.expect(empty.entries[0].isEmpty());

    const zero_size = helpers.makeEntry(0x00, 0x83, 5, 0);
    const zero_bytes = helpers.makeMbr(&.{zero_size}, .{ 0x55, 0xAA }, 0);
    const parsed = try mbr.parse(&zero_bytes);
    try std.testing.expect(!parsed.entries[0].isEmpty());
    try std.testing.expectEqual(@as(u32, 0), parsed.entries[0].sector_count);
}

test "conversão little-endian de LBA e número de setores" {
    const entry = helpers.makeEntry(0x00, 0x83, 0x00000800, 0x0000C800);
    const bytes = helpers.makeMbr(&.{entry}, .{ 0x55, 0xAA }, 0);
    const parsed = try mbr.parse(&bytes);

    try std.testing.expectEqual(@as(u32, 2048), parsed.entries[0].start_lba);
    try std.testing.expectEqual(@as(u32, 51_200), parsed.entries[0].sector_count);
}

test "nomes amigáveis dos tipos exigidos" {
    const cases = [_]struct { code: u8, name: []const u8 }{
        .{ .code = 0x07, .name = "HPFS/NTFS/exFAT" },
        .{ .code = 0x0B, .name = "FAT32 (CHS)" },
        .{ .code = 0x0C, .name = "FAT32 (LBA)" },
        .{ .code = 0x82, .name = "Linux swap" },
        .{ .code = 0x83, .name = "Linux" },
        .{ .code = 0x05, .name = "Partição estendida (CHS)" },
        .{ .code = 0x0F, .name = "Partição estendida (LBA)" },
        .{ .code = 0x85, .name = "Partição estendida (Linux)" },
        .{ .code = 0xEE, .name = "MBR protetor de GPT" },
    };

    for (cases) |case| {
        try std.testing.expectEqualStrings(case.name, mbr.partitionTypeName(case.code));
    }

    try std.testing.expectEqualStrings("desconhecido", mbr.partitionTypeName(0x99));
}
