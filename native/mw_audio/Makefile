# mightyweenie - audio GDExtension (native/mw_audio).
# Copyright (c) 2026 the mightyweenie authors. BSD-3-Clause
# (see LICENSE).
#
# Builds one library of the extension. Normally run by tools/bin/build-audio,
# which fetches the dependencies, generates the godot-cpp bindings and passes
# (paths relative to this directory, so the .d files hold no absolute paths
# and the build directory works on every machine that shares the folder):
#   GODOT_CPP  godot-cpp source tree            (../../tools/godot-cpp)
#   YMFM       ymfm source tree                 (../../tools/ymfm)
#   GEN        generated bindings (contains gen/) (build/bindings-<key>)
#   PLATFORM   linux | windows (x86_64 only)
#   TARGET     template_debug | template_release
#   CXX, AR    compiler / archiver (windows: zig c++ -target x86_64-windows-gnu, zig ar)
#   OUT        the library to produce
# Flags mirror godot-cpp's SCons defaults for these targets (tools/godot-cpp/
# tools/{linux,windows,common_compiler_flags}.py): C++17, no exceptions,
# hidden symbols, -O2 (debug) / -O3 (release), static C++ runtime, stripped.
# Every output is written to a temporary name and renamed, so an interrupted
# build never leaves a truncated file behind (and nothing is deleted).

PLATFORM ?= linux
TARGET ?= template_debug
CXX ?= g++
AR ?= ar
# (build/<platform>.<target>.x86_64/ from before the relative paths holds .d
# files with one machine's absolute paths: unused, safe to delete.)
BUILD := build/$(PLATFORM)-$(TARGET)-x86_64

DEFINES := -DGDEXTENSION -DTHREADS_ENABLED -DNDEBUG
CXXFLAGS := -std=c++17 -fno-exceptions -fvisibility=hidden -Wwrite-strings
LDFLAGS := -shared -fvisibility=hidden -s
ifeq ($(TARGET),template_debug)
  DEFINES += -DDEBUG_ENABLED
  CXXFLAGS += -O2
else
  CXXFLAGS += -O3
endif
ifeq ($(PLATFORM),windows)
  # zig c++ -target x86_64-windows-gnu: baseline x86-64 CPU, static libc++.
  DEFINES += -DWINDOWS_ENABLED
  LDFLAGS += -Wl,--no-undefined
else
  DEFINES += -DLINUX_ENABLED -DUNIX_ENABLED
  CXXFLAGS += -fPIC -m64 -march=x86-64
  LDFLAGS += -m64 -march=x86-64
  # --exclude-libs: the static C++ runtime's symbols stay private (only the
  # entry point is exported).
  LDFLAGS += -Wl,--no-undefined -Wl,-R,'$$ORIGIN' -static-libgcc -static-libstdc++ -Wl,--exclude-libs,ALL
endif

# Third-party headers as system headers: our warning flags stay on our code.
INCLUDES := -isystem $(GODOT_CPP)/include -isystem $(GEN)/gen/include -isystem $(YMFM)/src -Isrc
WARN_OURS := -Wall -Wextra

GODOT_CPP_SRC := $(wildcard $(GODOT_CPP)/src/*.cpp $(GODOT_CPP)/src/*/*.cpp)
GEN_SRC := $(shell find $(GEN)/gen/src -name '*.cpp' 2>/dev/null)
# ymfm_opn.cpp also holds the other OPN chips, which use the SSG and ADPCM engines.
YMFM_SRC := $(addprefix $(YMFM)/src/,ymfm_opn.cpp ymfm_ssg.cpp ymfm_adpcm.cpp)
OUR_SRC := $(wildcard src/*.cpp)

GODOT_CPP_OBJ := $(patsubst $(GODOT_CPP)/src/%.cpp,$(BUILD)/godot-cpp/%.o,$(GODOT_CPP_SRC)) \
                 $(patsubst $(GEN)/gen/src/%.cpp,$(BUILD)/gen/%.o,$(GEN_SRC))
YMFM_OBJ := $(patsubst $(YMFM)/src/%.cpp,$(BUILD)/ymfm/%.o,$(YMFM_SRC))
OUR_OBJ := $(patsubst src/%.cpp,$(BUILD)/mw/%.o,$(OUR_SRC))
GODOT_CPP_LIB := $(BUILD)/libgodot-cpp.a

COMPILE = @mkdir -p $(dir $@) && echo "  CXX $(notdir $<)" && \
	$(CXX) $(DEFINES) $(INCLUDES) $(CXXFLAGS) $(1) -MMD -MP -MF $(@:.o=.d) -MT $@ -c $< -o $@.tmp && mv -f $@.tmp $@

.PHONY: all
all: $(OUT)

$(BUILD)/godot-cpp/%.o: $(GODOT_CPP)/src/%.cpp
	$(call COMPILE,)
$(BUILD)/gen/%.o: $(GEN)/gen/src/%.cpp
	$(call COMPILE,)
$(BUILD)/ymfm/%.o: $(YMFM)/src/%.cpp
	$(call COMPILE,)
$(BUILD)/mw/%.o: src/%.cpp
	$(call COMPILE,$(WARN_OURS))

$(GODOT_CPP_LIB): $(GODOT_CPP_OBJ)
	@echo "  AR  $(notdir $@)"
	@$(AR) rcs $@.tmp $^ && mv -f $@.tmp $@

$(OUT): $(OUR_OBJ) $(YMFM_OBJ) $(GODOT_CPP_LIB) Makefile
	@mkdir -p $(dir $@)
	@echo "  LD  $(notdir $@)"
	@$(CXX) $(LDFLAGS) -o $(dir $@)tmp-$(notdir $@) $(OUR_OBJ) $(YMFM_OBJ) $(GODOT_CPP_LIB) && \
		mv -f $(dir $@)tmp-$(notdir $@) $@

-include $(GODOT_CPP_OBJ:.o=.d) $(YMFM_OBJ:.o=.d) $(OUR_OBJ:.o=.d)
