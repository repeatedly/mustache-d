[![Build Status](https://travis-ci.org/repeatedly/mustache-d.png)](https://travis-ci.org/repeatedly/mustache-d)

# Mustache for D

Mustache is a push-strategy (a.k.a logic-less) template engine.

# Features

* Variables

* Sections

  * Lists

  * Non-False Values

  * Lambdas(half implementation)

  * Inverted

* Comments

* Partials

# Usage

See example directory and DDoc comments.

## Mustache.Option

* ext(string)

File extenstion of Mustache template. Default is "mustache".

* path(string)

root path to read Mustache template. Default is "."(current directory).

* level(CacheLevel)

Cache level for Mustache's in-memory cache. Default is "check". See DDoc.

* handler(String delegate())

Callback delegate for unknown name. handler is called if Context can't find name. Image code is below.

    if (followable context is nothing)
        return handler is null ? null : handler();

# TODO

Working on CTFE.

# Link

* [{{ mustache }}](http://mustache.github.com/)

* [mustache(5) -- Logic-less templates.](http://mustache.github.com/mustache.5.html)

man page

# Copyright

    Copyright (c) 2011 Masahiro Nakagawa

Distributed under the Boost Software License, Version 1.0.
