const std = @import("std");
const mbr = @import("mbr.zig");
const partition = @import("partition.zig");
const validation = @import("validation.zig");

const Interval = struct {
    index: usize,
    start: u64,
    end: u64,
};

pub fn writeReport(
    writer: *std.Io.Writer,
    file_path: []const u8,
    parsed: *const mbr.Mbr,
    image_size: u64,
) !void {
    try writer.print("MBR Inspector\n", .{});
    try writer.print("Arquivo: {s}\n", .{file_path});
    try writer.print("Assinatura: válida (55 AA)\n", .{});
    try writer.print("Identificador do disco: 0x{X:0>8}\n", .{parsed.disk_id});
    try writeSize(writer, "Capacidade da imagem", image_size);

    if (image_size % mbr.sector_size != 0) {
        try writer.print(
            "Aviso: o tamanho da imagem não é múltiplo de 512 bytes; usando apenas os setores completos ({d}).\n",
            .{image_size / mbr.sector_size},
        );
    }
    try writer.print("\n", .{});

    var intervals: [mbr.partition_count]Interval = undefined;
    var interval_count: usize = 0;

    for (parsed.entries, 0..) |entry, index| {
        if (entry.isEmpty()) {
            try writer.print("Partição {d}: vazia\n", .{index + 1});
            continue;
        }

        try writer.print("Partição {d}\n", .{index + 1});
        try writer.print("  Inicializável: {s}\n", .{bootFlagLabel(entry.boot_flag)});
        try writer.print("  Flag de boot: 0x{X:0>2}\n", .{entry.boot_flag});
        try writer.print("  Tipo: 0x{X:0>2} ({s})\n", .{
            entry.partition_type,
            mbr.partitionTypeName(entry.partition_type),
        });
        try writer.print("  LBA inicial: {d}\n", .{entry.start_lba});
        try writer.print("  Setores: {d}\n", .{entry.sector_count});
        try writer.print("  Offset inicial: {d} bytes\n", .{partition.startByte(entry.start_lba)});
        try writeSize(writer, "  Tamanho", partition.sizeBytes(entry.sector_count));

        if (partition.endLba(entry.start_lba, entry.sector_count)) |end_lba| {
            try writer.print("  LBA final: {d}\n", .{end_lba});
        } else {
            try writer.print("  LBA final: n/a\n", .{});
        }

        if (partition.endByte(entry.start_lba, entry.sector_count)) |end_byte| {
            try writer.print("  Offset final: {d} bytes\n", .{end_byte});
        } else {
            try writer.print("  Offset final: n/a\n", .{});
        }

        switch (validation.entryKind(entry) orelse unreachable) {
            .extended => try writer.print(
                "  Observação: partição estendida; a cadeia de EBRs não é interpretada.\n",
                .{},
            ),
            .protective => try writer.print(
                "  Observação: entrada de MBR protetor de GPT; a tabela GPT não é interpretada.\n",
                .{},
            ),
            .data => {},
        }

        if (entry.partition_type == 0) {
            try writer.print(
                "  ERRO: tipo 0x00 em uma entrada não vazia.\n",
                .{},
            );
        }

        if (entry.sector_count == 0) {
            try writer.print(
                "  ERRO: entrada não vazia com número de setores igual a zero.\n",
                .{},
            );
        } else if (entry.start_lba == 0) {
            try writer.print(
                "  ERRO: intervalo LBA inclui o setor 0.\n",
                .{},
            );
        }

        if (entry.sector_count > 0 and
            !partition.fitsImage(entry.start_lba, entry.sector_count, image_size))
        {
            try writer.print(
                "  ERRO: partição ultrapassa o fim da imagem (imagem com {d} setores).\n",
                .{image_size / mbr.sector_size},
            );
        }

        if (validation.classifyBootFlag(entry.boot_flag) == .invalid) {
            try writer.print(
                "  AVISO: flag de boot inesperada (0x{X:0>2}); valores válidos: 0x00 e 0x80.\n",
                .{entry.boot_flag},
            );
        }

        if (validation.isDataEntry(entry) and entry.sector_count > 0) {
            intervals[interval_count] = .{
                .index = index,
                .start = entry.start_lba,
                .end = @as(u64, entry.start_lba) + entry.sector_count,
            };
            interval_count += 1;
        }

        try writer.print("\n", .{});
    }

    var i: usize = 0;
    while (i < interval_count) : (i += 1) {
        var j = i + 1;
        while (j < interval_count) : (j += 1) {
            const a = intervals[i];
            const b = intervals[j];
            if (partition.overlaps(a.start, a.end, b.start, b.end)) {
                try writer.print(
                    "AVISO: partições {d} e {d} se sobrepõem (LBAs {d}..{d} e {d}..{d}).\n",
                    .{
                        a.index + 1,
                        b.index + 1,
                        a.start,
                        a.end - 1,
                        b.start,
                        b.end - 1,
                    },
                );
            }
        }
    }
}

fn bootFlagLabel(flag: u8) []const u8 {
    return switch (validation.classifyBootFlag(flag)) {
        .inactive => "não",
        .active => "sim",
        .invalid => "flag inválida",
    };
}

fn writeSize(writer: *std.Io.Writer, label: []const u8, size_bytes: u64) !void {
    const hundredths = partition.capacityMibHundredths(size_bytes);
    try writer.print(
        "{s}: {d} bytes ({d}.{d:0>2} MiB)\n",
        .{ label, size_bytes, hundredths / 100, hundredths % 100 },
    );
}
