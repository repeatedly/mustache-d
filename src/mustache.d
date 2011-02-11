/**
 * Mustache template engine for D
 *
 * Implemented according to $(WEB mustache.github.com/mustache.5.html, mustache(5)).
 *
 * Copyright: Copyright Masahiro Nakagawa 2011-.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
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
            nil, value, func, list
        }

        struct Section
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

            this(String delegate(String) f)
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
                case SectionType.nil:
                    return true;
                case SectionType.value:
                    return !value.length;  // Why?
                case SectionType.func:
                    return func is null;
                case SectionType.list:
                    return !list.length;
                }
            }
        }

        Context         parent;
        String[String]  variables;
        Section[String] sections;


      public:
        this(Context context = null)
        {
            parent = context;
        }

        /**
         * Gets $(D_PARAM key)'s value. This method does not search Section.
         *
         * Params:
         *  key = key string to search
         *
         * Returns:
         *  a $(D_PARAM key) associated value.
         *
         * Throws:
         *  a RangeError if $(D_PARAM key) does not exist.
         */
        nothrow String opIndex(String key) const
        {
            return variables[key];
        }

        /**
         * Assigns $(D_PARAM value)(automatically convert to String) to $(D_PARAM key) field.
         *
         * If you try to assign associative array or delegate,
         * This method assigns $(D_PARAM value) as Section.
         *
         * Params:
         *  value = some type value to assign
         *  key   = key string to assign
         */
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

                    sections[key] = Section(aa);
                }
                else static assert(false, "Non-supported Associative Array type");
            }
            else static if (is(T == delegate))
            {
                static if (is(T D == S delegate(S), S : String))
                    sections[key] = Section(value);
                else static assert(false, "Non-supported delegate type");
            }
            else
            {
                variables[key] = to!String(value);
            }
        }

        /**
         * Gets $(D_PARAM key)'s section value for Phobos friends.
         *
         * Params*
         *  key = key string to get
         *
         * Returns:
         *  section wrapped Variant.
         */
        Variant section(String key)
        {
            auto p = key in sections;
            if (!p)
                return Variant.init;

            Variant v = void;

            final switch (p.type) {
            case SectionType.nil:
                v = Variant.init;
             case SectionType.value:
                v = p.value;
            case SectionType.func:
                v = p.func;
            case SectionType.list:
                v = p.list;
           }

            return v;
        }

        /**
         * Adds new context to $(D_PARAM key)'s section. This method overwrites with
         * list type if you already assigned other type to $(D_PARAM key)'s section.
         *
         * Params:
         *  key  = key string to add
         *  size = reserve size for avoiding reallocation
         *
         * Returns:
         *  new Context object that added to $(D_PARAM key) section list. 
         */
        Context addSubContext(String key, lazy size_t size = 1)
        {
            auto c = new Context(this);
            auto p = key in sections;
            if (!p || p.type != SectionType.list) {
                sections[key] = Section(c);
                sections[key].list.reserve(size);
            } else {
                sections[key].list ~= c;
            }

            return c;
        }

        /**
         * Fetches $(D_PARAM)'s value. This method follows parent context.
         *
         * Params:
         *  key = key string to fetch
         * 
         * Returns:
         *  a $(D_PARAM key) associated value.
         */
        nothrow String fetch(String key) const
        {
            auto result = key in variables;
            if (result !is null)
                return *result;

            if (parent is null)
                return null;

            return parent.fetch(key);
        }

        /* nothrow : Section.empty() is not nothrow. See above comment */ 
        private const(Result) fetchSection(Result, SectionType type, string name)(String key) const
        {
            auto result = key in sections;
            if (result !is null && result.type == type)
                return mixin("result." ~ to!String(type));

            if (parent is null)
                return null;

            return mixin("parent.fetch" ~ name ~ "(key)");
        }

        alias fetchSection!(Context[],               SectionType.list,  "List")  fetchList;
        alias fetchSection!(String delegate(String), SectionType.func,  "Func")  fetchFunc;
        alias fetchSection!(String[String],          SectionType.value, "Value") fetchValue;


    private:
        SectionType fetchableSectionType(String key)
        {
            auto result = key in sections;
            if (result !is null)
                return result.type;

            if (parent is null)
                return SectionType.nil;

            return parent.fetchableSectionType(key);
        }
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
                sub["num"] = i;

                foreach (b; [true, false]) {
                    auto subsub = sub.addSubContext("subsub");
                    subsub["To be or not to be"] = b;
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
            auto func = (String str) { return "<b>" ~ str ~ "</b>"; };

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
