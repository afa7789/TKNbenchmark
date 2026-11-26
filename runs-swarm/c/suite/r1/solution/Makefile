# Builds ./app from every .c file under src/. Each subcommand owns a directory
# src/<name>/; new source files placed there are picked up automatically.
#
# OPTFLAGS selects the optimization level (release by default); CFLAGS,
# CPPFLAGS and LDFLAGS may be supplied for extra flags without losing the
# required ones below.

CC       ?= cc
OPTFLAGS ?= -O2 -DNDEBUG
WARNINGS := -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes \
            -Wmissing-prototypes

ALL_CFLAGS   := -std=c17 $(WARNINGS) $(OPTFLAGS) $(CFLAGS)
ALL_CPPFLAGS := -Isrc -MMD -MP $(CPPFLAGS)

BUILD  := build
TARGET := app
SRCS   := $(shell find src -name '*.c' | LC_ALL=C sort)
OBJS   := $(SRCS:%.c=$(BUILD)/%.o)
DEPS   := $(OBJS:.o=.d)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(ALL_CFLAGS) $(LDFLAGS) -o $@ $^

$(BUILD)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c -o $@ $<

clean:
	rm -rf $(BUILD) $(TARGET)

-include $(DEPS)
