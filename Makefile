# =============================================================================
# Makefile – Secure Communication Gateway SoC
#
# Targets:
#   all             – Build firmware and run full SoC end-to-end simulation
#   sim_firmware    – Run full SoC simulation with compiled RISC-V C firmware
#   sim_soc         – Run SoC top-level hardware testbench (tb_soc_top.sv)
#   sim_interconnect– Run 2x9 AXI Interconnect standalone testbench
#   sim_cpu_adapter – Run CPU AXI adapter standalone testbench
#   sim_aes         – Run AES-128 CTR standalone testbench (FIPS-197 KAT)
#   sim_dma         – Run DMA standalone testbench
#   sim_watchdog    – Run Watchdog standalone testbench
#   sim_vcs_uvm     – Run UVM verification environment with Synopsys VCS
#   verdi           – Launch Synopsys Verdi waveform debugger
#   firmware        – Compile bare-metal RISC-V firmware (ELF, BIN, HEX)
#   lint            – Synthesizability & syntax check across all RTL modules
#   clean           – Remove generated simulation and build artifacts
# =============================================================================

# ---- Directories ------------------------------------------------------------
RTL_DIR    := rtl
SW_DIR     := sw
TB_DIR     := tb
UVM_DIR    := uvm
BUILD_DIR  := build
SCRIPTS_DIR:= scripts
CONFIG_DIR := config

# ---- Include Directories ----------------------------------------------------
INC_DIRS   := -I$(RTL_DIR)/interconnect -I$(TB_DIR) -I$(RTL_DIR)/top

# ---- Common RTL Sources -----------------------------------------------------
AXI_LIB_SRCS := \
    $(RTL_DIR)/third_party/verilog-axi/rtl/arbiter.v          \
    $(RTL_DIR)/third_party/verilog-axi/rtl/priority_encoder.v \
    $(RTL_DIR)/third_party/verilog-axi/rtl/axi_interconnect.v

INTERCONNECT_SRCS := \
    $(AXI_LIB_SRCS) \
    $(RTL_DIR)/interconnect/soc_axi_interconnect_wrap_2x9.v

IP_SRCS := \
    $(RTL_DIR)/memory/instruction_memory.v \
    $(RTL_DIR)/memory/data_memory.v        \
    $(RTL_DIR)/peripherals/uart.v          \
    $(RTL_DIR)/peripherals/spi.v           \
    $(RTL_DIR)/peripherals/gpio.v          \
    $(RTL_DIR)/peripherals/timer.v         \
    $(RTL_DIR)/peripherals/watchdog.v      \
    $(RTL_DIR)/security/aes.v              \
    $(RTL_DIR)/dma/dma.v

CPU_SRCS := \
    $(RTL_DIR)/cpu/cpu_axi_master.v        \
    $(RTL_DIR)/cpu/cpu_axi_adapter.v       \
    $(RTL_DIR)/cpu/veer_el2_wrapper.v

SOC_SRCS := \
    $(INTERCONNECT_SRCS) \
    $(CPU_SRCS)          \
    $(IP_SRCS)           \
    $(RTL_DIR)/top/soc_top.v

# ---- Firmware Compiler ------------------------------------------------------
CC       := riscv64-unknown-elf-gcc
OBJCOPY  := riscv64-unknown-elf-objcopy
OBJDUMP  := riscv64-unknown-elf-objdump
CFLAGS   := -march=rv32i -mabi=ilp32 -Os -Wall -DSIMULATION \
            -I$(SW_DIR)/include \
            -nostartfiles -nolibc
LDSCRIPT := $(SW_DIR)/linker/soc.ld
SRCS_SW  := $(SW_DIR)/startup/startup.S $(SW_DIR)/application/main.c
ELF      := $(BUILD_DIR)/firmware.elf
BIN      := $(BUILD_DIR)/firmware.bin
HEX      := $(BUILD_DIR)/firmware.hex

.PHONY: all sim sim_soc sim_firmware sim_vcs_uvm verdi sim_interconnect sim_cpu_adapter sim_aes sim_dma sim_watchdog firmware basic_firmware sim_basic_c lint clean

all: firmware sim_firmware

# ---- RISC-V Firmware Compilation --------------------------------------------
firmware: $(HEX)
	@echo ">>> Firmware compilation complete: $(HEX)"

