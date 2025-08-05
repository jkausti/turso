const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("limbo_zig.h");
});

pub const DbError = error{
    ConnectionFailed,
};

pub const StatementError = error{
    PrepareFailed,
    ExecuteFailed,
    NotImplemented,
    ZeroArguments,
};

pub const RowError = error{
    NoMoreRows,
};

pub const ResultValue = enum(i64) {
    Error = -1,
    Ok = 0,
    Row = 1,
    Busy = 2,
    Io = 3,
    Interrupt = 4,
    Invalid = 5,
    Null = 6,
    NoMem = 7,
    ReadOnly = 8,
    NoData = 9,
    Done = 10,
    SyntaxErr = 11,
    ConstraintViolation = 12,
    NoSuchEntity = 13,
};

pub const Result = struct {
    value: ResultValue,
    changed: i64,

    // pub fn format(self: Result, fmt: anytype) !void {
    //     try fmt.print("Result(value: {any}, changed: {any})", .{ self.value, self.changed });
    // }
};

pub const RowResult = struct {
    value: ResultValue,
    changed: i64,
    rows: ?*Rows = null,

    // pub fn format(self: Result, fmt: anytype) !void {
    //     try fmt.print("Result(value: {any}, changed: {any})", .{ self.value, self.changed });
    // }
};

pub const ValueType = enum(i64) {
    Integer = 0,
    Text = 1,
    Blob = 2,
    Real = 3,
    NullValue = 4,
};

pub const ValueUnion = union(enum) {
    int_val: i64,
    real_val: f64,
    text_ptr: [*c]const u8,
    blob_ptr: *const anyopaque,
};

pub const LimboValue = struct {
    value_type: ValueType,
    value: ValueUnion,

    fn to_c(self: LimboValue) c.LimboValue {
        return c.LimboValue{
            .value_type = @intCast(@intFromEnum(self.value_type)),
            .value = switch (self.value_type) {
                .Integer => .{ .int_val = self.value.int_val },
                .Text => .{ .text_ptr = self.value.text_ptr },
                .Blob => .{ .blob_ptr = self.value.blob_ptr },
                .Real => .{ .real_val = self.value.real_val },
                .NullValue => .{ .text_ptr = null },
            },
        };
    }
};

const Statement = struct {
    handle: ?*anyopaque,
    allocator: Allocator,

    fn handle_args(allocator: Allocator, args: []LimboValue) ![]c.LimboValue {
        // if (args.len == 0) {
        //     return StatementError.ZeroArguments;
        // }

        var c_args = try allocator.alloc(c.LimboValue, args.len);

        for (args, 0..) |arg, i| {
            const c_arg = arg.to_c();
            c_args[i] = c_arg;
        }

        return c_args;
    }

    fn execute(self: *Statement, args: ?[]LimboValue) !void {
        var rows_changed: i64 = undefined;

        var result_code: i64 = 0;

        if (args) |a| {
            const c_args = try Statement.handle_args(self.allocator, a);
            defer self.allocator.free(c_args);
            result_code = c.stmt_execute(self.handle, c_args.ptr, a.len, &rows_changed);
        } else {
            result_code = c.stmt_execute(self.handle, null, 0, &rows_changed);
        }

        if (result_code != 10) {
            std.log.err("Statement execution failed with code: {any}\n", .{result_code});
            return StatementError.ExecuteFailed;
        } else if (result_code == 10) {
            return;
        } else {
            return StatementError.ExecuteFailed;
        }
    }

    fn query(self: *Statement, args: []LimboValue) !RowResult {
        var rows_handle: ?*anyopaque = undefined;
        if (args.len == 0) {
            rows_handle = c.stmt_query(self.handle, null, args.len);
        } else {
            const c_args = try Statement.handle_args(self.allocator, args);
            defer self.allocator.free(c_args);
            rows_handle = c.stmt_query(self.handle, c_args.ptr, args.len);
        }

        if (rows_handle != null) {
            // If the query was successful, we can process the rows.
            // For now, we just return true to indicate success.
            // In a real implementation, you would fetch and process the rows here.
            const rows = try self.allocator.create(Rows);
            rows.* = Rows{
                .handle = rows_handle,
                .allocator = self.allocator,
            };
            return RowResult{
                .value = ResultValue.Ok,
                .changed = 0, // This would typically be the number of rows returned.
                .rows = rows,
            };
        } else {
            std.log.err("Query execution failed\n", .{});
            return RowResult{
                .value = ResultValue.Error,
                .changed = 0, // This would typically be the number of rows returned.
            };
        }
    }

    fn close(self: *Statement) void {
        if (self.handle) |h| {
            _ = c.stmt_close(h);
        }
    }
};

