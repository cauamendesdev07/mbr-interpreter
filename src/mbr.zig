const std = @import("std");

pub const sector_size: u64 = 512;
pub const mbr_size: usize = 512;
pub const disk_id_offset: usize = 440;
pub const partition_table_offset: usize = 446;
pub const partition_entry_size: usize = 16;
pub const partition_count: usize = 4;
pub const signature_offset: usize = 510;
pub const expected_signature: [2]u8 = .{ 0x55, 0xAA };

pub const ParseError = error{InvalidSignature};

pub const PartitionEntry = struct {
    raw: [partition_entry_size]u8,
    boot_flag: u8,
    partition_type: u8,
    start_lba: u32,
    sector_count: u32,

    pub fn isEmpty(self: PartitionEntry) bool {
        return std.mem.allEqual(u8, &self.raw, 0);
    }
};

pub const Mbr = struct {
    disk_id: u32,
    entries: [partition_count]PartitionEntry,
};

pub fn decodeEntry(raw: [partition_entry_size]u8) PartitionEntry {
    return .{
        .raw = raw,
        .boot_flag = raw[0],
        .partition_type = raw[4],
        .start_lba = std.mem.readInt(u32, raw[8..12], .little),
        .sector_count = std.mem.readInt(u32, raw[12..16], .little),
    };
}

pub fn parse(bytes: *const [mbr_size]u8) ParseError!Mbr {
    if (bytes[signature_offset] != expected_signature[0] or
        bytes[signature_offset + 1] != expected_signature[1])
    {
        return error.InvalidSignature;
    }

    const disk_id = std.mem.readInt(u32, bytes[disk_id_offset..][0..4], .little);

    var entries: [partition_count]PartitionEntry = undefined;
    for (0..partition_count) |i| {
        const offset = partition_table_offset + i * partition_entry_size;
        var raw: [partition_entry_size]u8 = undefined;
        @memcpy(&raw, bytes[offset..][0..partition_entry_size]);
        entries[i] = decodeEntry(raw);
    }

    return .{ .disk_id = disk_id, .entries = entries };
}

pub fn partitionTypeName(partition_type: u8) []const u8 {
    return switch (partition_type) {
        0x01 => "FAT12",
        0x04, 0x06, 0x0E => "FAT16",
        0x05 => "Partição estendida (CHS)",
        0x0F => "Partição estendida (LBA)",
        0x85 => "Partição estendida (Linux)",
        0x07 => "HPFS/NTFS/exFAT",
        0x0B => "FAT32 (CHS)",
        0x0C => "FAT32 (LBA)",
        0x82 => "Linux swap",
        0x83 => "Linux",
        0x8E => "Linux LVM",
        0xEE => "MBR protetor de GPT",
        0xEF => "EFI System",
        0x00 => "Não utilizado",
        else => "desconhecido",
    };
}
