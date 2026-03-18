CC = cc
CFLAGS = -Wall -Wextra -O2 $(shell pkg-config --cflags liburiparser)
LDFLAGS = $(shell pkg-config --libs liburiparser)

uriparser_test: uriparser_test.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test: uriparser_test
	./run_uriparser_tests.sh

clean:
	rm -f uriparser_test

.PHONY: clean test
