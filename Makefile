# =============================================================================
# Makefile  —  CfxLua Standalone Interpreter
# =============================================================================
# Targets:
#   make            — clone + build the LuaGLM VM (alias for 'make vm')
#   make vm         — clone citizenfx/lua and cmake-build the interpreter
#   make install    — install 'cfxlua' wrapper to PREFIX/bin (default /usr/local)
#   make test       — run the test suite using the built VM (or system Lua)
#   make stubs      — regenerate runtime/stubs.lua from cfxlua-vscode annotations
#   make clean      — remove build artefacts (keeps cloned sources)
#   make distclean  — remove everything including cloned repos
#
# Variables:
#   PREFIX      Install prefix              (default: /usr/local)
#   JOBS        Parallel build jobs         (default: nproc || 4)
#   VSCODE_PATH Path to cfxlua-vscode repo  (default: ./vendor/cfxlua-vscode)
# =============================================================================

PREFIX     ?= /usr/local
VSCODE_PATH ?= vendor/cfxlua-vscode
JOBS       ?= $(shell nproc 2>/dev/null || echo 4)

REPO_LUA   := https://github.com/citizenfx/lua.git
REPO_VSCODE := https://github.com/overextended/cfxlua-vscode.git
BRANCH_LUA := luaglm-dev/cfx

LUA_SRC    := vendor/citizenfx-lua
LUA_BUILD  := vm/build
VM_BIN     := $(LUA_BUILD)/cfxlua-vm

# ---------------------------------------------------------------------------
.PHONY: all vm install test stubs clean distclean help

all: vm

help:
	@echo "CfxLua Standalone Interpreter — build targets:"
	@echo ""
	@echo "  make          Build the LuaGLM VM binary"
	@echo "  make install  Install cfxlua to $(PREFIX)/bin"
	@echo "  make test     Run the test suite"
	@echo "  make stubs    Regenerate runtime/stubs.lua from cfxlua-vscode"
	@echo "  make clean    Remove build artifacts"
	@echo "  make distclean Remove build artifacts and vendor directory"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  JOBS=$(JOBS)"
	@echo "  VSCODE_PATH=$(VSCODE_PATH)"

# ---------------------------------------------------------------------------
# Clone citizenfx/lua if not already present
# ---------------------------------------------------------------------------
$(LUA_SRC)/.git:
	@echo "[cfxlua] Cloning citizenfx/lua (branch: $(BRANCH_LUA))..."
	@mkdir -p vendor
	git clone --depth=1 --branch "$(BRANCH_LUA)" "$(REPO_LUA)" "$(LUA_SRC)"
	@echo "[cfxlua] Initialising submodules (GLM)..."
	cd "$(LUA_SRC)" && git submodule update --init --recursive

# ---------------------------------------------------------------------------
# Build the LuaGLM VM with all CfxLua power-patches enabled.
#
# CMake flags explained:
#   GRIT_POWER_COMPOUND  — compound assignment operators:  +=  -=  *=  /=  %=
#   GRIT_POWER_SAFENAV   — safe navigation:  t?.field  t?[key]  t?:method()
#   GRIT_POWER_INTABLE   — in-table destructuring:  local a, b in t
#   GRIT_POWER_JOAAT     — backtick Jenkins hashes:  `Hello`  == 0x3E0B8C49
#   GRIT_POWER_DEFER     — defer statement:  defer fn()  (runs on scope exit)
#   GRIT_POWER_SETCONS   — set constructors:  { .a, .b }  from a table
#   LUA_GLM              — enable vec2/3/4, quat, mat primitives as VM tags
#   LUA_GLM_EXT          — additional GLM functions (cross, dot, normalize…)
#
# The output binary is renamed from `lua` to `cfxlua-vm` by the install step.
# ---------------------------------------------------------------------------
$(VM_BIN): $(LUA_SRC)/.git
	@echo "[cfxlua] Configuring LuaGLM with cmake..."
	@mkdir -p "$(LUA_BUILD)"
	cd "$(LUA_BUILD)" && cmake \
	    -G "Unix Makefiles" \
	    -DCMAKE_BUILD_TYPE=Release \
	    -DGRIT_POWER_COMPOUND=ON \
	    -DGRIT_POWER_SAFENAV=ON \
	    -DGRIT_POWER_INTABLE=ON \
	    -DGRIT_POWER_JOAAT=ON \
	    -DGRIT_POWER_DEFER=ON \
	    -DGRIT_POWER_CHRONO=OFF \
	    -DGRIT_POWER_SETCONS=ON \
	    -DLUA_GLM=ON \
	    -DLUA_GLM_EXT=ON \
	    -DCMAKE_INSTALL_PREFIX="$(abspath $(LUA_BUILD))" \
	    "../../$(LUA_SRC)"
	@echo "[cfxlua] Building LuaGLM ($(JOBS) jobs)..."
	$(MAKE) -C "$(LUA_BUILD)" -j$(JOBS)
	@# Rename the output binary to cfxlua-vm
	@if [ -f "$(LUA_BUILD)/lua" ]; then \
	    cp "$(LUA_BUILD)/lua" "$(VM_BIN)"; \
	    chmod +x "$(VM_BIN)"; \
	    echo "[cfxlua] VM binary: $(VM_BIN)"; \
	fi

