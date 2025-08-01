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

    var conn = try turso.Conn.init(allocator, "my.db");
    defer conn.close();
    var cursor = try conn.cursor();

    var params = try allocator.alloc(LimboValue, 3);

    params[0] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "urmom".ptr },
    };
    params[1] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "urdad".ptr },
    };
    params[2] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "ursister".ptr },
    };

    _ = cursor.execute(
        "DROP TABLE IF EXISTS test;",
        &.{},
    ) catch |err| {
        // print("Error executing query: {any}\n", .{err});
        return err;
    };

    _ = cursor.execute(
        "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);",
        &.{},
    ) catch |err| {
        // print("Error executing query: {any}\n", .{err});
        return err;
    };
    //
    _ = cursor.execute(
        "INSERT INTO test (name) VALUES (?);",
        params,
    ) catch |err| {
        // print("Error executing query: {any}\n", .{err});
        return err;
    };

    // _ = cursor.execute(
    //     "SELECT * FROM test;",
    //     &.{},
    // ) catch |err| {
    //     switch (err) {
    //         StatementError.NotImplemented => {
    //             // print("Your statement is not implemented.", .{});
    //             return err;
    //         },
    //         else => {
    //             // print("Error happened in your statement: {any}\n", .{cursor.statement_str.?});
    //             return err;
    //         },
    //     }
    // };

    // const row = cursor.fetch_one() catch |err| {
    //     print("Error fetching first value: {any}\n", .{err});
    //     return err;
    // };
    //
    // if (row != null) {
    //     print("{any}", .{row});
    // }

    // _ = cursor.execute(
    //     "SELECT * FROM test;",
    //     &.{},
    // ) catch |err| {
    //     switch (err) {
    //         StatementError.NotImplemented => {
    //             // print("Your statement is not implemented.", .{});
    //             return err;
    //         },
    //         else => {
    //             // print("Error happened in your statement: {any}\n", .{cursor.statement_str.?});
    //             return err;
    //         },
    //     }
    // };
    //
    // const rest = cursor.fetch_many(null) catch |err| {
    //     print("Error fetching rest of rows: {any}\n", .{err});
    //     return err;
    // };
    //
    // for (rest.?) |r| {
    //     print("{any}", .{r});
    // }

    // print("Type of first value: {any}\n", .{first_value.?.value_type});

    // if (cursor.rows != null) {
    //     print("Shit works!\n", .{});
    // } else {
    //     print("Scheisse!\n", .{});
    // }
}
