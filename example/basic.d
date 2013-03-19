import mustache;
import std.stdio;

alias MustacheEngine!(string) Mustache;

void main()
{
    Mustache mustache;
    auto context = new Mustache.Context;

    context["name"]  = "Chris";
    context["value"] = 10000;
    context["taxed_value"] = 10000 - (10000 * 0.4);
    context.useSection("in_ca");

    stdout.rawWrite(mustache.render("example/basic", context));
}
