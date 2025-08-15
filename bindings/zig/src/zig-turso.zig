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
    InvalidStatement,
    QueryFailed,
};

pub const RowError = error{
    NoMoreRows,
    NullPointer,
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

// pub const RowResult = struct {
//     value: ResultValue,
//     changed: i64,
//     rows: ?*Rows,
//
//     // pub fn format(self: Result, fmt: anytype) !void {
//     //     try fmt.print("Result(value: {any}, changed: {any})", .{ self.value, self.changed });
//     // }
// };

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
    blob_ptr: ?*const anyopaque,
};

pub const LimboValue = struct {
    value_type: ValueType,
    value: ValueUnion,

    pub fn to_c(self: LimboValue) c.LimboValue {
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

    pub fn from_c(c_limbo: *const c.LimboValue, limbo: *LimboValue) void {
        const value_type: ValueType = @enumFromInt(c_limbo.value_type);
        std.log.debug("Value_type: {any}\n", .{value_type});
        limbo.* = LimboValue{
            .value_type = value_type,
            .value = switch (value_type) {
                .Integer => ValueUnion{ .int_val = @intCast(c_limbo.*.value.int_val) },
                .Text => ValueUnion{ .text_ptr = c_limbo.*.value.text_ptr },
                .Blob => ValueUnion{ .blob_ptr = c_limbo.*.value.blob_ptr },
                .Real => ValueUnion{ .real_val = c_limbo.*.value.real_val },
                .NullValue => undefined,
            },
        };
    }
};

pub const Db = struct {
    const Self = @This();

    handle: ?*anyopaque,

    pub const Mode = union(enum) {
        File: []const u8,
        Memory,
    };

    // TODO: not supported on rust/c side yet. Defaults to create in Turso.
    // pub const OpenFlags = struct {
    //     write: bool = false,
    //     create: bool = false,
    // };

    pub fn init(mode: Mode) DbError!Db {
        const path: []const u8 = switch (mode) {
            .File => mode.File,
            .Memory => ":memory:",
        };
        const db_handle = c.db_open(path.ptr);
        if (db_handle == null) {
            return DbError.ConnectionFailed;
        }
        return Self{ .handle = db_handle };
    }

    pub fn close(self: *Db) void {
        if (self.handle) |h| {
            c.db_close(h);
        }
    }

    pub fn exec(self: *Db, allocator: Allocator, comptime query: []const u8, args: ?[]LimboValue) !void {
        var query_lower: [query.len]u8 = undefined;
        // std.ascii.lowerString(@as([]u8, @ptrCast(@constCast(&query_lower))), query);

        for (query, 0..) |ch, i| {
            query_lower[i] = std.ascii.toLower(ch);
        }

        var stmt: Statement = try self.prepare(allocator, query);
        defer stmt.close();

        if (std.mem.startsWith(u8, &query_lower, "insert") or
            std.mem.startsWith(u8, &query_lower, "update") or
            std.mem.startsWith(u8, &query_lower, "create") or
            std.mem.startsWith(u8, &query_lower, "delete") or
            std.mem.startsWith(u8, &query_lower, "drop"))
        {
            if (args) |a| {
                try stmt.execute(a);
                return;
            } else {
                try stmt.execute(null);
                return;
            }
        } else if (std.mem.startsWith(u8, &query_lower, "select")) {
            print("When executing a select statement, use the prepare method instead to get a prepared statement.\n", .{});
            return StatementError.InvalidStatement;
        } else {
            // Other statements are not implemented yet.
            return StatementError.NotImplemented;
        }
    }

    pub fn prepare(self: *Db, allocator: Allocator, query: []const u8) !Statement {
        const stmt_handle = c.db_prepare(self.handle, query.ptr);
        if (stmt_handle == null) {
            return StatementError.PrepareFailed;
        }
        return Statement{
            .handle = stmt_handle,
            .allocator = allocator,
        };
    }

    pub fn oneAlloc(self: *Self, allocator: Allocator, comptime query: []const u8, comptime T: type, args: ?[]LimboValue, values: anytype) !?T {
        var query_lower: [query.len]u8 = undefined;

        for (query, 0..) |ch, i| {
            query_lower[i] = std.ascii.toLower(ch);
        }

        // TODO: implement usage of `values` parameter
        _ = values;

        var rows: Rows = undefined;
        defer rows.close();
        var row_slice: ?[]LimboValue = undefined;
        defer allocator.free(row_slice.?);

        if (std.mem.startsWith(u8, &query_lower, "select")) {
            var stmt: Statement = try self.prepare(allocator, query);
            defer stmt.close();
            rows = try stmt.query(args orelse &.{});
            row_slice = try rows.one(allocator);
        }

        // parse slice into T
        var instance: T = undefined;
        const fields = std.meta.fields(T);

        inline for (fields, 0..) |field, i| {
            const limbo_value = row_slice.?[i];
            switch (limbo_value.value_type) {
                .Integer => {
                    if (field.type == i64) {
                        @field(instance, field.name) = limbo_value.value.int_val;
                    } else {
                        std.log.err("Field {s} is of type {s}, but LimboValue is Integer.\n", .{ field.name, @typeName(field.type) });
                        return null;
                    }
                },
                .Text => {
                    if (field.type == []const u8) {
                        @field(instance, field.name) = std.mem.span(limbo_value.value.text_ptr);
                    } else {
                        std.log.err("Field {s} is of type {s}, but LimboValue is Text.\n", .{ field.name, @typeName(field.type) });
                        return null;
                    }
                },
                .Blob => {
                    std.log.err("Database returned blob type. Blobs not supported in Zig bindings.\n", .{});
                    return null;
                },
                .Real => {
                    if (field.type == f64) {
                        @field(instance, field.name) = limbo_value.value.real_val;
                    } else {
                        std.log.err("Field {s} is of type {s}, but LimboValue is Real.\n", .{ field.name, @typeName(field.type) });
                        return null;
                    }
                },
                .NullValue => {},
            }
        }

        return instance;
    }
};

const Statement = struct {
    handle: ?*anyopaque,
    allocator: Allocator,

    fn handle_args(allocator: Allocator, args: []LimboValue) ![]c.LimboValue {
        var c_args = try allocator.alloc(c.LimboValue, args.len);

        for (args, 0..) |arg, i| {
            const c_arg = arg.to_c();
            c_args[i] = c_arg;
        }

        return c_args;
    }

    pub fn execute(self: *Statement, args: ?[]LimboValue) !void {
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

    pub fn query(self: *Statement, args: []LimboValue) !Rows {
        var rows_handle: ?*anyopaque = undefined;

        if (args.len == 0) {
            std.log.debug("No args passed to query method.", .{});
            rows_handle = c.stmt_query(self.handle, null, args.len);
        } else {
            std.log.debug("Args of length {d} passed to query method.", .{args.len});
            const c_args = try Statement.handle_args(self.allocator, args);
            defer self.allocator.free(c_args);
            rows_handle = c.stmt_query(self.handle, c_args.ptr, args.len);
        }

        if (rows_handle != null) {
            return Rows{
                .handle = rows_handle,
            };
        } else {
            std.log.err("Query execution failed.\n", .{});
            return StatementError.QueryFailed;
        }
    }

    pub fn close(self: *Statement) void {
        if (self.handle) |h| {
            _ = c.stmt_close(h);
        }
    }
};

pub const Rows = struct {
    handle: ?*anyopaque,

    pub fn one(self: Rows, allocator: Allocator) !?[]LimboValue {
        if (self.handle == null) {
            return null;
        }

        const has_next = c.rows_next(self.handle);
        if (has_next != 1) {
            print("Error fetching more rows: {any}\n", .{has_next});
            return RowError.NoMoreRows; // No more rows
        }
        std.log.debug("has_next is 1.", .{});

        const cols = c.rows_get_columns(self.handle);

        if (cols == 0) {
            return null; // No columns returned
        }

        var row = try std.ArrayList(LimboValue).initCapacity(allocator, @intCast(cols));
        defer row.deinit();

        for (0..@intCast(cols)) |col_idx| {
            const val_handle = c.rows_get_value(self.handle, col_idx);
            if (val_handle == null) {
                std.log.err("Value handle is null. Could not get value from database.", .{});
                return RowError.NullPointer;
            }

            const limbo_value: *const c.LimboValue = @ptrCast(@alignCast(val_handle));
            std.log.debug("C limboValue.value_type: {any}\n", .{limbo_value.*.value_type});
            var zig_value: LimboValue = undefined;

            LimboValue.from_c(limbo_value, &zig_value);
            try row.append(zig_value);
        }

        // const t_fields = std.meta.fields(T);
        const row_slice = try row.toOwnedSlice();
        // defer allocator.free(row_slice);

        // var res: T = undefined;
        // var res: T = try allocator.create(T);
        // var res: [cols]LimboValue = undefined;

        // std.log.debug("Looping fields and switching on row_slice\n", .{});
        // inline for (t_fields, 0..) |field, i| {
        //     switch (row_slice[i].value) {
        //         .int_val => |v| {
        //             if (@TypeOf(v) == field.type) {
        //                 const v_heap = try allocator.create(@TypeOf(v));
        //                 v_heap.* = v;
        //                 @field(res, field.name) = v_heap;
        //             }
        //         },
        //         .real_val => |v| {
        //             if (@TypeOf(v) == field.type) {
        //                 const v_heap = try allocator.create(@TypeOf(v));
        //                 v_heap.* = v;
        //                 @field(res, field.name) = v_heap;
        //             }
        //         },
        //         .text_ptr => |v| {
        //             if (@TypeOf(v) == field.type) {
        //                 const zig_ptr = allocator.dupe(u8, std.mem.span(v));
        //                 @field(res, field.name) = zig_ptr;
        //             }
        //         },
        //         .blob_ptr => |v| {
        //             if (@TypeOf(v) == field.type) {
        //                 const zig_ptr = allocator.dupe(u8, std.mem.span(v));
        //                 @field(res, field.name) = zig_ptr;
        //             }
        //         },
        //         // else => unreachable,
        //     }
        // }

        // for (row_slice) |val| {
        //     switch (val.value_type) {
        //         .Integer => res[i] = LimboValue{ .value_type = .Integer, .value = .{ .int_val = limbo_value.value.int_val } },
        //         .Text => res[i] = LimboValue{ .value_type = .Text, .value = .{ .text_ptr = limbo_value.value.text_ptr } },
        //         .Blob => res[i] = LimboValue{ .value_type = .Blob, .value = .{ .blob_ptr = limbo_value.value.blob_ptr } },
        //         .Real => res[i] = LimboValue{ .value_type = .Real, .value = .{ .real_val = limbo_value.value.real_val } },
        //         .NullValue => res[i] = LimboValue{ .value_type = .NullValue, .value = undefined },
        //     }
        // }
        std.log.debug("Returning result: {any}\n", .{row_slice});
        return row_slice;
    }

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
            // defer c.free_string(c_col_name);
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
        std.log.debug("Closing rows.", .{});
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
