DMD     = dmd
LIB     = mustache.lib
DFLAGS  = -O -release -inline -nofloat -w -d -Isrc
UDFLAGS = -w -g -debug -unittest
SRCS    = src\mustache.d

# DDoc
DOCS = mustache.html
DDOCFLAGS = -Dd. -c -o- std.ddoc -Isrc

target: $(LIB)

$(LIB):
	$(DMD) $(DFLAGS) -lib -of$(LIB) $(SRCS)

doc:
	$(DMD) $(DDOCFLAGS) $(SRCS)

clean:
	rm $(DOCS) $(LIB)
