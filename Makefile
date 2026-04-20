# redis-fractalsql Makefile — local (non-Docker) development build.
#
# For shipping multi-arch artifacts use:
#   ./build.sh        (Docker, static LuaJIT, per-arch .so in ./dist/${arch}/)
#
# This Makefile is for quick local iteration. It:
#   1. Fetches include/redismodule.h from upstream Redis if missing.
#   2. Compiles with -O3 -flto.
#   3. Links LuaJIT dynamically (faster to iterate than static).
#
# Build:   make
# Install: sudo make install
# Load:    redis-cli MODULE LOAD /usr/lib/redis/modules/fractalsql.so
#          (or add `loadmodule ...` to redis.conf)

CC ?= gcc

# Default to Redis's 7.2 branch — our minimum supported server. Override
# to pin a newer server release if you need to test 8.x-specific APIs.
REDISMODULE_H_URL ?= https://raw.githubusercontent.com/redis/redis/7.2/src/redismodule.h

# LuaJIT discovery
LUAJIT_CFLAGS := $(shell pkg-config --cflags luajit 2>/dev/null)
LUAJIT_LIBS   := $(shell pkg-config --libs luajit 2>/dev/null)
ifeq ($(strip $(LUAJIT_CFLAGS)),)
  LUAJIT_CFLAGS := -I/usr/include/luajit-2.1
  LUAJIT_LIBS   := -lluajit-5.1
endif

CFLAGS  = -Wall -Wextra -O3 -flto -fPIC $(LUAJIT_CFLAGS) -Iinclude
LDFLAGS = -shared -flto $(LUAJIT_LIBS) -lm -ldl -lpthread

TARGET = fractalsql.so
SRCS   = src/module.c
OBJS   = $(SRCS:.c=.o)

# Default Redis module dir on Debian / Ubuntu / most distros.
MODULE_DIR ?= /usr/lib/redis/modules

all: $(TARGET)

# Fetch redismodule.h on demand if it's missing.
include/redismodule.h:
	@echo "Fetching redismodule.h from $(REDISMODULE_H_URL)"
	@curl -fsSL "$(REDISMODULE_H_URL)" -o $@

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c include/sfs_core_bc.h include/redismodule.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)
	@# Note: include/redismodule.h is deliberately preserved across
	@# clean — refetch with `make distclean` if you want a fresh pull.

distclean: clean
	rm -f include/redismodule.h

install: $(TARGET)
	install -Dm0755 $(TARGET) $(MODULE_DIR)/fractalsql.so

.PHONY: all clean distclean install
