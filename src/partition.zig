const std = @import("std");
const mbr = @import("mbr.zig");

pub const mib_bytes: u64 = 1024 * 1024;

pub fn startByte(start_lba: u32) u64 {
    return @as(u64, start_lba) * mbr.sector_size;
}

pub fn sizeBytes(sector_count: u32) u64 {
    return @as(u64, sector_count) * mbr.sector_size;
}

pub fn endLba(start_lba: u32, sector_count: u32) ?u64 {
    if (sector_count == 0) return null;
    return @as(u64, start_lba) + sector_count - 1;
}

pub fn endByte(start_lba: u32, sector_count: u32) ?u64 {
    if (sector_count == 0) return null;
    return startByte(start_lba) + sizeBytes(sector_count) - 1;
}

/// Capacidade em MiB, com duas casas decimais, representada em centésimos.
/// Exemplo: 100 MiB -> 10000.
pub fn capacityMibHundredths(size_bytes: u64) u64 {
    const whole = size_bytes / mib_bytes;
    const remainder = size_bytes % mib_bytes;
    return whole * 100 + (remainder * 100 + mib_bytes / 2) / mib_bytes;
}

pub fn fitsImage(start_lba: u32, sector_count: u32, image_size: u64) bool {
    const image_sectors = image_size / mbr.sector_size;
    if (start_lba >= image_sectors) return false;
    return @as(u64, sector_count) <= image_sectors - start_lba;
}

/// Intervalos semiabertos: [start, end).
pub fn overlaps(a_start: u64, a_end: u64, b_start: u64, b_end: u64) bool {
    return a_start < b_end and b_start < a_end;
}