pub const Db = struct {
    const Self = @This();

    handle: ?*anyopaque,
    allocator: Allocator,

    pub const Mode = union(enum) {
        File: []const u8,
        Memory,
    };

    // TODO: not supported on rust/c side yet. Defaults to create in Turso.
    // pub const OpenFlags = struct {
    //     write: bool = false,
    //     create: bool = false,
    // };

    pub fn init(allocator: Allocator, mode: Mode) DbError!Db {
        const path: []const u8 = switch (mode) {
            .File => mode.File,
            .Memory => ":memory:",
        };
        const db_handle = c.db_open(path.ptr);
        if (db_handle == null) {
            return DbError.ConnectionFailed;
        }
        return Self{ .handle = db_handle, .allocator = allocator };
    }

    pub fn close(self: *Db) void {
        if (self.handle) |h| {
            c.db_close(h);
        }
    }

    pub fn exec(self: *Db, query: []const u8, args: ?[]LimboValue) !void {
        const query_lower: []const u8 = try std.ascii.allocLowerString(self.allocator, query);
        defer self.allocator.free(query_lower);

        var stmt: Statement = try self.prepare(query);
        defer stmt.close();

        if (std.mem.startsWith(u8, query_lower, "insert") or
            std.mem.startsWith(u8, query_lower, "update") or
            std.mem.startsWith(u8, query_lower, "create") or
            std.mem.startsWith(u8, query_lower, "delete") or
            std.mem.startsWith(u8, query_lower, "drop"))
        {
            if (args) |a| {
                try stmt.execute(a);
                return;
            } else {
                try stmt.execute(null);
                return;
            }
        } else if (std.mem.startsWith(u8, query_lower, "select"))
        {
            // TODO:
            // _ = try stmt.query(args);

            // self.rows = res.rows;
            // return Result{
            //     .value = res.value,
            //     .changed = res.changed,
            // };
            // return;
            return
        } else {
            // Other statements are not implemented yet.
            return StatementError.NotImplemented;
        }
    }

    pub fn prepare(self: *Db, query: []const u8) !Statement {
        const stmt_handle = c.db_prepare(self.handle, query.ptr);
        if (stmt_handle == null) {
            return StatementError.PrepareFailed;
        }
        return Statement{
            .handle = stmt_handle,
            .allocator = self.allocator,
        };
    }

    fn 
};
//
// pub const Cursor = struct {
//     array_size: i64,
//     statement_str: ?[]const u8,
//     conn: *Db,
//     rows: ?*Rows = null,
//
//     pub fn execute(self: *Cursor, query: []const u8, args: []LimboValue) !Result {
//         const query_lower: []const u8 = try std.ascii.allocLowerString(self.conn.allocator, query);
//         defer self.conn.allocator.free(query_lower);
//
//         var stmt: Statement = try self.prepare(query);
//         defer stmt.close();
//
//         if (std.mem.startsWith(u8, query_lower, "insert") or
//             std.mem.startsWith(u8, query_lower, "update") or
//             std.mem.startsWith(u8, query_lower, "create") or
//             std.mem.startsWith(u8, query_lower, "delete") or
//             std.mem.startsWith(u8, query_lower, "drop"))
//         {
//             const res: Result = try stmt.execute(args);
//             return res;
//         } else if (std.mem.startsWith(u8, query_lower, "select") or
//             std.mem.startsWith(u8, query_lower, "alter"))
//         {
//             const res: RowResult = try stmt.query(args);
//             self.rows = res.rows;
//             return Result{
//                 .value = res.value,
//                 .changed = res.changed,
//             };
//         } else {
//             // Other statements are not implemented yet.
//             return StatementError.NotImplemented;
//         }
//     }
//
//     fn prepare(self: *Cursor, query: []const u8) !Statement {
//         self.statement_str = query;
//         const stmt_handle = c.db_prepare(self.conn.handle, query.ptr);
//         if (stmt_handle == null) {
//             return StatementError.PrepareFailed;
//         }
//         return Statement{
//             .handle = stmt_handle,
//             .allocator = self.conn.allocator,
//         };
//     }
//
//     pub fn fetch_one(self: *Cursor) !?Row {
//         if (self.rows == null) {
//             return null; // No rows to fetch
//         }
//
//         const row: ?Row = try self.rows.?.next();
//         if (row == null) {
//             return null; // No more rows
//         }
//
//         return row.?;
//     }
//
//     pub fn fetch_many(self: *Cursor, limit: ?usize) !?[]Row {
//         if (self.rows == null) {
//             return null; // No rows to fetch
//         }
//
//         var rows = std.ArrayList(Row).init(self.conn.allocator);
//         // if (limit != null) {
//         //     try rows.initCapacity(self.conn.allocator, limit.?);
//         // } else {
//         //     try rows.init(self.conn.allocator);
//         // }
//
//         var row: ?Row = try self.rows.?.next();
//         var i: usize = 0;
//         while (row != null) {
//             if (limit != null) {
//                 if (i < limit.?) {
//                     try rows.append(row.?);
//                 } else {
//                     break;
//                 }
//             } else {
//                 try rows.append(row.?);
//             }
//             row = try self.rows.?.next();
//             i += 1;
//         }
//
//         return try rows.toOwnedSlice();
//     }
// };

