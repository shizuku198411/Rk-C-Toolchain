# Rk-C toolchain integration interface.
#
# Runtime tools are included in ordinary Rk-C images. Validation executables
# are built and packed only by the parent repository's application tests.
#
#   RKC_TOOLCHAIN_APP_NAMES += rkcc
#   RKC_TOOLCHAIN_TEST_APP_NAMES += toolcheck

RKC_TOOLCHAIN_SRC_DIR := $(RKC_TOOLCHAIN_DIR)/src
RKC_TOOLCHAIN_LIB_DIR := $(RKC_TOOLCHAIN_SRC_DIR)/lib
RKC_TOOLCHAIN_APP_DIR := $(RKC_TOOLCHAIN_SRC_DIR)/apps
RKC_TOOLCHAIN_LIB_SRCS := $(shell find $(RKC_TOOLCHAIN_LIB_DIR) -type f -name '*.nim' | sort)

RKC_TOOLCHAIN_APP_NAMES := rkas rkcc
RKC_TOOLCHAIN_TEST_APP_NAMES := rkxwritecheck
RKC_TOOLCHAIN_BUILD_APP_NAMES := $(RKC_TOOLCHAIN_APP_NAMES) $(RKC_TOOLCHAIN_TEST_APP_NAMES)
OPTIONAL_APP_RKXS += $(foreach app,$(RKC_TOOLCHAIN_APP_NAMES),$(BIN_DIR)/$(app).rkx)
OPTIONAL_APPFS_NAMES += $(RKC_TOOLCHAIN_APP_NAMES)
OPTIONAL_TEST_APP_RKXS += $(foreach app,$(RKC_TOOLCHAIN_TEST_APP_NAMES),$(BIN_DIR)/$(app).rkx)
OPTIONAL_TEST_APPFS_NAMES += $(RKC_TOOLCHAIN_TEST_APP_NAMES)

define RKC_TOOLCHAIN_APP_template
$(BIN_DIR)/$(1).elf: $(RKC_TOOLCHAIN_SRC_DIR)/app_main.nim $(RKC_TOOLCHAIN_SRC_DIR)/panicoverride.nim $$(shell find $(RKC_TOOLCHAIN_APP_DIR)/$(1) -type f -name '*.nim' | sort) $$(RKC_TOOLCHAIN_LIB_SRCS) $$(SHARED_LIB_SRCS) $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(USER_NIMFLAGS) --path:$$(RKC_TOOLCHAIN_SRC_DIR) -d:toolchainApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/toolchain_$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).rkx: $(BIN_DIR)/$(1).elf $$(RKX_TOOL) $(RKC_TOOLCHAIN_APP_DIR)/$(1)/rkx.toml | $(BIN_DIR)
	python3 $$(RKX_TOOL) --elf $$< --out $$@ --metadata $(RKC_TOOLCHAIN_APP_DIR)/$(1)/rkx.toml
endef

$(foreach app,$(RKC_TOOLCHAIN_BUILD_APP_NAMES),$(eval $(call RKC_TOOLCHAIN_APP_template,$(app))))
