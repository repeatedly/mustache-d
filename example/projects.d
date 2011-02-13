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
    Project("dmd", "https://github.com/D-Programming-Language/dmd", "dmd D Programming Language compiler"),
    Project("druntime", "https://github.com/D-Programming-Language/druntime", "Low level runtime library for the D programming language"),
    Project("phobos", "https://github.com/D-Programming-Language/phobos", "Runtime library for the D programming language")
];

void main()
{
    alias MustacheImpl!(string) Mustache;

    auto mustache = new Mustache.Template;
    auto context  = mustache.context;

    context["width"] = 4968;
    foreach (ref project; projects) {
        auto sub = context.addSubContext("projects");
        sub["name"]        = project.name;
        sub["url"]         = project.url;
        sub["description"] = project.description;
    }

    mustache.path = "example";
    writeln(mustache.render("projects"));
}
