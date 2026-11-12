const std = @import("std");
const mbr = @import("../src/mbr.zig");
const validation = @import("../src/validation.zig");
const helpers = @import("helpers.zig");

test "flags de boot convencionais e inesperadas" {
    try std.testing.expectEqual(validation.BootFlagStatus.inactive, validation.classifyBootFlag(0x00));
    try std.testing.expectEqual(validation.BootFlagStatus.active, validation.classifyBootFlag(0x80));
    try std.testing.expectEqual(validation.BootFlagStatus.invalid, validation.classifyBootFlag(0x81));
    try std.testing.expectEqual(validation.BootFlagStatus.invalid, validation.classifyBootFlag(0xFF));
}

test "tipos estendidos e MBR protetor de GPT" {
    try std.testing.expect(validation.isExtendedType(0x05));
    try std.testing.expect(validation.isExtendedType(0x0F));
    try std.testing.expect(validation.isExtendedType(0x85));
    try std.testing.expect(!validation.isExtendedType(0x83));

    try std.testing.expect(validation.isProtectiveType(0xEE));
    try std.testing.expect(!validation.isProtectiveType(0x83));
}

test "classificação de entradas" {
    const empty = mbr.decodeEntry([_]u8{0} ** mbr.partition_entry_size);
    const data = mbr.decodeEntry(helpers.makeEntry(0, 0x83, 1, 10));
    const extended = mbr.decodeEntry(helpers.makeEntry(0, 0x0F, 1, 10));
    const protective = mbr.decodeEntry(helpers.makeEntry(0, 0xEE, 1, 10));

    try std.testing.expect(validation.entryKind(empty) == null);
    try std.testing.expectEqual(validation.EntryKind.data, validation.entryKind(data).?);
    try std.testing.expectEqual(validation.EntryKind.extended, validation.entryKind(extended).?);
    try std.testing.expectEqual(validation.EntryKind.protective, validation.entryKind(protective).?);

    try std.testing.expect(!validation.isDataEntry(empty));
    try std.testing.expect(validation.isDataEntry(data));
    try std.testing.expect(!validation.isDataEntry(extended));
    try std.testing.expect(!validation.isDataEntry(protective));
}
