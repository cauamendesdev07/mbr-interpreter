const std = @import("std");
const mbr = @import("../src/mbr.zig");
const partition = @import("../src/partition.zig");

test "conversão little-endian e cálculos de partição" {
    try std.testing.expectEqual(@as(u64, 1_048_576), partition.startByte(2048));
    try std.testing.expectEqual(@as(u64, 104_857_600), partition.sizeBytes(204_800));
    try std.testing.expectEqual(@as(u64, 206_847), partition.endLba(2048, 204_800).?);
    try std.testing.expectEqual(@as(u64, 105_906_175), partition.endByte(2048, 204_800).?);
}

test "partição de tamanho zero não tem LBA final nem offset final" {
    try std.testing.expectEqual(@as(?u64, null), partition.endLba(2048, 0));
    try std.testing.expectEqual(@as(?u64, null), partition.endByte(2048, 0));
}

test "capacidade em MiB" {
    try std.testing.expectEqual(@as(u64, 10_000), partition.capacityMibHundredths(104_857_600));
    try std.testing.expectEqual(@as(u64, 5), partition.capacityMibHundredths(51_200));
    try std.testing.expectEqual(@as(u64, 0), partition.capacityMibHundredths(0));
}

test "capacidade não estoura para tamanho máximo de u64" {
    try std.testing.expectEqual(
        @as(u64, 1_759_218_604_441_600),
        partition.capacityMibHundredths(std.math.maxInt(u64)),
    );
}

test "partição que termina além da imagem" {
    const image_size: u64 = 2048 * mbr.sector_size;

    try std.testing.expect(partition.fitsImage(1, 100, image_size));
    try std.testing.expect(partition.fitsImage(1948, 100, image_size));
    try std.testing.expect(!partition.fitsImage(2000, 100, image_size));
    try std.testing.expect(!partition.fitsImage(2048, 1, image_size));
    try std.testing.expect(!partition.fitsImage(0, 2049, image_size));
}

test "intervalos sobrepostos" {
    try std.testing.expect(partition.overlaps(1, 101, 50, 150));
    try std.testing.expect(partition.overlaps(10, 100, 20, 30));
    try std.testing.expect(!partition.overlaps(1, 20, 20, 40));
    try std.testing.expect(!partition.overlaps(1, 10, 20, 30));
}
