const std = @import("std");
const turso = @import("zig-turso");

// Re-export the test file so its tests are included
// pub usingnamespace @import("buffermanager_test.zig");

pub fn main() !void {
    std.testing.refAllDecls(@This());

    // setup
    std.testing.refAllDecls(@import("setup.zig"));

    // add tests here
    std.testing.refAllDecls(@import("zig-turso_test.zig"));
}

// This test block ensures that tests are discovered
test {
    std.testing.refAllDecls(@This());
}
