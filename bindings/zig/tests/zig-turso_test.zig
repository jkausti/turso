const std = @import("std");
const print = std.debug.print;
const tst = std.testing;
const turso = @import("turso");
const Db = turso.Db;
const ResultValue = turso.ResultValue;
const Result = turso.Result;
const LimboValue = turso.LimboValue;
const ValueUnion = turso.ValueUnion;
const ValueType = turso.ValueType;

const c = @cImport({
    @cInclude("limbo_zig.h");
});

test "conn" {
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);
}

test "exec_success" {
    const allocator = tst.allocator;

    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

    const query = "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER);";
    try db.exec(allocator, query, null);
}

test "exec_fail" {
    const allocator = tst.allocator;
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

    const query = "not valid sql";
    _ = db.exec(allocator, query, null) catch |err| {
        try tst.expectEqual(turso.StatementError.PrepareFailed, err);
        return;
    };
}

test "prepare_success" {
    const allocator = tst.allocator;
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

    const query = "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER);";
    var stmt = try db.prepare(allocator, query);
    defer stmt.close();

    try tst.expect(stmt.handle != null);
}

test "prepare_fail" {
    const allocator = tst.allocator;
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

    const query = "not valid sql";
    var stmt = db.prepare(allocator, query) catch |err| {
        try tst.expectEqual(turso.StatementError.PrepareFailed, err);
        return;
    };
    defer stmt.close();
}

test "z.LimboValue create" {
    const my_limbo = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "Hello, World!".ptr },
    };

    try tst.expect(my_limbo.value_type == ValueType.Text);
    try tst.expectEqualStrings(std.mem.span(my_limbo.value.text_ptr), "Hello, World!");
}

test "z.LimboValue to_c" {
    const my_limbo = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "Hello, World!".ptr },
    };

    const c_limbo = my_limbo.to_c();
    try tst.expect(c_limbo.value_type == c.Text);
    try tst.expectEqualStrings(std.mem.span(c_limbo.value.text_ptr), "Hello, World!");
}

test "z.LimboValue from_c" {
    const c_limbo = c.LimboValue{
        .value_type = c.Text,
        .value = c.ValueUnion{ .text_ptr = "Hello, World!".ptr },
    };

    var zig_limbo: LimboValue = undefined;

    LimboValue.from_c(&c_limbo, &zig_limbo);
    try tst.expect(zig_limbo.value_type == ValueType.Text);
    try tst.expectEqualStrings(std.mem.span(zig_limbo.value.text_ptr), "Hello, World!");
}

test "oneAlloc basic" {
    const allocator = tst.allocator;
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

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
        allocator,
        "DROP TABLE IF EXISTS test;",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    db.exec(
        allocator,
        "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER);",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };
    //
    db.exec(
        allocator,
        "INSERT INTO test (name, age) VALUES (?, ?);",
        &params,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    const Person = struct {
        id: i64,
        name: []const u8,
        age: i64,
    };

    const query = "SELECT id, name, age FROM test";

    const person = try db.oneAlloc(allocator, query, Person, null, null);
    if (person == null) {
        print("No person found.\n", .{});
        return;
    }
    defer allocator.destroy(person.?);

    print("Person: {any}\n", .{person.?});

    try tst.expect(person.?.id == 1);
    try tst.expectEqualStrings(person.?.name, "urmom");
    try tst.expect(person.?.age == 34);
}

test "manyAlloc basic" {
    const allocator = tst.allocator;
    const db_path = "tests/artifacts/test.db";

    var db = try Db.init(.{ .File = db_path });
    defer db.close();

    try tst.expect(db.handle != null);

    var params_first: [2]LimboValue = undefined;
    var params_second: [2]LimboValue = undefined;

    params_first[0] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "urmom".ptr },
    };
    params_first[1] = LimboValue{
        .value_type = ValueType.Integer,
        .value = ValueUnion{ .int_val = 33 },
    };

    params_second[0] = LimboValue{
        .value_type = ValueType.Text,
        .value = ValueUnion{ .text_ptr = "urdad".ptr },
    };
    params_second[1] = LimboValue{
        .value_type = ValueType.Integer,
        .value = ValueUnion{ .int_val = 36 },
    };

    db.exec(
        allocator,
        "DROP TABLE IF EXISTS test;",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    db.exec(
        allocator,
        "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER);",
        null,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    db.exec(
        allocator,
        "INSERT INTO test (name, age) VALUES (?, ?);",
        &params_first,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };
    db.exec(
        allocator,
        "INSERT INTO test (name, age) VALUES (?, ?);",
        &params_second,
    ) catch |err| {
        print("Error executing query. {any}\n", .{err});
        return err;
    };

    const Person = struct {
        id: i64,
        name: []const u8,
        age: i64,
    };

    const query = "SELECT id, name, age FROM test";

    const result = try db.manyAlloc(allocator, Person, query, null, null, null);

    if (result == null) {
        print("No results returned.\n", .{});
        return;
    }
    defer {
        for (result.?) |person| {
            allocator.destroy(person);
        }
        allocator.free(result.?);
    }

    try tst.expect(result != null);
    try tst.expect(result.?.len == 2);

    try tst.expect(result.?[0].*.id == 1);
    try tst.expect(result.?[1].*.id == 2);
    try tst.expectEqualStrings(result.?[0].*.name, "urmom");
    try tst.expectEqualStrings(result.?[1].*.name, "urdad");
}
