const std = @import("std");

const BIG_ENDIAN_MBR_BYTES = [2]u8{ 0xAA, 0x55 };
const LITTLE_ENDIAN_MBR_BYTES = [2]u8{ 0x55, 0xAA };
const MBR_SIZE = 512;
const MBR_CHECK_START_OFFSET = 510;
const MBR_ID_START_OFFSET = 440;

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
}
