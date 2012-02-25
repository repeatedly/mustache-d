/**
 * Mustache template engine for D
 *
 * Implemented according to <a href="http://mustache.github.com/mustache.5.html">mustach(5)</a>.
 *
 * Copyright: Copyright Masahiro Nakagawa 2011-.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Masahiro Nakagawa
 */
module mustache;

import std.array;    // empty, back, popBack, appender
import std.conv;     // to
import std.datetime; // SysTime (I think std.file should import std.datetime as public)
import std.file;     // read, timeLastModified
import std.path;     // buildPath
import std.string;   // strip, chomp, stripLeft
import std.traits;   // isSomeString, isAssociativeArray

version(unittest) import core.thread;


/**
 * Exception for Mustache
 */
class MustacheException : Exception
{
    this(string messaage)
    {
        super(messaage);
    }
}


/**
 * Core implementation of Mustache
 *
 * $(D_PARAM String) parameter means a string type to render.
 *
 * Example:
 * -----
 * alias MustacheEngine!(string) Mustache;
 *
 * Mustache mustache;
 * auto context = new Mustache.Context;
 *
 * context["name"]  = "Chris";
 * context["value"] = 10000;
 * context["taxed_value"] = 10000 - (10000 * 0.4);
 * context.useSection("in_ca");
 *
 * write(mustache.render("sample", context));
 * -----
 * sample.mustache:
 * -----
 * Hello {{name}}
 * You have just won ${{value}}!
 * {{#in_ca}}
 * Well, ${{taxed_value}}, after taxes.
 * {{/in_ca}}
 * -----
 * Output:
 * -----
 * Hello Chris
 * You have just won $10000!
 * Well, $6000, after taxes.
 * -----
 */
struct MustacheEngine(String = string) if (isSomeString!(String))
{
    static assert(!is(String == wstring), "wstring is unsupported. It's a buggy!");


  public:
    alias String delegate() Handler;


    /**
     * Cache level for compile result
     */
    static enum CacheLevel
    {
        no,     /// No caching
        check,  /// Caches compiled result and checks the freshness of template
        once    /// Caches compiled result but not check the freshness of template
    }


    /**
     * Options for rendering
     */
    static struct Option
    {
        string     ext   = "mustache";        /// template file extenstion
        string     path  = ".";               /// root path for template file searching
        CacheLevel level = CacheLevel.check;  /// See CacheLevel
        Handler    handler;                   /// Callback handler for unknown name
    }


    /**
     * Mustache context for setting values
     *
     * Variable:
     * -----
     * //{{name}} to "Chris"
     * context["name"] = "Chirs"
     * -----
     *
     * Lists section("addSubContext" name is drived from ctemplate's API):
     * -----
     * //{{#repo}}
     * //<b>{{name}}</b>
     * //{{/repo}}
     * //  to
     * //<b>resque</b>
     * //<b>hub</b>
     * //<b>rip</b>
     * foreach (name; ["resque", "hub", "rip"]) {
     *     auto sub = context.addSubContext("repo");
     *     sub["name"] = name;
     * }
     * -----
     *
     * Variable section:
     * -----
     * //{{#person?}}Hi {{name}}{{/person?}} to "Hi Jon"
     * context["person?"] = ["name" : "Jon"];
     * -----
     *
     * Lambdas section:
     * -----
     * //{{#wrapped}}awesome{{/wrapped}} to "<b>awesome</b>"
     * context["Wrapped"] = (string str) { return "<b>" ~ str ~ "</b>"; };
     * -----
     *
     * Inverted section:
     * -----
     * //{{#repo}}<b>{{name}}</b>{{/repo}}
     * //{{^repo}}No repos :({{/repo}}
     * //  to
     * //No repos :(
     * context["foo"] = "bar";  // not set to "repo" 
     * -----
     */
    static final class Context
    {
      private:
        enum SectionType
        {
            nil, use, var, func, list
        }

        struct Section
        {
            SectionType type;

            union
            {
                String[String]          var;
                String delegate(String) func;  // func type is String delegate(String) delegate()?
                Context[]               list;
            }

