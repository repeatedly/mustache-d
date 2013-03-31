import mustache;
import std.stdio;

alias MustacheEngine!(string) Mustache;

void main()
{
    Mustache mustache;
    auto context = new Mustache.Context;
    context.useSection("boolean");

    // from https://github.com/mustache/spec/blob/master/specs/sections.yml
    assert(mustache.renderString(" | {{#boolean}}\t|\t{{/boolean}} | \n", context) == " | \t|\t | \n");
    assert(mustache.renderString(" | {{#boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n", context) == " |  \n  | \n");
    assert(mustache.renderString(" {{#boolean}}YES{{/boolean}}\n {{#boolean}}GOOD{{/boolean}}\n", context) == " YES\n GOOD\n");
    assert(mustache.renderString("#{{#boolean}}\n/\n  {{/boolean}}", context) == "#\n/\n");
    assert(mustache.renderString("  {{#boolean}}\n#{{/boolean}}\n/", context) == "#\n/");

    auto expected = `This Is

A Line`;
    auto t = `This Is
  {{#boolean}}

  {{/boolean}}
A Line`;
    assert(mustache.renderString(t, context) == expected);

    auto t2 = `This Is
  {{#boolean}}

  {{/boolean}}
A Line`;
    assert(mustache.renderString(t, context) == expected);

    // TODO: \r\n support

    issue2();
    issue9();
}

void issue2()
{
    Mustache mustache;
    auto context = new Mustache.Context;
    context["module_name"] = "mustache";
    context.useSection("static_imports");

    auto text = `module {{module_name}};

{{#static_imports}}
/*
 * Auto-generated static imports
 */
{{/static_imports}}`;

    assert(mustache.renderString(text, context) == `module mustache;

/*
 * Auto-generated static imports
 */
`);
}

void issue9()
{
    Mustache mustache;
    auto context = new Mustache.Context;
    context.useSection("section");

    auto text = `FOO

{{#section}}BAR{{/section}}`;

    assert(mustache.renderString(text, context) == `FOO

BAR`);
}
