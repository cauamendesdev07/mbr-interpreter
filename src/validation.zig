const mbr = @import("mbr.zig");

pub const BootFlagStatus = enum {
    inactive,
    active,
    invalid,
};

pub const EntryKind = enum {
    data,
    extended,
    protective,
};

pub fn classifyBootFlag(flag: u8) BootFlagStatus {
    return switch (flag) {
        0x00 => .inactive,
        0x80 => .active,
        else => .invalid,
    };
}

pub fn isExtendedType(partition_type: u8) bool {
    return switch (partition_type) {
        0x05, 0x0F, 0x85 => true,
        else => false,
    };
}

pub fn isProtectiveType(partition_type: u8) bool {
    return partition_type == 0xEE;
}

pub fn entryKind(entry: mbr.PartitionEntry) ?EntryKind {
    if (entry.isEmpty()) return null;
    if (isExtendedType(entry.partition_type)) return .extended;
    if (isProtectiveType(entry.partition_type)) return .protective;
    return .data;
}

pub fn isDataEntry(entry: mbr.PartitionEntry) bool {
    const kind = entryKind(entry) orelse return false;
    return kind == .data and entry.partition_type != 0;
}