            @safe nothrow
            {
                this(bool u)
                {
                    type = SectionType.use;
                }

                this(String[String] v)
                {
                    type = SectionType.var;
                    var  = v;
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
            }

            /* nothrow : AA's length is not nothrow */
            @trusted @property
            bool empty() const
            {
                final switch (type) {
                case SectionType.nil:
                    return true;
                case SectionType.use:
                    return false;
                case SectionType.var:
                    return !var.length;  // Why?
                case SectionType.func:
                    return func is null;
                case SectionType.list:
                    return !list.length;
                }
            }
        }

        const Context   parent;
        String[String]  variables;
        Section[String] sections;


      public:
        @safe
        this(in Context context = null) nothrow
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
        @safe
        String opIndex(in String key) const nothrow
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
        @trusted
        void opIndexAssign(T)(T value, in String key)
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
            else static if (isCallable!T)
            {
                import std.functional : toDelegate;

                auto v = toDelegate(value);
                static if (is(typeof(v) D == S delegate(S), S : String))
                    sections[key] = Section(v);
                else static assert(false, "Non-supported delegate type");
            }
            else
            {
                variables[key] = to!String(value);
            }
        }

        /**
         * Enable $(D_PARAM key)'s section.
         *
         * Params:
         *  key = key string to enable
         *
         * NOTE:
         *  I don't like this method, but D's typing can't well-handle Ruby's typing.
         */
        @safe
        void useSection(in String key)
        {
            sections[key] = Section(true);
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
        @trusted
        Context addSubContext(in String key, lazy size_t size = 1)
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
        /*
         * Fetches $(D_PARAM)'s value. This method follows parent context.
         *
         * Params:
         *  key = key string to fetch
         * 
         * Returns:
         *  a $(D_PARAM key) associated value.　null if key does not exist.
         */
        @trusted
        String fetch(in String key, lazy Handler handler = null) const
        {
            auto result = key in variables;
            if (result !is null)
                return *result;

            if (parent is null)
                return handler is null ? null : handler()();

            return parent.fetch(key);
        }

        @safe
        SectionType fetchableSectionType(in String key) const nothrow
        {
            auto result = key in sections;
            if (result !is null)
                return result.type;

            if (parent is null)
                return SectionType.nil;

            return parent.fetchableSectionType(key);
        }

        @trusted
        const(Result) fetchSection(Result, SectionType type, string name)(in String key) const /* nothrow */
        {
            auto result = key in sections;
            if (result !is null && result.type == type)
                return result.empty ? null : mixin("result." ~ to!string(type));

            if (parent is null)
                return null;

            return mixin("parent.fetch" ~ name ~ "(key)");
        }

        alias fetchSection!(String[String],          SectionType.var,  "Var")  fetchVar;
        alias fetchSection!(Context[],               SectionType.list, "List") fetchList;
        alias fetchSection!(String delegate(String), SectionType.func, "Func") fetchFunc;
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
        { // variable
            String[String] aa = ["name" : "Ritsu"];

            context["Value"] = aa;
            assert(context.fetchVar("Value") == cast(const)aa);
        }
        { // func
            auto func = function (String str) { return "<b>" ~ str ~ "</b>"; };

            context["Wrapped"] = func;
            assert(context.fetchFunc("Wrapped")("Ritsu") == func("Ritsu"));
        }
        { // handler
            Handler fixme = delegate String() { return "FIXME"; };
            Handler error = delegate String() { throw new MustacheException("Unknow"); };

            assert(context.fetch("unknown") == "");
            assert(context.fetch("unknown", fixme) == "FIXME");
            try {
                assert(context.fetch("unknown", error) == "");
                assert(false);
            } catch (const MustacheException e) { }
        }
    }


  private:
    // Internal cache
    struct Cache
    {
        Node[]  compiled;
        SysTime modified;
    }

    Option        option_;
    Cache[string] caches_;


  public:
    @safe
    this(Option option) nothrow
    {
        option_ = option;
    }

