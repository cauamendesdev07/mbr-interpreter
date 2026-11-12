const std = @import("std");
const partition = @import("../src/partition.zig");
const reader = @import("../src/reader.zig");
const report = @import("../src/report.zig");

fn loadFixture(path: []const u8) !reader.Loaded {
    return reader.load(std.testing.io, path);
}

fn renderFixture(loaded: *const reader.Loaded, path: []const u8) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    errdefer allocating.deinit();
    try report.writeReport(&allocating.writer, path, &loaded.mbr, loaded.image_size);
    return allocating.toOwnedSlice();
}

test "fixture: MBR válido sem partições" {
    const loaded = try loadFixture("fixtures/teste-mbr-vazio.img");

    try std.testing.expectEqual(@as(u64, 512), loaded.image_size);
    for (loaded.mbr.entries) |entry| {
        try std.testing.expect(entry.isEmpty());
    }
}

test "fixture: identificador do disco em little-endian" {
    const loaded = try loadFixture("fixtures/teste-mbr-id.img");
    try std.testing.expectEqual(@as(u32, 0x12345678), loaded.mbr.disk_id);
}

test "fixture: uma partição válida" {
    const loaded = try loadFixture("fixtures/teste-mbr-particao.img");
    const entry = loaded.mbr.entries[0];

    try std.testing.expect(!entry.isEmpty());
    try std.testing.expectEqual(@as(u8, 0x83), entry.partition_type);
    try std.testing.expectEqual(@as(u32, 1), entry.start_lba);
    try std.testing.expectEqual(@as(u32, 100), entry.sector_count);
    try std.testing.expect(partition.fitsImage(entry.start_lba, entry.sector_count, loaded.image_size));
}

test "fixture: quatro entradas de partição" {
    const loaded = try loadFixture("fixtures/teste-mbr-quatro.img");

    try std.testing.expectEqual(@as(u32, 1), loaded.mbr.entries[0].start_lba);
    try std.testing.expectEqual(@as(u32, 20), loaded.mbr.entries[1].start_lba);
    try std.testing.expectEqual(@as(u32, 40), loaded.mbr.entries[2].start_lba);
    try std.testing.expectEqual(@as(u32, 60), loaded.mbr.entries[3].start_lba);
}

test "fixture: assinatura inválida" {
    try std.testing.expectError(
        error.InvalidSignature,
        loadFixture("fixtures/teste-assinatura-invalida.img"),
    );
}

test "fixture: arquivo truncado com menos de 512 bytes" {
    try std.testing.expectError(
        error.FileTooSmall,
        loadFixture("fixtures/teste-pequeno.img"),
    );
}

test "leitor rejeita diretório" {
    try std.testing.expectError(
        error.NotRegularFile,
        loadFixture("."),
    );
}

test "leitor informa arquivo inexistente" {
    try std.testing.expectError(
        error.FileNotFound,
        loadFixture("fixtures/arquivo-que-nao-existe.img"),
    );
}

test "fixture: flag de boot inesperada" {
    const loaded = try loadFixture("fixtures/teste-boot-flag.img");
    try std.testing.expectEqual(@as(u8, 0x81), loaded.mbr.entries[0].boot_flag);

    const output = try renderFixture(&loaded, "fixtures/teste-boot-flag.img");
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "AVISO: flag de boot inesperada (0x81)") != null);
}

test "fixture: intervalos sobrepostos" {
    const loaded = try loadFixture("fixtures/teste-mbr-sobreposicao.img");
    const a = loaded.mbr.entries[0];
    const b = loaded.mbr.entries[1];

    try std.testing.expect(partition.overlaps(
        a.start_lba,
        @as(u64, a.start_lba) + a.sector_count,
        b.start_lba,
        @as(u64, b.start_lba) + b.sector_count,
    ));

    const output = try renderFixture(&loaded, "fixtures/teste-mbr-sobreposicao.img");
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "AVISO: partições 1 e 2 se sobrepõem") != null);
}

test "fixture: partição que termina além da imagem" {
    const loaded = try loadFixture("fixtures/teste-mbr-limites.img");
    const entry = loaded.mbr.entries[0];

    try std.testing.expectEqual(@as(u64, 5120), loaded.image_size);
    try std.testing.expect(!partition.fitsImage(entry.start_lba, entry.sector_count, loaded.image_size));

    const output = try renderFixture(&loaded, "fixtures/teste-mbr-limites.img");
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "ERRO: partição ultrapassa o fim da imagem") != null);
}
