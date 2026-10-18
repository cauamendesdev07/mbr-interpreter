const std = @import("std");

const BIG_ENDIAN_MBR_BYTES = [2]u8{ 0xAA, 0x55 };
const LITTLE_ENDIAN_MBR_BYTES = [2]u8{ 0x55, 0xAA };
const MBR_SIZE = 512;
const MBR_CHECK_START_OFFSET = 510;
const MBR_ID_START_OFFSET = 440;

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