    @property @safe nothrow
    {
        /**
         * Property for template extenstion
         */
        const(string) ext() const
        {
            return option_.ext;
        }

        /// ditto
        void ext(string ext)
        {
            option_.ext = ext;
        }

        /**
         * Property for template searche path
         */
        const(string) path() const
        {
            return option_.path;
        }

        /// ditto
        void path(string path)
        {
            option_.path = path;
        }

        /**
         * Property for cache level
         */
        const(CacheLevel) level() const
        {
            return option_.level;
        }

        /// ditto
        void level(CacheLevel level)
        {
            option_.level = level;
        }

        /**
         * Property for callback handler
         */
        const(Handler) handler() const
        {
            return option_.handler;
        }

        /// ditto
        void handler(Handler handler)
        {
            option_.handler = handler;
        }
    }

    /**
     * Renders $(D_PARAM name) template with $(D_PARAM context).
     *
     * This method stores compile result in memory if you set check or once CacheLevel.
     *
     * Params:
     *  name    = template name without extenstion
     *  context = Mustache context for rendering
     *
     * Returns:
     *  rendered result.
     *
     * Throws:
     *  object.Exception if String alignment is mismatched from template file.
     */
    String render(in string name, in Context context)
    {
        /*
         * Helper for file reading
         *
         * Throws:
         *  object.Exception if alignment is mismatched.
         */
        @trusted
        static String readFile(string file)
        {
            // cast checks character encoding alignment.
            return cast(String)read(file);
        }

        string file = buildPath(option_.path, name ~ "." ~ option_.ext);
        Node[] nodes;

        final switch (option_.level) {
        case CacheLevel.no:
            nodes = compile(readFile(file));
            break;
        case CacheLevel.check:
            auto t = timeLastModified(file);
            auto p = file in caches_;
            if (!p || t > p.modified)
                caches_[file] = Cache(compile(readFile(file)), t);
            nodes = caches_[file].compiled;
            break;
        case CacheLevel.once:
            if (file !in caches_)
                caches_[file] = Cache(compile(readFile(file)), SysTime.min);
            nodes = caches_[file].compiled;
            break;
        }

        return renderImpl(nodes, context);
    }

    /**
     * string version of $(D render).
     */
    String renderString(in String src, in Context context)
    {
        return renderImpl(compile(src), context);
    }


  private:
    /*
     * Implemention of render function.
     */
    String renderImpl(in Node[] nodes, in Context context)
    {
        // helper for HTML escape(original function from std.xml.encode)
        static String encode(in String text)
        {
            size_t index;
            auto   result = appender!String();

            foreach (i, c; text) {
                String temp;

                switch (c) {
                case '&': temp = "&amp;";  break;
                case '"': temp = "&quot;"; break;
                case '<': temp = "&lt;";   break;
                case '>': temp = "&gt;";   break;
                default: continue;
                }

                result.put(text[index .. i]);
                result.put(temp);
                index = i + 1;
            }

            if (!result.data)
                return text;

            result.put(text[index .. $]);
            return result.data;
        }

        String result;

        foreach (ref node; nodes) {
            final switch (node.type) {
            case NodeType.text:
                result ~= node.text;
                break;
            case NodeType.var:
                auto value = context.fetch(node.key, option_.handler);
                if (value)
                    result ~= node.flag ? value : encode(value);
                break;
            case NodeType.section:
                auto type = context.fetchableSectionType(node.key);
                final switch (type) {
                case Context.SectionType.nil:
                    if (node.flag)
                        result ~= renderImpl(node.childs, context);
                    break;
                case Context.SectionType.use:
                    if (!node.flag)
                        result ~= renderImpl(node.childs, context);
                    break;
                case Context.SectionType.var:
                    auto var = context.fetchVar(node.key);
                    if (!var) {
                        if (node.flag)
                            result ~= renderImpl(node.childs, context);
                    } else {
                        auto sub = new Context(context);
                        foreach (k, v; var)
                            sub[k] = v;
                        result ~= renderImpl(node.childs, sub);
                    }
                    break;
                case Context.SectionType.func:
                    auto func = context.fetchFunc(node.key);
                    if (!func) {
                        if (node.flag)
                            result ~= renderImpl(node.childs, context);
                    } else {
                        result ~= renderImpl(compile(func(node.source)), context);
                    }
                    break;
                case Context.SectionType.list:
                    auto list = context.fetchList(node.key);
                    if (!list) {
                        if (node.flag)
                            result ~= renderImpl(node.childs, context);
                    } else {
                        foreach (sub; list)
                            result ~= renderImpl(node.childs, sub);
                    }
                    break;
                }
                break;
            case NodeType.partial:
                result ~= render(to!string(node.key), context);
                break;
            }
        }

        return result;
    }


