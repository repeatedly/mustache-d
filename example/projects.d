// This example from https://github.com/defunkt/mustache/blob/master/examples/projects.mustache

import mustache;
import std.stdio;

struct Project
{
    string name;
    string url;
    string description;
}

static Project[] projects = [
    Project("dmd", "https://github.com/dlang/dmd", "dmd D Programming Language compiler"),
    Project("druntime", "https://github.com/dlang/druntime", "Low level runtime library for the D programming language"),
    Project("phobos", "https://github.com/dlang/phobos", "The standard library of the D programming language")
];

void main()
{
    alias MustacheEngine!(string) Mustache;

    Mustache mustache;
    auto context = new Mustache.Context;

    context["width"] = 4968;
    foreach (ref project; projects) {
        auto sub = context.addSubContext("projects");
        sub["name"]        = project.name;
        sub["url"]         = project.url;
        sub["description"] = project.description;
    }

    mustache.path  = "example";
    mustache.level = Mustache.CacheLevel.no;
    stdout.rawWrite(mustache.render("projects", context));
}
