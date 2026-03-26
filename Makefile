CC = cc
CFLAGS = -Wall -Wextra -O2 $(shell pkg-config --cflags liburiparser)
LDFLAGS = $(shell pkg-config --libs liburiparser)

all: uriparser_test go_uri_validator

uriparser_test: uriparser_test.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

go_uri_validator: go_uri_validator.go go.mod
	CGO_ENABLED=0 go build -o $@ $<

test: uriparser_test go_uri_validator
	./run_uriparser_tests.sh

clean:
	rm -f uriparser_test go_uri_validator

.PHONY: clean test all
