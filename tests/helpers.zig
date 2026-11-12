const mbr = @import("../src/mbr.zig");

pub fn putLe32(out: []u8, value: u32) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
    out[2] = @truncate(value >> 16);
    out[3] = @truncate(value >> 24);
}

pub fn makeEntry(
    boot_flag: u8,
    partition_type: u8,
    start_lba: u32,
    sector_count: u32,
) [mbr.partition_entry_size]u8 {
    var entry = [_]u8{0} ** mbr.partition_entry_size;
    entry[0] = boot_flag;
    entry[4] = partition_type;
    putLe32(entry[8..12], start_lba);
    putLe32(entry[12..16], sector_count);
    return entry;
}

pub fn makeMbr(
    entries: []const [mbr.partition_entry_size]u8,
    signature: [2]u8,
    disk_id: u32,
) [mbr.mbr_size]u8 {
    var bytes = [_]u8{0} ** mbr.mbr_size;
    putLe32(bytes[mbr.disk_id_offset..][0..4], disk_id);

    for (entries, 0..) |entry, i| {
        const offset = mbr.partition_table_offset + i * mbr.partition_entry_size;
        @memcpy(bytes[offset..][0..mbr.partition_entry_size], &entry);
    }

    bytes[mbr.signature_offset] = signature[0];
    bytes[mbr.signature_offset + 1] = signature[1];
    return bytes;
}
