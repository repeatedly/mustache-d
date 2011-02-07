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


template Mustache(String = string)
{
    final class Context
    {
      private:
        Context           parent;
        String[String]    variables;
        Context[][String] sections;


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
                foreach (k, v; value) {
                    auto context = section(key); 
                    context[k] = v;
                }
            }
            else
            {
                variables[key] = to!String(value);
            }
        }

        Context section(String key, lazy size_t size = 10)
        {
            bool    first  = key in sections ? true : false;
            Context result = new Context(this);

            sections[key] ~= result;
            if (first)
                sections[key].reserve(size);

            return result;
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

        nothrow const(Context[]) fetchSection(String key) const
        {
            auto result = key in sections;
            if (result !is null)
                return *result;

            if (parent is null)
                return null;

            return parent.fetchSection(key);
        }
    }

    unittest
    {
        Context context = new Context();

        context["name"] = "Red Bull";
        assert(context["name"] == "Red Bull");
        context["price"] = 275;
        assert(context["price"] == "275");

        foreach (i; 100..105) {
            auto sub = context.section("sub");
            sub.opIndexAssign(i, "num");

            foreach (b; [true, false]) {
                auto subsub = sub.section("subsub");
                subsub.opIndexAssign(b, "To be or not to be");
            }
        }

        foreach (i, ref sub; context.fetchSection("sub")) {
            assert(sub.fetch("name") == "Red Bull");
            assert(sub["num"] == to!String(i + 100));

            foreach (j, ref subsub; sub.fetchSection("subsub")) {
                assert(subsub.fetch("price") == to!String(275));
                assert(subsub["To be or not to be"] == to!String(j == 0));
            }
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