    unittest
    {
        MustacheEngine!(String) m;
        auto render = &m.renderString;

        { // var
            auto context = new Context;
            context["name"] = "Ritsu & Mio";

            assert(render("Hello {{name}}",   context) == "Hello Ritsu &amp; Mio");
            assert(render("Hello {{&name}}",  context) == "Hello Ritsu & Mio");
            assert(render("Hello {{{name}}}", context) == "Hello Ritsu & Mio");
        }
        { // var with handler
            auto context = new Context;
            context["name"] = "Ritsu & Mio";

            m.handler = delegate String() { return "FIXME"; };
            assert(render("Hello {{unknown}}", context) == "Hello FIXME");

            m.handler = delegate String() { throw new MustacheException("Unknow"); };
            try {
                assert(render("Hello {{&unknown}}", context) == "Hello Ritsu & Mio");
                assert(false);
            } catch (const MustacheException e) {}
        }
        { // list section
            auto context = new Context;
            foreach (name; ["resque", "hub", "rip"]) {
                auto sub = context.addSubContext("repo");
                sub["name"] = name;
            }

            assert(render("{{#repo}}\n  <b>{{name}}</b>\n{{/repo}}", context) ==
                   "\n  <b>resque</b>\n  <b>hub</b>\n  <b>rip</b>");
        }
        { // var section
            auto context = new Context;
            String[String] aa = ["name" : "Ritsu"];
            context["person?"] = aa;

            assert(render("{{#person?}}\n  Hi {{name}}!\n{{/person?}}", context) ==
                   "\n  Hi Ritsu!");
        }
        { // inverted section
            String temp  = "{{#repo}}\n<b>{{name}}</b>\n{{/repo}}\n{{^repo}}\nNo repos :(\n{{/repo}}\n";
            auto context = new Context;
            assert(render(temp, context) == "\nNo repos :(\n");

            String[String] aa;
            context["person?"] = aa;
            assert(render(temp, context) == "\nNo repos :(\n");
        }
        { // comment
            auto context = new Context;
            assert(render("<h1>Today{{! ignore me }}.</h1>", context) == "<h1>Today.</h1>");
        }
        { // partial
            std.file.write("user.mustache", to!String("<strong>{{name}}</strong>"));
            scope(exit) std.file.remove("user.mustache");

            auto context = new Context;
            foreach (name; ["Ritsu", "Mio"]) {
                auto sub = context.addSubContext("names");
                sub["name"] = name;
            }

            assert(render("<h2>Names</h2>\n{{#names}}\n  {{> user}}\n{{/names}}\n", context) ==
                   "<h2>Names</h2>\n  <strong>Ritsu</strong>\n  <strong>Mio</strong>\n");
        }
    }

