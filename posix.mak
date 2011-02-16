DMD     = dmd
LIB     = libmustache.a
DFLAGS  = -O -release -inline -nofloat -w -d -Isrc
UDFLAGS = -w -g -debug -unittest
NAMES   = mustache
FILES   = $(addsuffix .d, $(NAMES))
SRCS    = $(addprefix src/, $(FILES))

# DDoc
DDOCFLAGS = -c -o- std.ddoc -Isrc

target: $(LIB)

$(LIB):
	$(DMD) $(DFLAGS) -lib -of$(LIB) $(SRCS)

doc:
	$(DMD) -Dd. $(DDOCFLAGS) $(SRCS)

clean:
	rm $(addsuffix $(NAMES), .html) $(LIB)
