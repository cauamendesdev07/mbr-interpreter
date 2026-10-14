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

fn readU32LE(bytes: [4]u8) u64 {
    return @as(u64, bytes[0]) |
        (@as(u64, bytes[1]) << 8) |
        (@as(u64, bytes[2]) << 16) |
        (@as(u64, bytes[3]) << 24);
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

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const args = try init.minimal.args.toSlice(init.arena.allocator());
	
	var stdout_buf: [1024]u8 = undefined;
    	var writer_impl = std.Io.File.stdout().writer(io, stdout_buf[0..]);
    	const writer = &writer_impl.interface;
	
	if (args.len != 2) {
        	try writer.print("Usage: mbr-check <file>\n", .{});
        	try writer.flush();
        	return;
    	}

	var mbr_check_buf: [2]u8 = undefined;
    	const file = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    	defer file.close(io);

	if (try file.length(io) < MBR_SIZE) {
        	try writer.print("File too small\n", .{});
        	try writer.flush();
        	return;
    	}
	
	_ = try file.readPositionalAll(io, &mbr_check_buf, MBR_CHECK_START_OFFSET);
    	const mbr_check_buf_hex = std.fmt.bytesToHex(&mbr_check_buf, .upper);
	
	var BIG_ENDIAN = false;
	
	if (std.mem.eql(u8, mbr_check_buf[0..], BIG_ENDIAN_MBR_BYTES[0..])) {
        	BIG_ENDIAN = true;
    	} else if (std.mem.eql(u8, mbr_check_buf[0..], LITTLE_ENDIAN_MBR_BYTES[0..])) {
        	BIG_ENDIAN = false;
    	} else {
        	try writer.print("Not a MBR: {s}\n", .{mbr_check_buf_hex});
		try writer.flush();
		return;
	}	
	
	var mbr_id_disk: [4]u8 = undefined;
	_ = try file.readPositionalAll(io, &mbr_id_disk, MBR_ID_START_OFFSET);	
    	const mbr_id_disk_hex = std.fmt.bytesToHex(&mbr_id_disk, .upper);

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

        const start_lba: u64 = readU32LE(.{
            entry[8], entry[9], entry[10], entry[11],
        });

        const sector_count: u64 = readU32LE(.{
            entry[12], entry[13], entry[14], entry[15],
        });

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