# ---- Basic C Test Application Compilation -----------------------------------
BASIC_SRCS_SW := $(SW_DIR)/startup/startup.S $(SW_DIR)/application/basic_test.c
BASIC_ELF     := $(BUILD_DIR)/basic_test.elf
BASIC_BIN     := $(BUILD_DIR)/basic_test.bin
BASIC_HEX     := $(BUILD_DIR)/basic_test.hex

basic_firmware: $(BASIC_HEX)
	@echo ">>> Basic C test firmware compilation complete: $(BASIC_HEX)"

$(BASIC_ELF): $(BASIC_SRCS_SW) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -T$(LDSCRIPT) $(BASIC_SRCS_SW) -o $@
	$(OBJDUMP) -D -S $@ > $(BUILD_DIR)/basic_test.dis

$(BASIC_BIN): $(BASIC_ELF)
	$(OBJCOPY) -O binary $< $@

$(BASIC_HEX): $(BASIC_BIN)
	python3 $(SCRIPTS_DIR)/bin2hex.py $< $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): $(SRCS_SW) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -T$(LDSCRIPT) $(SRCS_SW) -o $@
	$(OBJDUMP) -D -S $@ > $(BUILD_DIR)/firmware.dis

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	python3 $(SCRIPTS_DIR)/bin2hex.py $< $@

# ---- Standalone IP & Interconnect Simulations (Icarus Verilog) --------------
sim_interconnect: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_interconnect \
	    $(INTERCONNECT_SRCS) $(TB_DIR)/interconnect/tb_interconnect.sv
	cd $(BUILD_DIR) && vvp sim_interconnect

sim_cpu_adapter: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_cpu_adapter \
	    $(RTL_DIR)/cpu/cpu_axi_adapter.v $(TB_DIR)/cpu/tb_cpu_adapter.sv
	cd $(BUILD_DIR) && vvp sim_cpu_adapter

sim_aes: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_aes \
	    $(RTL_DIR)/security/aes.v $(TB_DIR)/ip/tb_aes.sv
	cd $(BUILD_DIR) && vvp sim_aes

sim_dma: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_dma \
	    $(RTL_DIR)/dma/dma.v $(TB_DIR)/ip/tb_dma.sv
	cd $(BUILD_DIR) && vvp sim_dma

sim_watchdog: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_watchdog \
	    $(RTL_DIR)/peripherals/watchdog.v $(TB_DIR)/ip/tb_watchdog.sv
	cd $(BUILD_DIR) && vvp sim_watchdog

# ---- SoC Top Hardware Testbench Simulation ----------------------------------
sim_soc: | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -o $(BUILD_DIR)/sim_soc_top \
	    $(SOC_SRCS) $(TB_DIR)/soc/tb_soc_top.sv
	cd $(BUILD_DIR) && vvp sim_soc_top

# ---- Full SoC End-to-End Firmware Simulation --------------------------------
sim_firmware: $(HEX) | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -f filelist.f \
	    $(TB_DIR)/soc/tb_soc_firmware.sv -o $(BUILD_DIR)/sim_soc_firmware
	vvp $(BUILD_DIR)/sim_soc_firmware

# ---- Basic C Test Simulation ------------------------------------------------
sim_basic_c: basic_firmware | $(BUILD_DIR)
	iverilog -g2012 -Wall $(INC_DIRS) -f filelist.f \
	    $(TB_DIR)/soc/tb_basic_c_test.sv -o $(BUILD_DIR)/sim_basic_c
	vvp $(BUILD_DIR)/sim_basic_c

# ---- Synopsys VCS UVM Simulation --------------------------------------------
sim_vcs_uvm:
	./scripts/run_vcs_uvm.sh soc_gateway_pipeline_test

verdi:
	./scripts/run_verdi.sh soc_uvm.fsdb

# ---- RTL Linting & Synthesizability Check -----------------------------------
lint:
	iverilog -g2012 -Wall -f filelist.f -o $(BUILD_DIR)/lint_check
	@echo ">>> All RTL modules passed syntax and lint checks."

# ---- Waveform vs HEX Automated Comparison -----------------------------------
compare:
	python3 $(SCRIPTS_DIR)/compare_waveform_hex.py

# ---- Clean ------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) *.vcd *.fsdb *.log
