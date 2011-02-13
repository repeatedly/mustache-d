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

import std.array;
import std.conv;
import std.string;
import std.traits;
import std.variant;

import std.stdio; void main() { alias Mustache!(dstring) M; alias Mustache!(string) M2; writeln(M.Node.sizeof); }

template Mustache(String = string)
{
    final class Context
    {
      private:
        enum SectionType
        {
            nil, var, func, list
        }

        struct Section
        {
            SectionType type;

            union
            {
                String[String]          var;
                String delegate(String) func;  // String delegate(String) delegate()?
                Context[]               list;
            }

            this(String[String] v)
            {
                type  = SectionType.var;
                var = v;
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
                case SectionType.var:
                    return !var.length;  // Why?
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
         * Params:
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
             case SectionType.var:
                v = p.var;
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


      private:
        /**
         * Fetches $(D_PARAM)'s value. This method follows parent context.
         *
         * Params:
         *  key = key string to fetch
         * 
         * Returns:
         *  a $(D_PARAM key) associated value.　null if key does not exist.
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

        nothrow SectionType fetchableSectionType(String key) const
        {
            auto result = key in sections;
            if (result !is null)
                return result.type;

            if (parent is null)
                return SectionType.nil;

            return parent.fetchableSectionType(key);
        }

        nothrow const(Result) fetchSection(Result, SectionType type, string name)(String key) const
        {
            auto result = key in sections;
            if (result !is null && result.type == type)
                return mixin("result." ~ to!String(type));

            if (parent is null)
                return null;

            return mixin("parent.fetch" ~ name ~ "(key)");
        }

        alias fetchSection!(Context[],               SectionType.list, "List") fetchList;
        alias fetchSection!(String delegate(String), SectionType.func, "Func") fetchFunc;
        alias fetchSection!(String[String],          SectionType.var,  "Var")  fetchVar;
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
            // workaround for dstring initialization
            // String[String] aa = ["name" : "Ritsu"];
            String[String] aa;
            aa["name"] = "Ritsu";

            context["Value"] = aa;
            assert(context.fetchVar("Value")["name"] == aa["name"]);
            // @@@BUG@@@ Why following assert raises signal?
            //assert(context.fetchVar("Value") == aa);
            //writeln(context.fetchVar("Value") == aa);  // -> true
        }
        { // func
            auto func = (String str) { return "<b>" ~ str ~ "</b>"; };

            context["Wrapped"] = func;
            assert(context.fetchFunc("Wrapped")("Ritsu") == func("Ritsu"));
        }
    }


    Node[] compile(String src)
    {
        /**
         * State capturing for section
         */
        struct Memo
        {
            String key;
            Node[] nodes;
            String source;
        }

        String startTag = "{{";
        String endTag   = "}}";
        Node[] result;
        Memo[] stack;  // for nested section

        while (true) {
            auto hit = src.indexOf(startTag);
            if (hit == -1) {  // rest template does not have tags
                if (src.length > 0)
                    result ~= Node(src);
                break;
            } else {
                if (hit > 0)
                    result ~= Node(src[0..hit]);
                src = src[hit + startTag.length..$];
            }

            auto end = src.indexOf(endTag);
            if (end == -1)
                throw new Exception("Mustache tag is not closed");

            immutable type = src[0];
            switch (type) {
            case '#', '^':
                auto key = src[1..end].strip();
                result  ~= Node(NodeType.section, key, type == '^');
                stack   ~= Memo(key, result, src[end + endTag.length..$]);
                result   = null;
                break;
            case '/':
                auto key = src[1..end].strip();
                if (stack.empty)
                    throw new Exception(to!string(key) ~ " is unopened");
                auto memo = stack.back; stack.popBack();
                if (key != memo.key)
                    throw new Exception(to!string(key) ~ " is different from " ~ to!string(memo.key));

                auto temp = result;
                result = memo.nodes;
                result[$ - 1].childs = temp;
                result[$ - 1].source = memo.source[0..src.ptr - memo.source.ptr - endTag.length];
                break;
            case '>':
                result ~= Node(NodeType.partial, src[1..end].strip());
                break;
            case '=':
                auto newTags = src[1..end - 1].split();
                startTag = newTags[0];
                endTag   = newTags[1];
                break;
            case '!':
                break;
            case '{':
                auto pos = end + endTag.length;
                if (pos >= src.length || src[pos] != '}')
                    throw new Exception("Unescaped tag is mismatched");
                result ~= Node(NodeType.var, src[1..end++].strip(), true);
                break;
            case '&':
                result ~= Node(NodeType.var, src[1..end].strip(), true);
                break;
            default:
                result ~= Node(NodeType.var, src[0..end].strip());
                break;
            }

            src = src[end + endTag.length..$];
        }

        return result;
    }

    unittest
    {
        {  // text and unescape
            auto nodes = compile("Hello {{{name}}}");
            assert(nodes[0].type == NodeType.text);
            assert(nodes[0].text == "Hello ");
            assert(nodes[1].type == NodeType.var);
            assert(nodes[1].key  == "name");
            assert(nodes[1].flag == true);
        }
        {  // section and escape
            auto nodes = compile("{{#in_ca}}\nWell, ${{taxed_value}}, after taxes.\n{{/in_ca}}");
            assert(nodes[0].type   == NodeType.section);
            assert(nodes[0].key    == "in_ca");
            assert(nodes[0].flag   == false);
            assert(nodes[0].source == "\nWell, ${{taxed_value}}, after taxes.\n");

            auto childs = nodes[0].childs;
            assert(childs[0].type == NodeType.text);
            assert(childs[0].text == "\nWell, $");
            assert(childs[1].type == NodeType.var);
            assert(childs[1].key  == "taxed_value");
            assert(childs[1].flag == false);
            assert(childs[2].type == NodeType.text);
            assert(childs[2].text == ", after taxes.\n");
        }
        {  // inverted section
            auto nodes = compile("{{^repo}}\n  No repos :(\n{{/repo}}");
            assert(nodes[0].type == NodeType.section);
            assert(nodes[0].key  == "repo");
            assert(nodes[0].flag == true);

            auto childs = nodes[0].childs;
            assert(childs[0].type == NodeType.text);
            assert(childs[0].text == "\n  No repos :(\n");
        }
        {  // partial and set delimiter
            auto nodes = compile("{{=<% %>=}}<%> erb_style %>");
            assert(nodes[0].type == NodeType.partial);
            assert(nodes[0].key  == "erb_style");
        }
    }


  private:
    /**
     * Mustache's node types
     */
    enum NodeType
    {
        text,     /// outside tag
        var,      /// {{}} or {{{}}} or {{&}}
        section,  /// {{#}} or {{^}}
        partial   /// {{<}}
    }


    /**
     * Represents a Mustache node. Currently prototype.
     */
    struct Node
    {
        NodeType type;

        union
        {
            String text;

            struct
            {
                String key;
                bool   flag;    // true is inverted or unescape
                Node[] childs;  // for list section
                String source;  // for lambda section
            }
        }


        /**
         * Constructs with arguments.
         *
         * Params:
         *   t = raw text
         */
        this(String t)
        {
            type = NodeType.text;
            text = t;
        }

        /**
         * ditto
         *
         * Params:
         *   t = Mustache's node type
         *   k = key string of tag
         *   f = invert? or escape?
         */
        this(NodeType t, String k, bool f = false)
        {
            type = t;
            key  = k;
            flag = f;
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
            case NodeType.text:
                result = "[T : \"" ~ to!string(text) ~ "\"]";
                break;
            case NodeType.var:
                result = "[" ~ (flag ? "E" : "V") ~ " : \"" ~ to!string(key) ~ "\"]";
                break;
            case NodeType.section:
                result = "[" ~ (flag ? "I" : "S") ~ " : \"" ~ to!string(key) ~ "\", [ ";
                foreach (ref node; childs)
                    result ~= node.toString() ~ " ";
                result ~= "], \"" ~ to!string(source) ~ "\"]";
                break;
            case NodeType.partial:
                result = "[P : \"" ~ to!string(key) ~ "\"]";
                break;
            }

            return result;
        }
    }

    unittest
    {
        Node section;
        Node[] nodes, childs;

        nodes ~= Node("Hi ");
        nodes ~= Node(NodeType.var, "name");
        nodes ~= Node(NodeType.partial, "redbull");
        {
            childs ~= Node("Ritsu is ");
            childs ~= Node(NodeType.var, "attr", true);
            section = Node(NodeType.section, "ritsu", false);
            section.childs = childs;
            nodes ~= section;
        }

        assert(to!string(nodes) == `[[T : "Hi "], [V : "name"], [P : "redbull"], `
                                   `[S : "ritsu", [ [T : "Ritsu is "] [E : "attr"] ], ""]]`);
    }
}
