/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The purpose of this module is to allow you to segregate your `string` data that
represent a path from the rest. A string-that-is-a-type have specific
characteristics that we want to represent. This module have two types that help
you encode these characteristics.

This allows you to construct type safe APIs wherein a parameter that takes a
path can be assured that the data **actually** is a path. The API can further
e.g. require the parameter to be have the even higher restriction that it is an
absolute path.

I have found it extremely useful in my own programs to internally only work
with `AbsolutePath` types. There is a boundary in my programs that takes data
and converts it appropriately to `AbsolutePath`s. This is usually configuration
data, command line input, external libraries etc. This conversion layer handles
the defensive coding, validity checking etc that is needed of the data.

This has overall lead to a significant reduction in the number of bugs I have
had when handling paths and simplified the code. The program normally look
something like this:

* user input as raw strings via e.g. `getopt`.
* wrap path strings as either `Path` or `AbsolutePath`. Prefer `AbsolutePath`
  when applicable but there are cases where this is the wrong behavior. Lets
  say that the user input is relative to some working directory. Then later on
  in your program the two are combined to produce an `AbsolutePath`.
* internally in the program all parameters are `AbsolutePath`. A function that
  takes an `AbsolutePath` can be assured it is a path, full expanded and thus
  do not need any defensive code. It can use it as it is.

I have used an equivalent program structure when interacting with external
libraries.
*/
module my.path;

import std.range : isOutputRange, put;
import std.path : dirName, baseName, buildPath;

/** Types a string as a `Path` to provide path related operations.
 *
 * A `Path` is subtyped as a `string` in order to make it easy to integrate
 * with the Phobos APIs that take a `string` as an argument. Example:
 * ---
 * auto a = Path("foo");
 * writeln(exists(a));
 * ---
 *
 * The string that represent paths are deduplicated and cached. This is to
 * reduce the amount of memory that paths in your program occupy. This either
 * have none impact on your program or it may be significant. Usually you do
 * not have to care about this fact, the type do it for you.
 *
 * TODO: maybe make the cache:ing configurable and global? It is currenly
 * thread local and the cache is unbounded.
 */
struct Path {
    private string value_;

    this(string s) @safe nothrow {
        if (__ctfe) {
            value_ = s;
        } else {
            const h = s.hashOf;
            if (auto v = h in pathCache) {
                value_ = *v;
            } else {
                pathCache[h] = s;
                value_ = s;
            }
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        return value_.length == 0;
    }

    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return value_ == s;
    }

    bool opEquals(const Path s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return value_.hashOf;
    }

    Path opBinary(string op)(string rhs) @safe {
        static if (op == "~") {
            return Path(buildPath(value_, rhs));
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    void opOpAssign(string op)(string rhs) @safe nothrow {
        static if (op == "~=") {
            value_ = buildNormalizedPath(value_, rhs);
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    T opCast(T : string)() const {
        return value_;
    }

    string toString() @safe pure nothrow const @nogc {
        return value_;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        put(w, value_);
    }

    Path dirName() @safe const {
        return Path(value_.dirName);
    }

    string baseName() @safe const {
        return value_.baseName;
    }

    private static string fromCache(size_t h) {
        if (pathCache.length > 1024) {
            pathCache = null;
        }
        if (auto v = h in pathCache) {
            return *v;
        }
        return null;
    }
}

private {
    // Reduce memory usage by reusing paths.
    private string[size_t] pathCache;
}

/** The path is guaranteed to be the absolute, normalized and tilde expanded
 * path.
 *
 * An `AbsolutePath` is subtyped as a `Path` in order to make it easy to
 * integrate with the Phobos APIs that take a `string` as an argument. Example:
 * ---
 * auto a = AbsolutePath("foo");
 * writeln(exists(a));
 * ---
 *
 * The type is optimized such that it avoids expensive operations when it is
 * either constructed or assigned to from an `AbsolutePath`.
 */
struct AbsolutePath {
    import std.path : buildNormalizedPath, absolutePath, expandTilde;

    private Path value_;

    this(AbsolutePath p) @safe pure nothrow @nogc {
        value_ = p.value_;
    }

    this(string p) @safe {
        this(Path(p));
    }

    this(Path p) @safe {
        value_ = Path(p.value_.expandTilde.absolutePath.buildNormalizedPath);
    }

    void opAssign(AbsolutePath p) @safe pure nothrow @nogc {
        value_ = p.value_;
    }

    void opAssign(Path p) @safe {
        value_ = p.AbsolutePath.value_;
    }

    Path opBinary(string op, T)(T rhs) @safe if (is(T == string) || is(T == Path)) {
        static if (op == "~") {
            return value_ ~ rhs;
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    void opOpAssign(string op)(T rhs) @safe if (is(T == string) || is(T == Path)) {
        static if (op == "~=") {
            value_ = AbsolutePath(value_ ~ rhs).value_;
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    string opCast(T : string)() pure nothrow const @nogc {
        return value_;
    }

    Path opCast(T : Path)() pure nothrow const @nogc {
        return value_;
    }

    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return value_ == s;
    }

    bool opEquals(const Path s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    bool opEquals(const AbsolutePath s) @safe pure nothrow const @nogc {
        return value_ == s.value_;
    }

    string toString() @safe pure nothrow const @nogc {
        return cast(string) value_;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        put(w, value_);
    }

    AbsolutePath dirName() @safe const {
        // avoid the expensive expansions and normalizations.
        AbsolutePath a;
        a.value_ = value_.dirName;
        return a;
    }

    string baseName() @safe const {
        return value_.baseName;
    }
}

@("shall always be the absolute path")
unittest {
    import std.algorithm : canFind;
    import std.path;
    import unit_threaded;

    AbsolutePath(Path("~/foo")).toString.canFind('~').shouldEqual(false);
    AbsolutePath(Path("foo")).toString.isAbsolute.shouldEqual(true);
}

@("shall expand . without any trailing /.")
unittest {
    import std.algorithm : canFind;
    import unit_threaded;

    AbsolutePath(Path(".")).toString.canFind('.').shouldBeFalse;
    AbsolutePath(Path(".")).toString.canFind('.').shouldBeFalse;
}
