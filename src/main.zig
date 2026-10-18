const std = @import("std");

const BIG_ENDIAN_MBR_BYTES = [2]u8{ 0xAA, 0x55 };
const LITTLE_ENDIAN_MBR_BYTES = [2]u8{ 0x55, 0xAA };
const MBR_SIZE = 512;
const MBR_CHECK_START_OFFSET = 510;
const MBR_ID_START_OFFSET = 440;
const PARTITION_TABLE_START: u64 = 446;
const PARTITION_ENTRY_SIZE: usize = 16;
const PARTITION_COUNT: usize = 4;
const SECTOR_SIZE: u64 = 512;

fn reverse(comptime N: usize, bytes: [N]u8) [N]u8 {
    var result: [N]u8 = undefined;

    for (0..N) |i| {
        result[i] = bytes[N - 1 - i];
    }

    return result;
}

fn partitionTypeName(partition_type: u8) []const u8 {
    return switch (partition_type) {
        0x01 => "FAT12",
        0x04, 0x06, 0x0E => "FAT16",
        0x05, 0x0F => "Particao estendida",
        0x07 => "NTFS/exFAT/HPFS",
        0x0B, 0x0C => "FAT32",
        0x82 => "Linux swap",
        0x83 => "Linux",
        0x8E => "Linux LVM",
        0xEE => "GPT protective",
        0xEF => "EFI System",
        0x00 => "Vazio",
        else => "Desconhecido",
    };
}

const MbrSignature = enum {
    big_endian,
    little_endian,
    invalid,
};

fn validateArgs(args: []const [:0]const u8) bool {
    return args.len == 2;
}

fn validateSize(len: u64) bool {
    return len >= MBR_SIZE;
}

fn parseSignature(buf: [2]u8) MbrSignature {
    if (std.mem.eql(u8, buf[0..], BIG_ENDIAN_MBR_BYTES[0..])) {
        return .big_endian;
    } else if (std.mem.eql(u8, buf[0..], LITTLE_ENDIAN_MBR_BYTES[0..])) {
        return .little_endian;
    } else {
        return .invalid;
    }
}

fn signatureToHex(buf: *const [2]u8) [4]u8 {
    return std.fmt.bytesToHex(buf, .upper);
}

fn diskIdToHex(buf: *const [4]u8) [8]u8 {
    return std.fmt.bytesToHex(buf, .upper);
}

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const args = try init.minimal.args.toSlice(init.arena.allocator());
	
	var stdout_buf: [1024]u8 = undefined;
    	var writer_impl = std.Io.File.stdout().writer(io, stdout_buf[0..]);
    	const writer = &writer_impl.interface;
	
	if (validateArgs(args) == false) {
        	try writer.print("Usage: mbr-check <file>\n", .{});
        	try writer.flush();
        	return;
    	}

	var mbr_check_buf: [2]u8 = undefined;
    	const file = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    	defer file.close(io);

	if (validateSize(try file.length(io)) == false) {
        	try writer.print("File too small\n", .{});
        	try writer.flush();
        	return;
    	}
	
	_ = try file.readPositionalAll(io, &mbr_check_buf, MBR_CHECK_START_OFFSET);
    	const mbr_check_buf_hex = signatureToHex(&mbr_check_buf);
	
	const signature = parseSignature(mbr_check_buf);

	if (signature == .invalid) {
        	try writer.print("Not a MBR: {s}\n", .{mbr_check_buf_hex});
		try writer.flush();
		return;
	}	
	
	var mbr_id_disk: [4]u8 = undefined;
	_ = try file.readPositionalAll(io, &mbr_id_disk, MBR_ID_START_OFFSET);	
    	const mbr_id_disk_hex = diskIdToHex(&mbr_id_disk);

	try writer.print("Assinatura: valida {s}\n", .{mbr_check_buf_hex});	
	try writer.print("Identificador de Disco: 0x{s}\n", .{mbr_id_disk_hex});
	
	try writer.flush();

   const image_size = try file.length(io);

    try writer.print(
        "Capacidade da imagem: {d} MiB\n",
        .{image_size / (1024 * 1024)},
    );

    var partition_starts: [PARTITION_COUNT]u64 = undefined;
    var partition_ends: [PARTITION_COUNT]u64 = undefined;
    var valid_partitions: [PARTITION_COUNT]bool = [_]bool{false} ** PARTITION_COUNT;

    for (0..PARTITION_COUNT) |i| {
        var entry: [PARTITION_ENTRY_SIZE]u8 = undefined;

        const entry_offset = PARTITION_TABLE_START +
            @as(u64, @intCast(i)) * PARTITION_ENTRY_SIZE;

        _ = try file.readPositionalAll(io, &entry, entry_offset);

        const boot_flag = entry[0];
        const partition_type = entry[4];

        const start_lba_bytes = reverse(4, .{
            entry[8], entry[9], entry[10], entry[11],
        });
        const start_lba: u64 = std.mem.readInt(u32, &start_lba_bytes, .big);

        const sector_count_bytes = reverse(4, .{
            entry[12], entry[13], entry[14], entry[15],
        });
        const sector_count: u64 = std.mem.readInt(u32, &sector_count_bytes, .big);

        if (partition_type == 0 and sector_count == 0) {
            try writer.print(
                "\nParticao {d}: vazia\n",
                .{i + 1},
            );
            continue;
        }

        const boot_status: []const u8 = switch (boot_flag) {
            0x80 => "Inicializavel",
            0x00 => "Nao inicializavel",
            else => "Flag invalida",
        };

        try writer.print("\nParticao {d}\n", .{i + 1});
        try writer.print("  Boot: {s}\n", .{boot_status});
        try writer.print("  Flag: 0x{X}\n", .{boot_flag});
        try writer.print(
            "  Tipo: 0x{X} ({s})\n",
            .{ partition_type, partitionTypeName(partition_type) },
        );
        try writer.print("  LBA inicial: {d}\n", .{start_lba});
        try writer.print("  Setores: {d}\n", .{sector_count});

        if (sector_count == 0) {
            try writer.print(
                "  Aviso: particao com zero setores\n",
                .{},
            );
            continue;
        }

        const start_byte = start_lba * SECTOR_SIZE;
        const size_bytes = sector_count * SECTOR_SIZE;
        const end_byte = start_byte + size_bytes;
        const end_lba = start_lba + sector_count - 1;

        try writer.print(
            "  Offset inicial: {d} bytes\n",
            .{start_byte},
        );
        try writer.print(
            "  Tamanho: {d} bytes\n",
            .{size_bytes},
        );
        try writer.print(
            "  LBA final: {d}\n",
            .{end_lba},
        );

        if (end_byte > image_size) {
            try writer.print(
                "  ERRO: particao ultrapassa o tamanho da imagem\n",
                .{},
            );
        }

        partition_starts[i] = start_lba;
        partition_ends[i] = start_lba + sector_count;
        valid_partitions[i] = true;
    }

    for (0..PARTITION_COUNT) |i| {
        if (!valid_partitions[i]) continue;

        for (i + 1..PARTITION_COUNT) |j| {
            if (!valid_partitions[j]) continue;

            if (partition_starts[i] < partition_ends[j] and
                partition_starts[j] < partition_ends[i])
            {
                try writer.print(
                    "AVISO: particoes {d} e {d} se sobrepoem\n",
                    .{ i + 1, j + 1 },
                );
            }
        }
    }

    try writer.flush();
}

