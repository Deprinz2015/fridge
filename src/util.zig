const std = @import("std");

pub const log = std.log.scoped(.fridge);

pub fn tableName(comptime T: type) []const u8 {
    return comptime brk: {
        if (@hasDecl(T, "sql_table_name")) break :brk T.sql_table_name;
        const s = @typeName(T);
        const i = std.mem.lastIndexOfScalar(u8, s, '.').?;
        break :brk s[i + 1 ..];
    };
}

pub fn columns(comptime T: type) []const u8 {
    return comptime brk: {
        var res: []const u8 = "";

        for (@typeInfo(T).Struct.fields) |f| {
            if (res.len > 0) res = res ++ ", ";
            res = res ++ f.name;
        }

        break :brk res;
    };
}

pub fn placeholders(comptime T: type) []const u8 {
    return comptime brk: {
        var res: []const u8 = "";

        for (@typeInfo(T).Struct.fields) |_| {
            if (res.len > 0) res = res ++ ", ";
            res = res ++ "?";
        }

        break :brk res;
    };
}

pub fn setters(comptime T: type) []const u8 {
    return comptime brk: {
        var res: []const u8 = "";

        for (@typeInfo(T).Struct.fields) |f| {
            if (res.len > 0) res = res ++ ", ";
            res = res ++ f.name ++ " = ?";
        }

        break :brk res;
    };
}

pub fn isString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |ptr| ptr.child == u8 or switch (@typeInfo(ptr.child)) {
            .Array => |arr| arr.child == u8,
            else => false,
        },
        else => false,
    };
}

pub fn isDense(comptime E: type) bool {
    for (@typeInfo(E).Enum.fields, 0..) |f, i| {
        if (f.value != i) return false;
    }

    return true;
}

pub fn isJsonRepresentable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Array, .Struct, .Union => true,
        .Pointer => |p| p.size == .Slice,
        else => false,
    };
}

pub fn checkFields(comptime T: type, comptime D: type) void {
    comptime {
        outer: for (@typeInfo(D).Struct.fields) |f| {
            for (@typeInfo(T).Struct.fields) |f2| {
                if (std.mem.eql(u8, f.name, f2.name)) {
                    if (isAssignableTo(f.type, f2.type)) {
                        continue :outer;
                    }

                    @compileError(
                        "Type mismatch for field " ++ f.name ++
                            " found:" ++ @typeName(f.type) ++
                            " expected:" ++ @typeName(f2.type),
                    );
                }
            }

            @compileError("Unknown field " ++ f.name);
        }
    }
}

pub fn isAssignableTo(comptime A: type, B: type) bool {
    if (A == B) return true;
    if (isString(A) and isString(B)) return true;

    switch (@typeInfo(A)) {
        .ComptimeInt => if (@typeInfo(B) == .Int) return true,
        .ComptimeFloat => if (@typeInfo(B) == .Float) return true,
        else => {},
    }

    switch (@typeInfo(B)) {
        .Optional => |opt| {
            if (A == @TypeOf(null)) return true;
            if (isAssignableTo(A, opt.child)) return true;
        },
        else => {},
    }

    return false;
}

pub fn upcast(handle: anytype, comptime T: type) T {
    return .{
        .handle = handle,
        .vtable = comptime brk: {
            const Handle = @TypeOf(handle);
            const Impl = switch (@typeInfo(@TypeOf(handle))) {
                .Pointer => |ptr| ptr.child,
                else => @TypeOf(handle),
            };

            // Check the types first.
            var impl: T.VTable(Handle) = undefined;
            for (@typeInfo(@TypeOf(impl)).Struct.fields) |f| {
                if (std.meta.hasFn(Impl, f.name)) {
                    @field(impl, f.name) = @field(Impl, f.name);
                } else {
                    @compileError("Impl " ++ @typeName(Impl) ++ " is missing " ++ f.name);
                }
            }

            // Get erased vtable.
            var res: T.VTable(*anyopaque) = undefined;
            for (@typeInfo(@TypeOf(res)).Struct.fields) |f| {
                @field(res, f.name) = @ptrCast(@field(impl, f.name));
            }

            const copy = res;
            break :brk &copy;
        },
    };
}
