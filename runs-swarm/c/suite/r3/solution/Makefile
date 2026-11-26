# Build for ./app. Every .c file under src/ is compiled, so adding files to a
# subcommand's directory needs no change here.

CC      ?= cc
CSTD    := -std=c17
WARN    := -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes \
           -Wmissing-prototypes -Wconversion -Wno-sign-conversion
OPT     ?= -O2 -DNDEBUG
CFLAGS  ?=
CFLAGS  += $(CSTD) $(WARN) $(OPT) -Isrc
LDFLAGS ?=

BUILD   := build
TARGET  := app
SRCS    := $(shell find src -name '*.c' | LC_ALL=C sort)
OBJS    := $(SRCS:src/%.c=$(BUILD)/%.o)
DEPS    := $(OBJS:.o=.d)

.PHONY: all debug clean

all: $(TARGET)

debug:
	$(MAKE) OPT='-O0 -g -fsanitize=address,undefined' BUILD=build/debug TARGET=app-debug

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(BUILD)/%.o: src/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

clean:
	rm -rf build $(TARGET) app-debug

-include $(DEPS)
