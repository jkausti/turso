const std = @import("std");

test "tests:beforeAll" {
    // create artifacts directory
    const artifacts_dir = "./tests/artifacts";
    std.fs.cwd().makeDir(artifacts_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return;
        }
    };
}

test "tests:afterAll" {
    // remove artifacts directory
    const artifacts_dir = "./tests/artifacts";
    _ = try std.fs.cwd().deleteTree(artifacts_dir);
}
