/**
 * Mustache template engine for D
 *
 * Implemented according to $(WEB mustache.github.com/mustache.5.html, mustache(5)).
 *
 * Copyright: Copyright Masahiro Nakagawa 2011-.
 * License:   <a href = "http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Masahiro Nakagawa
 */
module mustache;

import std.conv;
import std.traits;
import std.variant;


template Mustache(String = string)
{
    final class Context
    {
      private:
        enum SectionType
        {
            value, func, list
        }

        struct Value
        {
            SectionType type;

            union
            {
                String[String]          value;
                String delegate(String) func;  // String delegate(String) delegate()?
                Context[]               list;
            }

            this(String[String] v)
            {
                type  = SectionType.value;
                value = v;
            }

            this(string delegate(string) f)
            {
                type = SectionType.func;
                func = f;
            }

            this(Context c)
            {
                type = SectionType.list;
                list = [c];
            }

            /* nothrow : AA's length is not nothrow */
            bool empty() const
            {
                final switch (type) {
                case SectionType.value:
                    return !value.length;  // Why?
                case SectionType.func:
                    return func is null;
                case SectionType.list:
                    return !list.length;
                }
            }
        }

        Context        parent;
        String[String] variables;
        Value[String]  sections;


      public:
        this(Context context = null)
        {
            parent = context;
        }

        nothrow String opIndex(String key) const
        {
            return variables[key];
        }

        void opIndexAssign(T)(T value, String key)
        {
            static if (isAssociativeArray!(T))
            {
                static if (is(T V : V[K], K : String))
                {
                    String[String] aa;

                    static if (is(V == String))
                        aa = value;
                    else
                        foreach (k, v; value) aa[k] = to!String(v);

                    sections[key] = Value(aa);
                }
                else static assert(false, "Non-supported Associative Array type");
            }
            else static if (is(T == delegate))
            {
                static if (is(T D == S delegate(S), S : String))
                    sections[key] = Value(value);
                else static assert(false, "Non-supported delegate type");
            }
            else
            {
                variables[key] = to!String(value);
            }
        }

        Variant section(String key)
        {
            auto p = key in sections;
            if (!p || p.empty())
                return Variant.init;

            Variant v;

            final switch (p.type) {
            case SectionType.value:
                v = p.value;
            case SectionType.func:
                v = p.func;
            case SectionType.list:
                v = p.list;
            }

            return v;
        }

        Context addSubContext(String key, lazy size_t size = 10)
        {
            auto c = new Context(this);
            auto p = key in sections;
            if (!p || p.type != SectionType.list) {
                sections[key] = Value(c);
                sections[key].list.reserve(size);
            } else {
                sections[key].list ~= c;
            }

            return c;
        }

        nothrow String fetch(String key) const
        {
            auto result = key in variables;
            if (result !is null)
                return *result;

            if (parent is null)
                return null;

            return parent.fetch(key);
        }


      private:
        /* nothrow : Value.empty() is not nothrow. See above comment */ 
        const(Result) fetchBody(Result, SectionType type, string name)(String key) const
        {
            auto result = key in sections;
            if (result !is null && result.type == type)
                return result.empty() ? null : mixin("result." ~ to!String(type));

            if (parent is null)
                return null;

            return mixin("parent.fetch" ~ name ~ "(key)");
        }

        alias fetchBody!(Context[],               SectionType.list,  "List")  fetchList;
        alias fetchBody!(String delegate(String), SectionType.func,  "Func")  fetchFunc;
        alias fetchBody!(String[String],          SectionType.value, "Value") fetchValue;
    }

    unittest
    {
        Context context = new Context();

        context["name"] = "Red Bull";
        assert(context["name"] == "Red Bull");
        context["price"] = 275;
        assert(context["price"] == "275");

        { // list
            foreach (i; 100..105) {
                auto sub = context.addSubContext("sub");
                sub.opIndexAssign(i, "num");

                foreach (b; [true, false]) {
                    auto subsub = sub.addSubContext("subsub");
                    subsub.opIndexAssign(b, "To be or not to be");
                }
            }

            foreach (i, sub; context.fetchList("sub")) {
                assert(sub.fetch("name") == "Red Bull");
                assert(sub["num"] == to!String(i + 100));

                foreach (j, subsub; sub.fetchList("subsub")) {
                    assert(subsub.fetch("price") == to!String(275));
                    assert(subsub["To be or not to be"] == to!String(j == 0));
                }
            }
        }
        { // value
            String[String] aa = ["name" : "Ritsu"];

            context["Value"] = aa;
            assert(context.fetchValue("Value")["name"] == aa["name"]);
            // @@@BUG@@@ Why following assert raises signal?
            //assert(context.fetchValue("Value") == aa);
            //writeln(context.fetchValue("Value") == aa);  // -> true
        }
        { // func
            auto func = (string str) { return "<b>" ~ str ~ "</b>"; };

            context["Wrapped"] = func;
            assert(context.fetchFunc("Wrapped")("Ritsu") == func("Ritsu"));
        }
    }


  private:
    /**
     * Mustache's tag types
     */
    enum TagType
    {
        nil,     ///
        var,     /// {{}}
        raw,     /// {{{}}} or {{&}}
        section  /// {{#}} or {{^}}
    }


    /**
     * Represents a Mustache node. Currently prototype.
     */
    struct Node
    {
        TagType type;  /// node type as Mustache tag

        union
        {
            struct Section
            {
                Node[] nodes;
                bool   invert;
            }

            struct Variable
            {
                String text;
                bool   escape;
            }
        }

        /**
         * Constructs with argument type.
         *
         * Params:
         *   type = A Mustache tag type.
         */
        this(TagType t)
        {
            type = t;
        }

        /**
         * Represents the internal status as a string.
         *
         * Returns:
         *  stringized node representation.
         */
        string toString() const
        {
            string result;

            switch (type) {
            case TagType.section:
                result ~= "Section";
                break;
            case TagType.var:
                result ~= "Variable";
                break;
            default:
                result ~= "Raw Text";
                break;
            }

            return result;
        }
    }
}
