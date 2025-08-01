const std = @import("std");
const print = std.debug.print;
const tst = std.testing;
const turso = @import("turso");
const conn = turso.Conn;
const ResultValue = turso.ResultValue;
const Result = turso.Result;

test "conn" {
    const db_path = "tests/artifacts/test.db";

    var c = try conn.init(db_path);
    defer c.close();

    try tst.expect(c.handle != null);
}

test "execute_stmt" {
    const db_path = "tests/artifacts/test.db";

    var con = try conn.init(db_path);
    defer con.close();

    const create_result = try con.execute("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, name TEXT);");

    const insert_result = try con.execute("INSERT INTO test (name) VALUES ('test_name');");

    try tst.expect(create_result.value == ResultValue.Done);
    try tst.expect(insert_result.value == ResultValue.Done);
}

test "failed_prepare_stmt" {
    const db_path = "tests/artifacts/test.db";

    var con = try conn.init(db_path);
    defer con.close();

    const result = con.execute("INVALID SQL STATEMENT;") catch |err| {
        try tst.expectEqual(err, turso.StatementError.PrepareFailed);
        return;
    };

    _ = result;
}

test "failed_execute_stmt" {
    const db_path = "tests/artifacts/test.db";

    var con = try conn.init(db_path);
    defer con.close();

    const result = con.execute("SELECT 1;") catch |err| {
        try tst.expectEqual(err, turso.StatementError.ExecuteFailed); // Expecting an error because c.stmt_query should be used for SELECT statements
        return;
    };
    _ = result;
}

test "test_query" {
    const db_path = "tests/artifacts/test.db";

    var con = try conn.init(db_path);
    defer con.close();

    const query_result = try con.execute("SELECT 1;");
    try tst.expect(query_result.value ==);
}
