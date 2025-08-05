const std = @import("std");
const print = std.debug.print;
const turso = @import("zig-turso.zig");
const LimboValue = turso.LimboValue;
const ValueType = turso.ValueType;
const ValueUnion = turso.ValueUnion;
const StatementError = turso.StatementError;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var db = try turso.Db.init(allocator, .{ .File = "my.db" });
    defer db.close();

    var params: [2]LimboValue = undefined;

    params[0] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "urmom".ptr },
    };
    params[1] = LimboValue{
        .value_type = ValueType.Integer,
        .value = ValueUnion{ .int_val = 34 },
    };

    db.exec(
        "DROP TABLE IF EXISTS test;",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    db.exec(
        "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER);",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };
    //
    db.exec(
        "INSERT INTO test (name, age) VALUES (?, ?);",
        &params,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };
}