vm: $(VM_BIN)
	@echo "[cfxlua] LuaGLM VM ready at: $(VM_BIN)"
	@$(VM_BIN) -v

# ---------------------------------------------------------------------------
# Install wrapper to PREFIX/bin
# ---------------------------------------------------------------------------
install: $(VM_BIN)
	@echo "[cfxlua] Installing to $(PREFIX)/bin ..."
	@mkdir -p "$(PREFIX)/bin"
	install -m 755 "$(VM_BIN)" "$(PREFIX)/bin/cfxlua-vm"
	install -m 755 bin/cfxlua "$(PREFIX)/bin/cfxlua"
	@echo "[cfxlua] Installed cfxlua and cfxlua-vm to $(PREFIX)/bin"
	@echo "         You may need to add $(PREFIX)/bin to your PATH."

# ---------------------------------------------------------------------------
# Run test suite
# The wrapper falls back to system Lua if cfxlua-vm hasn't been built yet,
# so tests run without needing a full build first.
# ---------------------------------------------------------------------------
test:
	@echo "[cfxlua] Running test suite..."
	@if [ -x "$(VM_BIN)" ]; then \
	    CFXLUA_VM="$(abspath $(VM_BIN))" bash bin/cfxlua tests/run_tests.lua; \
	else \
	    echo "[cfxlua] cfxlua-vm not built; running with system Lua (no LuaGLM)"; \
	    bash bin/cfxlua tests/run_tests.lua; \
	fi

# Quick test without the build system (useful in CI before VM is compiled)
test-quick:
	@$(shell command -v lua5.4 2>/dev/null || command -v lua) \
	    -e "__cfx_bootstrapPath = '.'" \
	    runtime/bootstrap.lua tests/run_tests.lua

# ---------------------------------------------------------------------------
# Regenerate stubs from cfxlua-vscode annotations
# ---------------------------------------------------------------------------
$(VSCODE_PATH)/.git:
	@echo "[cfxlua] Cloning cfxlua-vscode for stub generation..."
	@mkdir -p vendor
	git clone --depth=1 "$(REPO_VSCODE)" "$(VSCODE_PATH)"

stubs: $(VSCODE_PATH)/.git
	@echo "[cfxlua] Generating stubs from cfxlua-vscode annotations..."
	$(shell command -v lua5.4 2>/dev/null || command -v lua) \
	    tools/gen_stubs.lua "$(VSCODE_PATH)" server \
	    > runtime/stubs_generated.lua
	@echo "[cfxlua] Generated runtime/stubs_generated.lua"
	@echo "         Review and merge into runtime/stubs.lua as needed."

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf "$(LUA_BUILD)"
	@echo "[cfxlua] Removed $(LUA_BUILD)"

distclean: clean
	rm -rf vendor/
	@echo "[cfxlua] Removed vendor/"
