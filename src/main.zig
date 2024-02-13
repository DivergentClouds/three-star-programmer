const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var code_file: ?std.fs.File = null;

    var memory: ?std.AutoHashMap(usize, usize) = null;
    var memory_file: std.fs.File = undefined;
    var memory_file_name: ?[]const u8 = null;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const arg0 = args.next() orelse
        return error.NoArg0;

    while (args.next()) |arg| {
        errdefer printUsage(arg0, true) catch {};

        if (std.mem.eql(u8, arg, "--memory")) {
            if (memory_file_name == null) {
                memory_file_name = args.next() orelse
                    return error.NoMemoryFileSpecified;
            } else {
                return error.TooManyMemoryFiles;
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(arg0, false);
            return;
        } else {
            if (code_file == null) {
                code_file = try std.fs.cwd().openFile(arg, .{});
            } else {
                return error.TooManyCodeFiles;
            }
        }
    }

    if (code_file == null) {
        try printUsage(arg0, true);
        return error.NoCodeFileSpecified;
    }

    if (memory_file_name) |memory_name| {
        memory_file = try std.fs.cwd().openFile(memory_name, .{});
        defer memory_file.close();

        memory = try readMemory(memory_file, allocator);
    }
    defer if (memory) |*memory_list| {
        memory_list.deinit();
    };

    try interpret(code_file.?, memory, allocator);
}

fn interpret(
    code_file: std.fs.File,
    initial_memory: ?std.AutoHashMap(usize, usize),
    allocator: std.mem.Allocator,
) !void {
    const stdout = std.io.getStdOut().writer();

    var memory = if (initial_memory) |initial|
        initial
    else
        std.AutoHashMap(usize, usize).init(allocator);

    defer if (initial_memory == null) {
        memory.deinit();
    };

    const code_reader = code_file.reader();

    var string_list = std.ArrayList(u8).init(allocator);
    defer string_list.deinit();

    while (code_reader.readByte() catch next: {
        // loop if end of file is reached
        try code_file.seekTo(0);

        // if file is empty break with null
        break :next code_reader.readByte() catch null;
    }) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            if (string_list.items.len == 0) {
                continue;
            }

            var address = try std.fmt.parseUnsigned(
                usize,
                string_list.items,
                10,
            );
            string_list.clearAndFree();

            // deref 3 times
            for (0..2) |_| {
                address = memory.get(address) orelse 0;
            }

            const value = (memory.get(address) orelse 0) + 1;

            try memory.put(address, value);
        } else if (byte >= '0' and byte <= '9') {
            try string_list.append(byte);
        } else {
            try code_file.seekTo(0);

            if ((memory.get(1) orelse 0) % 2 == 1) {
                try stdout.writeByte(
                    @as(u8, @truncate(memory.get(3) orelse 0)),
                );
            }
        }
    }
}

fn readMemory(
    memory_file: std.fs.File,
    allocator: std.mem.Allocator,
) !std.AutoHashMap(usize, usize) {
    const memory_reader = memory_file.reader();

    var memory = std.AutoHashMap(usize, usize).init(allocator);
    errdefer memory.deinit();

    var string_list = std.ArrayList(u8).init(allocator);
    defer string_list.deinit();

    var index: usize = 0;

    while (memory_reader.readByte() catch null) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            if (string_list.items.len == 0) {
                continue;
            }

            try memory.put(
                index,
                try std.fmt.parseUnsigned(usize, string_list.items, 10),
            );

            index += 1;
            string_list.clearAndFree();
        } else if (byte >= '0' and byte <= '9') {
            try string_list.append(byte);
        } else {
            return error.UnknownCharacterInMemoryFile;
        }
    }

    return memory;
}

fn printUsage(program_name: []const u8, is_err: bool) !void {
    const output = if (is_err)
        std.io.getStdErr()
    else
        std.io.getStdOut();

    try output.writer().print(
        \\usage: {s} [--help] [--memory <file>] <code file>
        \\
        \\  --help      Print this help message and exit
        \\  --memory    Initialize memory to decimal values in a file
        \\
    , .{program_name});
}
