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

import std.algorithm : all;
import std.array;    // empty, back, popBack, appender
import std.conv;     // to
import std.datetime; // SysTime (I think std.file should import std.datetime as public)
import std.file;     // read, timeLastModified
import std.path;     // buildPath
import std.range;    // isOutputRange
import std.string;   // strip, chomp, stripLeft
import std.traits;   // isSomeString, isAssociativeArray

static import std.ascii; // isWhite;

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
    alias String delegate(String) Handler;


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
            
            /* Convenience function */
            @safe @property
            static Section nil() nothrow
            {
                Section result;
                result.type = SectionType.nil;
                return result;
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
        String fetch(in String[] key, lazy Handler handler = null) const
        {
            assert(key.length > 0);
            
            if (key.length == 1) {
                auto result = key[0] in variables;

                if (result !is null)
                    return *result;

                if (parent !is null)
                    return parent.fetch(key, handler);
            } else {
                auto contexts = fetchList(key[0..$-1]);
                foreach (c; contexts) {
                    auto result = key[$-1] in c.variables;

                    if (result !is null)
                        return *result;
                }
            }
            
            return handler is null ? null : handler()(keyToString(key));
        }

        @trusted
        const(Section) fetchSection()(in String[] key) const /* nothrow */
        {
            assert(key.length > 0);
            
            // Ascend context tree to find the key's beginning
            auto currentSection = key[0] in sections;
            if (currentSection is null) {
                if (parent is null)
                    return Section.nil;

                return parent.fetchSection(key);
            }
            
            // Decend context tree to match the rest of the key
            size_t keyIndex = 0;
            while (currentSection) {
                // Matched the entire key?
                if (keyIndex == key.length-1)
                    return currentSection.empty ? Section.nil : *currentSection;
                
                if (currentSection.type != SectionType.list)
                    return Section.nil; // Can't decend any further
                
                // Find next part of key
                keyIndex++;
                foreach (c; currentSection.list)
                {
                    currentSection = key[keyIndex] in c.sections;
                    if (currentSection)
                        break;
                }
            }

            return Section.nil;
        }

        @trusted
        const(Result) fetchSection(Result, SectionType type, string name)(in String[] key) const /* nothrow */
        {
            auto result = fetchSection(key);
            if (result.type == type)
                return result.empty ? null : mixin("result." ~ to!string(type));
            
            return null;
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

            foreach (i, sub; context.fetchList(["sub"])) {
                assert(sub.fetch(["name"]) == "Red Bull");
                assert(sub["num"] == to!String(i + 100));

                foreach (j, subsub; sub.fetchList(["subsub"])) {
                    assert(subsub.fetch(["price"]) == to!String(275));
                    assert(subsub["To be or not to be"] == to!String(j == 0));
                }
            }
        }
        { // variable
            String[String] aa = ["name" : "Ritsu"];

            context["Value"] = aa;
            assert(context.fetchVar(["Value"]) == cast(const)aa);
        }
        { // func
            auto func = function (String str) { return "<b>" ~ str ~ "</b>"; };

            context["Wrapped"] = func;
            assert(context.fetchFunc(["Wrapped"])("Ritsu") == func("Ritsu"));
        }
        { // handler
            Handler fixme = delegate String(String s) { assert(s=="unknown"); return "FIXME"; };
            Handler error = delegate String(String s) { assert(s=="unknown"); throw new MustacheException("Unknow"); };

            assert(context.fetch(["unknown"]) == "");
            assert(context.fetch(["unknown"], fixme) == "FIXME");
            try {
                assert(context.fetch(["unknown"], error) == "");
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
     * Clears the intenal cache.
     * Useful for forcing reloads when using CacheLevel.once.
     */
    @safe
    void clearCache()
    {
        caches_ = null;
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
    String render()(in string name, in Context context)
    {
        auto sink = appender!String();
        render(name, context, sink);
        return sink.data;
    }
    
    /**
    * OutputRange version of $(D render).
    */
    void render(Sink)(in string name, in Context context, ref Sink sink)
        if(isOutputRange!(Sink, String))
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

        renderImpl(nodes, context, sink);
    }

    /**
     * string version of $(D render).
     */
    String renderString()(in String src, in Context context)
    {
        auto sink = appender!String();
        renderString(src, context, sink);
        return sink.data;
    }

    /**
     * string/OutputRange version of $(D render).
     */
    void renderString(Sink)(in String src, in Context context, ref Sink sink)
        if(isOutputRange!(Sink, String))
    {
        renderImpl(compile(src), context, sink);
    }


  private:
    /*
     * Implemention of render function.
     */
    void renderImpl(Sink)(in Node[] nodes, in Context context, ref Sink sink)
        if(isOutputRange!(Sink, String))
    {
        // helper for HTML escape(original function from std.xml.encode)
        static void encode(in String text, ref Sink sink)
        {
            size_t index;
            
            foreach (i, c; text) {
                String temp;

                switch (c) {
                case '&': temp = "&amp;";  break;
                case '"': temp = "&quot;"; break;
                case '<': temp = "&lt;";   break;
                case '>': temp = "&gt;";   break;
                default: continue;
                }

                sink.put(text[index .. i]);
                sink.put(temp);
                index = i + 1;
            }

            sink.put(text[index .. $]);
        }

        foreach (ref node; nodes) {
            final switch (node.type) {
            case NodeType.text:
                sink.put(node.text);
                break;
            case NodeType.var:
                auto value = context.fetch(node.key, option_.handler);
                if (value)
                {
                    if(node.flag)
                        sink.put(value);
                    else
                        encode(value, sink);
                }
                break;
            case NodeType.section:
                auto section = context.fetchSection(node.key);
                final switch (section.type) {
                case Context.SectionType.nil:
                    if (node.flag)
                        renderImpl(node.childs, context, sink);
                    break;
                case Context.SectionType.use:
                    if (!node.flag)
                        renderImpl(node.childs, context, sink);
                    break;
                case Context.SectionType.var:
                    auto var = section.var;
                    auto sub = new Context(context);
                    foreach (k, v; var)
                        sub[k] = v;
                    renderImpl(node.childs, sub, sink);
                    break;
                case Context.SectionType.func:
                    auto func = section.func;
                    renderImpl(compile(func(node.source)), context, sink);
                    break;
                case Context.SectionType.list:
                    auto list = section.list;
                    if (!node.flag) {
                        foreach (sub; list)
                            renderImpl(node.childs, sub, sink);
                    }
                    break;
                }
                break;
            case NodeType.partial:
                render(to!string(node.key.front), context, sink);
                break;
            }
        }
    }


    unittest
    {
        MustacheEngine!(String) m;
        auto render = (String str, Context c) => m.renderString(str, c);

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

            m.handler = delegate String(String s) { assert(s=="unknown"); return "FIXME"; };
            assert(render("Hello {{unknown}}", context) == "Hello FIXME");

            m.handler = delegate String(String s) { assert(s=="unknown"); throw new MustacheException("Unknow"); };
            try {
                assert(render("Hello {{&unknown}}", context) == "Hello Ritsu & Mio");
                assert(false);
            } catch (const MustacheException e) {}

            m.handler = null;
        }
        { // list section
            auto context = new Context;
            foreach (name; ["resque", "hub", "rip"]) {
                auto sub = context.addSubContext("repo");
                sub["name"] = name;
            }

            assert(render("{{#repo}}\n  <b>{{name}}</b>\n{{/repo}}", context) ==
                   "  <b>resque</b>\n  <b>hub</b>\n  <b>rip</b>\n");
        }
        { // var section
            auto context = new Context;
            String[String] aa = ["name" : "Ritsu"];
            context["person?"] = aa;

            assert(render("{{#person?}}  Hi {{name}}!\n{{/person?}}", context) ==
                   "  Hi Ritsu!\n");
        }
        { // inverted section
            {
                String temp  = "{{#repo}}\n<b>{{name}}</b>\n{{/repo}}\n{{^repo}}\nNo repos :(\n{{/repo}}\n";
                auto context = new Context;
                assert(render(temp, context) == "\nNo repos :(\n");

                String[String] aa;
                context["person?"] = aa;
                assert(render(temp, context) == "\nNo repos :(\n");
            }
            {
                auto temp = "{{^section}}This shouldn't be seen.{{/section}}";
                auto context = new Context;
                context.addSubContext("section")["foo"] = "bar";
                assert(render(temp, context).empty);
            }
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
        { // dotted names
            auto context = new Context;
            context
                .addSubContext("a")
                .addSubContext("b")
                .addSubContext("c")
                .addSubContext("person")["name"] = "Ritsu";
            context
                .addSubContext("b")
                .addSubContext("c")
                .addSubContext("person")["name"] = "Wrong";

            assert(render("Hello {{a.b.c.person.name}}",                  context) == "Hello Ritsu");
            assert(render("Hello {{#a}}{{b.c.person.name}}{{/a}}",        context) == "Hello Ritsu");
            assert(render("Hello {{# a . b }}{{c.person.name}}{{/a.b}}",  context) == "Hello Ritsu");
        }
        { // dotted names - context precedence
            auto context = new Context;
            context.addSubContext("a").addSubContext("b")["X"] = "Y";
            context.addSubContext("b")["c"] = "ERROR";

            assert(render("-{{#a}}{{b.c}}{{/a}}-", context) == "--");
        }
        { // dotted names - broken chains
            auto context = new Context;
            context.addSubContext("a")["X"] = "Y";
            assert(render("-{{a.b.c}}-", context) == "--");
        }
        { // dotted names - broken chain resolution
            auto context = new Context;
            context.addSubContext("a").addSubContext("b")["X"] = "Y";
            context.addSubContext("c")["name"] = "ERROR";

            assert(render("-{{a.b.c.name}}-", context) == "--");
        }
    }

    /*
     * Compiles $(D_PARAM src) into Intermediate Representation.
     */
    static Node[] compile(String src)
    {
        bool beforeNewline = true;

        // strip previous whitespace
        bool fixWS(ref Node node)
        {
            // TODO: refactor and optimize with enum
            if (node.type == NodeType.text) {
                if (beforeNewline) {
                    if (all!(std.ascii.isWhite)(node.text)) {
                        node.text = "";
                        return true;
                    }
                }

                auto i = node.text.lastIndexOf('\n');
                if (i != -1) {
                    if (all!(std.ascii.isWhite)(node.text[i + 1..$])) {
                        node.text = node.text[0..i + 1];
                        return true;
                    }
                }
            }

            return false;
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
        
        size_t getEnd(String src)
        {
            auto end = src.indexOf(eTag);
            if (end == -1)
                throw new MustacheException("Mustache tag is not closed");
            
            return end;
        }
        
        // State capturing for section
        struct Memo
        {
            String[] key;
            Node[]   nodes;
            String   source;
            
            bool opEquals()(auto ref const Memo m) inout
            {
                // Don't compare source because the internal
                // whitespace might be different
                return key == m.key && nodes == m.nodes;
            }
        }

        Node[] result;
        Memo[] stack;   // for nested section
        bool singleLineSection;

        while (true) {
            if (singleLineSection) {
                src = chompPrefix(src, "\n");
                singleLineSection = false;
            }

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

            size_t end;

            immutable type = src[0];
            switch (type) {
            case '#': case '^':
                src = src[1..$];
                auto key = parseKey(src, eTag, end);

                if (result.length == 0) {  // for start of template
                    singleLineSection = true;
                } else if (result.length > 0) {
                    if (src[end + eTag.length] == '\n') {
                        singleLineSection = fixWS(result[$ - 1]);
                        beforeNewline = false;
                    }
                }

                result ~= Node(NodeType.section, key, type == '^');
                stack  ~= Memo(key, result, src[end + eTag.length..$]);
                result  = null;
                break;
            case '/':
                src = src[1..$];
                auto key = parseKey(src, eTag, end);
                if (stack.empty)
                    throw new MustacheException(to!string(key) ~ " is unopened");
                auto memo = stack.back; stack.popBack(); stack.assumeSafeAppend();
                if (key != memo.key)
                    throw new MustacheException(to!string(key) ~ " is different from expected " ~ to!string(memo.key));

                if (src.length == (end + eTag.length)) // for end of template
                    fixWS(result[$ - 1]);
                if ((src.length > (end + eTag.length)) && (src[end + eTag.length] == '\n')) {
                    singleLineSection = fixWS(result[$ - 1]);
                    beforeNewline = false;
                }

                auto temp = result;
                result = memo.nodes;
                result[$ - 1].childs = temp;
                result[$ - 1].source = memo.source[0..src.ptr - memo.source.ptr - 1 - eTag.length];
                break;
            case '>':
                // TODO: If option argument exists, this function can read and compile partial file.
                end = getEnd(src);
                result ~= Node(NodeType.partial, [src[1..end].strip()]);
                break;
            case '=':
                end = getEnd(src);
                setDelimiter(src[1..end - 1]);
                break;
            case '!':
                end = getEnd(src);
                break;
            case '{':
                src = src[1..$];
                auto key = parseKey(src, "}", end);
                
                end += 1;
                if (end >= src.length || !src[end..$].startsWith(eTag))
                    throw new MustacheException("Unescaped tag is not closed");
                
                result ~= Node(NodeType.var, key, true);
                break;
            case '&':
                src = src[1..$];
                auto key = parseKey(src, eTag, end);
                result ~= Node(NodeType.var, key, true);
                break;
            default:
                auto key = parseKey(src, eTag, end);
                result ~= Node(NodeType.var, key);
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
            assert(nodes[1].key  == ["name"]);
            assert(nodes[1].flag == true);
        }
        {  // section and escape
            auto nodes = compile("{{#in_ca}}\nWell, ${{taxed_value}}, after taxes.\n{{/in_ca}}\n");
            assert(nodes[0].type   == NodeType.section);
            assert(nodes[0].key    == ["in_ca"]);
            assert(nodes[0].flag   == false);
            assert(nodes[0].source == "\nWell, ${{taxed_value}}, after taxes.\n");

            auto childs = nodes[0].childs;
            assert(childs[0].type == NodeType.text);
            assert(childs[0].text == "Well, $");
            assert(childs[1].type == NodeType.var);
            assert(childs[1].key  == ["taxed_value"]);
            assert(childs[1].flag == false);
            assert(childs[2].type == NodeType.text);
            assert(childs[2].text == ", after taxes.\n");
        }
        {  // inverted section
            auto nodes = compile("{{^repo}}\n  No repos :(\n{{/repo}}\n");
            assert(nodes[0].type == NodeType.section);
            assert(nodes[0].key  == ["repo"]);
            assert(nodes[0].flag == true);

            auto childs = nodes[0].childs;
            assert(childs[0].type == NodeType.text);
            assert(childs[0].text == "  No repos :(\n");
        }
        {  // partial and set delimiter
            auto nodes = compile("{{=<% %>=}}<%> erb_style %>");
            assert(nodes[0].type == NodeType.partial);
            assert(nodes[0].key  == ["erb_style"]);
        }
    }

    private static String[] parseKey(String src, String eTag, out size_t end)
    {
        String[] key;
        size_t index = 0;
        size_t keySegmentStart = 0;
        // Index from before eating whitespace, so stripRight
        // doesn't need to be called on each segment of the key.
        size_t beforeEatWSIndex = 0;

        void advance(size_t length)
        {
            if (index + length >= src.length)
                throw new MustacheException("Mustache tag is not closed");

            index += length;
            beforeEatWSIndex = index;
        }

        void eatWhitespace()
        {
            beforeEatWSIndex = index;
            index = src.length - src[index..$].stripLeft().length;
        }
        
        void acceptKeySegment()
        {
            if (keySegmentStart >= beforeEatWSIndex)
                throw new MustacheException("Missing tag name");

            key ~= src[keySegmentStart .. beforeEatWSIndex];
        }
        
        eatWhitespace();
        keySegmentStart = index;

        enum String dot = ".";
        while (true) {
            if (src[index..$].startsWith(eTag)) {
                acceptKeySegment();
                break;
            } else if (src[index..$].startsWith(dot)) {
                acceptKeySegment();
                advance(dot.length);
                eatWhitespace();
                keySegmentStart = index;
            } else {
                advance(1);
                eatWhitespace();
            }
        }
        
        end = index;
        return key;
    }

    unittest
    {
        {  // single char, single segment, no whitespace
            size_t end;
            String src = "a}}";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 1);
            assert(key[0] == "a");
            assert(src[end..$] == "}}");
        }
        {  // multiple chars, single segment, no whitespace
            size_t end;
            String src = "Mio}}";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 1);
            assert(key[0] == "Mio");
            assert(src[end..$] == "}}");
        }
        {  // single char, multiple segments, no whitespace
            size_t end;
            String src = "a.b.c}}";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 3);
            assert(key[0] == "a");
            assert(key[1] == "b");
            assert(key[2] == "c");
            assert(src[end..$] == "}}");
        }
        {  // multiple chars, multiple segments, no whitespace
            size_t end;
            String src = "Mio.Ritsu.Yui}}";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 3);
            assert(key[0] == "Mio");
            assert(key[1] == "Ritsu");
            assert(key[2] == "Yui");
            assert(src[end..$] == "}}");
        }
        {  // whitespace
            size_t end;
            String src = "  Mio  .  Ritsu  }}";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 2);
            assert(key[0] == "Mio");
            assert(key[1] == "Ritsu");
            assert(src[end..$] == "}}");
        }
        {  // single char custom end delimiter
            size_t end;
            String src = "Ritsu-";
            auto key = parseKey(src, "-", end);
            assert(key.length == 1);
            assert(key[0] == "Ritsu");
            assert(src[end..$] == "-");
        }
        {  // extra chars at end
            size_t end;
            String src = "Ritsu}}abc";
            auto key = parseKey(src, "}}", end);
            assert(key.length == 1);
            assert(key[0] == "Ritsu");
            assert(src[end..$] == "}}abc");
        }
        {  // error: no end delimiter
            size_t end;
            String src = "a.b.c";
            try {
                auto key = parseKey(src, "}}", end);
                assert(false);
            } catch (const MustacheException e) { }
        }
        {  // error: missing tag name
            size_t end;
            String src = "  }}";
            try {
                auto key = parseKey(src, "}}", end);
                assert(false);
            } catch (const MustacheException e) { }
        }
        {  // error: missing ending tag name
            size_t end;
            String src = "Mio.}}";
            try {
                auto key = parseKey(src, "}}", end);
                assert(false);
            } catch (const MustacheException e) { }
        }
        {  // error: missing middle tag name
            size_t end;
            String src = "Mio. .Ritsu}}";
            try {
                auto key = parseKey(src, "}}", end);
                assert(false);
            } catch (const MustacheException e) { }
        }
    }
    
    @trusted
    static String keyToString(in String[] key)
    {
        if (key.length == 0)
            return null;
        
        if (key.length == 1)
            return key[0];
        
        Appender!String buf;
        foreach (index, segment; key) {
            if (index != 0)
                buf.put('.');
            
            buf.put(segment);
        }
        
        return buf.data;
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
                String[] key;
                bool     flag;    // true is inverted or unescape
                Node[]   childs;  // for list section
                String   source;  // for lambda section
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
            this(NodeType t, String[] k, bool f = false)
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
                result = "[" ~ (flag ? "E" : "V") ~ " : \"" ~ keyToString(key) ~ "\"]";
                break;
            case NodeType.section:
                result = "[" ~ (flag ? "I" : "S") ~ " : \"" ~ keyToString(key) ~ "\", [ ";
                foreach (ref node; childs)
                    result ~= node.toString() ~ " ";
                result ~= "], \"" ~ to!string(source) ~ "\"]";
                break;
            case NodeType.partial:
                result = "[P : \"" ~ keyToString(key) ~ "\"]";
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
        nodes ~= Node(NodeType.var, ["name"]);
        nodes ~= Node(NodeType.partial, ["redbull"]);
        {
            childs ~= Node("Ritsu is ");
            childs ~= Node(NodeType.var, ["attr"], true);
            section = Node(NodeType.section, ["ritsu"], false);
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