    /*
     * Compiles $(D_PARAM src) into Intermediate Representation.
     */
    static Node[] compile(String src)
    {
        // strip previous whitespace
        void fixWS(ref Node node)
        {
            if (node.type == NodeType.text)
                node.text = node.text.chomp();
        }

        String sTag = "{{";
        String eTag = "}}";

        void setDelimiter(String src)
        {
            auto i = src.indexOf(" ");
            if (i == -1)
                throw new MustacheException("Delimiter tag needs whitespace");

            sTag = src[0..i];
            eTag = src[i + 1..$].stripLeft();
        }

        // State capturing for section
        struct Memo
        {
            String key;
            Node[] nodes;
            String source;
        }

        Node[] result;
        Memo[] stack;   // for nested section

        while (true) {
            auto hit = src.indexOf(sTag);
            if (hit == -1) {  // rest template does not have tags
                if (src.length > 0)
                    result ~= Node(src);
                break;
            } else {
                if (hit > 0)
                    result ~= Node(src[0..hit]);
                src = src[hit + sTag.length..$];
            }

            auto end = src.indexOf(eTag);
            if (end == -1)
                throw new MustacheException("Mustache tag is not closed");

            immutable type = src[0];
            switch (type) {
            case '#': case '^':
                if (result.length)
                    fixWS(result[$ - 1]);

                auto key = src[1..end].strip();
                result ~= Node(NodeType.section, key, type == '^');
                stack  ~= Memo(key, result, src[end + eTag.length..$]);
                result  = null;
                break;
            case '/':
                auto key = src[1..end].strip();
                if (stack.empty)
                    throw new MustacheException(to!string(key) ~ " is unopened");
                auto memo = stack.back; stack.popBack();
                if (key != memo.key)
                    throw new MustacheException(to!string(key) ~ " is different from expected " ~ to!string(memo.key));

                fixWS(result[$ - 1]);

                auto temp = result;
                result = memo.nodes;
                result[$ - 1].childs = temp;
                result[$ - 1].source = memo.source[0..src.ptr - memo.source.ptr - eTag.length];
                break;
            case '>':
                // TODO: If option argument exists, this function can read and compile partial file.
                result ~= Node(NodeType.partial, src[1..end].strip());
                break;
            case '=':
                setDelimiter(src[1..end - 1]);
                break;
            case '!':
                break;
            case '{':
                auto pos = end + eTag.length;
                if (pos >= src.length || src[pos] != '}')
                    throw new MustacheException("Unescaped tag is mismatched");
                result ~= Node(NodeType.var, src[1..end++].strip(), true);
                break;
            case '&':
                result ~= Node(NodeType.var, src[1..end].strip(), true);
                break;
            default:
                result ~= Node(NodeType.var, src[0..end].strip());
                break;
            }

            src = src[end + eTag.length..$];
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
            auto nodes = compile("{{#in_ca}}\nWell, ${{taxed_value}}, after taxes.\n{{/in_ca}}\n");
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
            assert(childs[2].text == ", after taxes.");
        }
        {  // inverted section
            auto nodes = compile("{{^repo}}\n  No repos :(\n{{/repo}}\n");
            assert(nodes[0].type == NodeType.section);
            assert(nodes[0].key  == "repo");
            assert(nodes[0].flag == true);

            auto childs = nodes[0].childs;
            assert(childs[0].type == NodeType.text);
            assert(childs[0].text == "\n  No repos :(");
        }
        {  // partial and set delimiter
            auto nodes = compile("{{=<% %>=}}<%> erb_style %>");
            assert(nodes[0].type == NodeType.partial);
            assert(nodes[0].key  == "erb_style");
        }
    }


    /*
     * Mustache's node types
     */
    static enum NodeType
    {
        text,     /// outside tag
        var,      /// {{}} or {{{}}} or {{&}}
        section,  /// {{#}} or {{^}}
        partial   /// {{>}}
    }


    /*
     * Intermediate Representation of Mustache
     */
    static struct Node
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

        @safe nothrow
        {
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

            final switch (type) {
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

unittest
{
    alias MustacheEngine!(string) Mustache;

    std.file.write("unittest.mustache", "Level: {{lvl}}");
    scope(exit) std.file.remove("unittest.mustache");

    Mustache mustache;
    auto context = new Mustache.Context;

    { // no
        mustache.level = Mustache.CacheLevel.no;
        context["lvl"] = "no";
        assert(mustache.render("unittest", context) == "Level: no");
        assert(mustache.caches_.length == 0);
    }
    { // check
        mustache.level = Mustache.CacheLevel.check;
        context["lvl"] = "check";
        assert(mustache.render("unittest", context) == "Level: check");
        assert(mustache.caches_.length > 0);

        core.thread.Thread.sleep(dur!"seconds"(1));
        std.file.write("unittest.mustache", "Modified");
        assert(mustache.render("unittest", context) == "Modified");
    }
    mustache.caches_.remove("./unittest.mustache");  // remove previous cache
    { // once
        mustache.level = Mustache.CacheLevel.once;
        context["lvl"] = "once";
        assert(mustache.render("unittest", context) == "Modified");
        assert(mustache.caches_.length > 0);

        core.thread.Thread.sleep(dur!"seconds"(1));
        std.file.write("unittest.mustache", "Level: {{lvl}}");
        assert(mustache.render("unittest", context) == "Modified");
    }
}