pub const Rows = struct {
    handle: ?*anyopaque,
    allocator: Allocator,

    pub fn next(self: *Rows) !?Row {
        if (self.handle == null) {
            return null;
        }

        const result = c.rows_next(self.handle);
        if (result != 1) {
            print("Error fetching more rows: {any}\n", .{result});
            return RowError.NoMoreRows; // No more rows
        }

        const cols = c.rows_get_columns(self.handle);

        if (cols == 0) {
            return null; // No columns returned
        }

        // var row: Row = try self.allocator.create(Row);
        // defer self.allocator.destroy(row);

        var col_list = try std.ArrayList([]u8).initCapacity(self.allocator, @intCast(cols));
        defer col_list.deinit();
        var val_list = try std.ArrayList(LimboValue).initCapacity(self.allocator, @intCast(cols));
        defer val_list.deinit();

        for (0..@intCast(cols)) |i| {
            const c_col_name = c.rows_get_column_name(self.handle, @intCast(i));
            const col_name = try self.allocator.dupe(u8, std.mem.span(c_col_name));
            // defer c.free_string(c_col_name);
            // defer self.allocator.free(col_name);
            try col_list.append(col_name);
            //
            const col_value = c.rows_get_value(self.handle, i);
            const limbo_value_ptr: *const c.LimboValue = @ptrCast(@alignCast(col_value.?));

            // print("Column name {s} = {d}\n", .{ c_col_name, limbo_value_ptr.*.value_type });
            const value_type: ValueType = @enumFromInt(limbo_value_ptr.*.value_type);
            const limbo_value = LimboValue{ .value_type = value_type, .value = switch (value_type) {
                .Integer => .{ .int_val = limbo_value_ptr.*.value.int_val },
                .Text => .{ .text_ptr = limbo_value_ptr.*.value.text_ptr },
                .Blob => .{ .blob_ptr = limbo_value_ptr.*.value.blob_ptr.? },
                .Real => .{ .real_val = limbo_value_ptr.*.value.real_val },
                .NullValue => undefined,
            } };

            try val_list.append(limbo_value);
        }

        // needs to be freed by caller
        return Row{
            .columns = try col_list.toOwnedSlice(),
            .values = try val_list.toOwnedSlice(),
        };
    }

    pub fn close(self: *Rows) void {
        if (self.handle) |h| {
            _ = c.rows_close(h);
        }
    }
};

pub const Row = struct {
    columns: [][]u8,
    values: []LimboValue,

    pub fn format(
        self: Row,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("Columns: ");
        var i: usize = 0;
        while (i < self.columns.len) {
            try writer.print("{s}, ", .{self.columns[i]});
            i += 1;
        }
        try writer.writeAll("\n");
        try writer.writeAll("Values: ");
        var k: usize = 0;
        while (k < self.values.len) {
            const val = self.values[k];
            switch (val.value_type) {
                .Integer => try writer.print("{d}, ", .{val.value.int_val}),
                .Text => try writer.print("{s}, ", .{val.value.text_ptr}),
                .Blob => try writer.print("{any}, ", .{val.value.blob_ptr}),
                .Real => try writer.print("{d}, ", .{val.value.real_val}),
                .NullValue => try writer.writeAll("NULL, "),
            }
            k += 1;
        }
        try writer.writeAll("\n");
    }
};