test "validateArgs requires program plus file" {
    const ok = [_][:0]const u8{ "mbr-check", "disk.img" };
    try std.testing.expect(validateArgs(&ok));

    const empty = [_][:0]const u8{};
    try std.testing.expect(!validateArgs(&empty));

    const one = [_][:0]const u8{"mbr-check"};
    try std.testing.expect(!validateArgs(&one));

    const three = [_][:0]const u8{ "mbr-check", "a.img", "b.img" };
    try std.testing.expect(!validateArgs(&three));
}

test "validateSize enforces 512-byte minimum" {
    try std.testing.expect(!validateSize(0));
    try std.testing.expect(!validateSize(511));
    try std.testing.expect(validateSize(512));
    try std.testing.expect(validateSize(513));
    try std.testing.expect(validateSize(1024));
}

test "parseSignature detects endianness" {
    try std.testing.expectEqual(MbrSignature.big_endian, parseSignature(.{ 0xAA, 0x55 }));
    try std.testing.expectEqual(MbrSignature.little_endian, parseSignature(.{ 0x55, 0xAA }));
}

test "parseSignature rejects invalid signatures" {
    try std.testing.expectEqual(MbrSignature.invalid, parseSignature(.{ 0x00, 0x00 }));
    try std.testing.expectEqual(MbrSignature.invalid, parseSignature(.{ 0xFF, 0xFF }));
    try std.testing.expectEqual(MbrSignature.invalid, parseSignature(.{ 0xAA, 0xAA }));
    try std.testing.expectEqual(MbrSignature.invalid, parseSignature(.{ 0x55, 0x55 }));
    try std.testing.expectEqual(MbrSignature.invalid, parseSignature(.{ 0x55, 0x00 }));
}

test "signatureToHex formats upper-case" {
    var little = [2]u8{ 0x55, 0xAA };
    try std.testing.expectEqualStrings("55AA", signatureToHex(&little)[0..]);

    var big = [2]u8{ 0xAA, 0x55 };
    try std.testing.expectEqualStrings("AA55", signatureToHex(&big)[0..]);
}

test "diskIdToHex formats upper-case" {
    var id = [4]u8{ 0x12, 0x34, 0x56, 0x78 };
    try std.testing.expectEqualStrings("12345678", diskIdToHex(&id)[0..]);

    var dead = [4]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try std.testing.expectEqualStrings("DEADBEEF", diskIdToHex(&dead)[0..]);

    var zero = [4]u8{ 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectEqualStrings("00000000", diskIdToHex(&zero)[0..]);
}

test "reverse flips byte order" {
    const four = reverse(4, .{ 0xAA, 0xBB, 0xCC, 0xDD });
    try std.testing.expectEqualSlices(u8, &.{ 0xDD, 0xCC, 0xBB, 0xAA }, &four);

    const two = reverse(2, .{ 0x12, 0x34 });
    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12 }, &two);
}
