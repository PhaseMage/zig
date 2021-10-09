const std = @import("std");
const fs = std.fs;

// pub fn main() !void {
//     const cwd = fs.cwd();
//     const temp_file = "hello.txt";
//     try cwd.writeFile(temp_file, temp_file);
//     const mtime = try getmtime(temp_file);
//     var data: [10]u8 = .{0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
//     const new_mtime = while (true) {
//         data[0] +%= 1;
//         var file = try cwd.openFile(temp_file, .{.write=true});
//         _ = try file.write(data[0..]);
//         try file.updateTimes(std.time.nanoTimestamp()+100, std.time.nanoTimestamp()+100);
//         file.close();
//         const new_mtime = try getmtime(temp_file);
//         if (new_mtime != mtime) {
//             break new_mtime;
//         }
//     } else unreachable;
//     std.debug.print(
//         "{} old mtime: {}\nnew mtime: {}\ndifference: {}\n",
//         .{ data[0], mtime, new_mtime, new_mtime - mtime },
//     );
// }

pub fn main() !void {
    // const mtime = std.time.nanoTimestamp();
    var i: u32 = 0;
    
    // Wait for file timestamps to tick
    const cwd = fs.cwd();
    const nanoStart = std.time.nanoTimestamp();
    const mtime = try testGetCurrentFileTimestamp(cwd);
    const nanoStop = std.time.nanoTimestamp();
    var new_mtime = try testGetCurrentFileTimestamp(cwd);
    while (new_mtime == mtime) : (i += 1) {
        std.time.sleep(1);
        new_mtime = try testGetCurrentFileTimestamp(cwd);
    }
    
    // const new_mtime = while (true) : (i += 1) {
    //     var new_mtime = std.time.nanoTimestamp();
    //     if (new_mtime != mtime) {
    //         break new_mtime;
    //     }
    // } else unreachable;
    std.debug.print(
        "{} s {} old mtime: {}\nnew mtime: {}\ndifference: {}\n",
        .{ i, nanoStop - nanoStart, mtime, new_mtime, new_mtime - mtime },
    );
}

fn getmtime(temp_file: []const u8) !i128 {
    const file = try fs.cwd().openFile(temp_file, .{});
    defer file.close();
    const stat = try file.stat();
    return stat.mtime;
}

fn testGetCurrentFileTimestamp(cwd: fs.Dir) !i128 {
    var timestamp_file = try cwd.createFile("filetimestamp.tmp", .{
        .read = true,
        .truncate = false,
    });
    defer timestamp_file.close();
    try timestamp_file.setEndPos(0);
    
    return (try timestamp_file.stat()).mtime;
}

// The current level of precision (in ns) shown to exist in file timestamps. Lower is more precise.
var s_current_precision: u32 = 1_000_000_000;

// The next level of precision (in ns) that could exist in file timestamps.
var s_next_precision: u32 = 100_000_000;

// mask of decimal digits found in the next level of precision in file timestamps. Once this is 
// maxInt(u10), all digits have been found, and s_current_precision can brought to the next level.
var s_next_digit_mask: u10 = 0;

/// If the wall clock time, rounded to the same precision as the
/// mtime, is equal to the mtime, then we cannot rely on this mtime
/// yet. We will instead save an mtime value that indicates the hash
/// must be unconditionally computed.
/// This function recognizes the precision of mtime by looking at trailing
/// zero bits of the seconds and nanoseconds.
fn isProblematicTimestamp(fs_clock: u96) bool {
    const fs_sec = std.time.secondsFromStdTime(fs_clock);
    if (fs_sec == 0)
        return true;    // Zero timestamp on the file is clearly problematic

    const wall_clock = std.time.timestampNow();
    const wall_sec = std.time.secondsFromStdTime(wall_clock);
    if (fs_sec != wall_sec)
        return false;

    const fs_nsec = std.time.nsPartOfStdTime(fs_clock);
    if (fs_nsec == 0)
        return true;    // Zero ns is problematic
    
    var wall_nsec = std.time.nsPartOfStdTime(wall_clock);

    const current_precision = s_current_precision;
    if (current_precision == 1) {
        // Files have nanosecond precision, compare directly
        return wall_nsec == fs_nsec;
    }

    // This finds the next decimal digit and adds it to the mask.
    // Once all digits are found, we know the precision is at least that good.
    // TODO: Once we hit the limit of mtime precision, should we ever give up, or just keep trying?
    const next_precision = s_next_precision;
    s_next_digit_mask |= (1 << (fs_nsec / next_precision));
    if (s_next_digit_mask == std.math.maxInt(u10)) {
        // Found all digits in the next level of precision. Files have better precision.
        // TODO: Does this need to be more thread safe?
        s_next_digit_mask = 0;
        s_current_precision = next_precision;
        s_next_precision = next_precision / 10;
    }

    if (fs_nsec > wall_nsec) {
        // fs_nsec is in the future. Clearly problematic.
        return true;
    } else {
        // Problematic if the delta is smaller than the currently proven precision
        return (wall_nsec - fs_nsec) < current_precision;
    }
}