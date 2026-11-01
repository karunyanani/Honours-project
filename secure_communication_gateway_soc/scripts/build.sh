#!/usr/bin/env bash
# =============================================================================
# build.sh – Build script for Secure Communication Gateway SoC
#
# Usage:
#   ./scripts/build.sh [TARGET]
#
# Targets:
#   all         – Build firmware and run full SoC simulation (default)
#   gen         – Re-generate address map and interconnect wrapper
#   sim         – Build and run Icarus Verilog SoC simulation
#   sim_firmware– Build and run full SoC simulation with C firmware
#   sim_vcs     – Build VCS simulation
#   firmware    – Build RISC-V firmware (ELF, BIN, HEX)
#   clean       – Remove build artefacts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RTL_DIR="${ROOT}/rtl"
TB_DIR="${ROOT}/tb"
SW_DIR="${ROOT}/sw"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
SCRIPTS_DIR="${ROOT}/scripts"

IVERILOG="${IVERILOG:-iverilog}"
VCS="${VCS:-vcs}"
RISCV_GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
RISCV_OBJCOPY="${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}"

# ---------------------------------------------------------------------------
# Source file lists
# ---------------------------------------------------------------------------
RTL_SRCS=(
    "${RTL_DIR}/third_party/verilog-axi/rtl/arbiter.v"
    "${RTL_DIR}/third_party/verilog-axi/rtl/priority_encoder.v"
    "${RTL_DIR}/third_party/verilog-axi/rtl/axi_interconnect.v"
    "${RTL_DIR}/interconnect/soc_axi_interconnect_wrap_2x9.v"
    "${RTL_DIR}/memory/instruction_memory.v"
    "${RTL_DIR}/memory/data_memory.v"
    "${RTL_DIR}/peripherals/uart.v"
    "${RTL_DIR}/peripherals/spi.v"
    "${RTL_DIR}/peripherals/gpio.v"
    "${RTL_DIR}/peripherals/timer.v"
    "${RTL_DIR}/peripherals/watchdog.v"
    "${RTL_DIR}/security/aes.v"
    "${RTL_DIR}/dma/dma.v"
    "${RTL_DIR}/cpu/cpu_axi_master.v"
    "${RTL_DIR}/cpu/cpu_axi_adapter.v"
    "${RTL_DIR}/cpu/veer_el2_wrapper.v"
    "${RTL_DIR}/top/soc_top.v"
)

TB_SOC_SRCS=( "${TB_DIR}/soc/tb_soc_top.sv" )
INC_FLAGS=( "-I${RTL_DIR}/interconnect" "-I${TB_DIR}" "-I${RTL_DIR}/top" )

SW_SRCS=( "${SW_DIR}/startup/startup.S" "${SW_DIR}/application/main.c" )
SW_INC=( "-I${SW_DIR}/include" )
SW_CFLAGS=( -march=rv32i -mabi=ilp32 -Os -Wall -DSIMULATION
             -nostartfiles -nolibc
             "${SW_INC[@]}" )
LDSCRIPT="${SW_DIR}/linker/soc.ld"

info()  { echo "[BUILD] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || \
        error "Tool '$1' not found. Set ${2:-} environment variable or add it to PATH."
}

target_gen() {
    info "Regenerating address map ..."
    cd "${ROOT}"
    python3 "${SCRIPTS_DIR}/generate_address_map.py" --outdir "${ROOT}"
    python3 "${SCRIPTS_DIR}/gen_interconnect_wrap.py" \
        > "${RTL_DIR}/interconnect/soc_axi_interconnect_wrap_2x9.v"
    info "Address map regeneration done."
}

target_firmware() {
    require_tool "${RISCV_GCC}" "RISCV_GCC"
    require_tool "${RISCV_OBJCOPY}" "RISCV_OBJCOPY"
    info "Building RISC-V bare-metal firmware ..."
    mkdir -p "${BUILD_DIR}"
    "${RISCV_GCC}" "${SW_CFLAGS[@]}" \
        -T "${LDSCRIPT}" \
        "${SW_SRCS[@]}" \
        -o "${BUILD_DIR}/firmware.elf"
    "${RISCV_OBJCOPY}" -O binary \
        "${BUILD_DIR}/firmware.elf" \
        "${BUILD_DIR}/firmware.bin"
    python3 "${SCRIPTS_DIR}/bin2hex.py" \
        "${BUILD_DIR}/firmware.bin" \
        "${BUILD_DIR}/firmware.hex"
    info "Firmware built successfully: ${BUILD_DIR}/firmware.hex"
}

target_sim() {
    require_tool "${IVERILOG}" "IVERILOG"
    info "Compiling hardware SoC testbench with Icarus Verilog ..."
    mkdir -p "${BUILD_DIR}"
    "${IVERILOG}" -g2012 -Wall \
        "${INC_FLAGS[@]}" \
        -o "${BUILD_DIR}/sim_soc_top" \
        "${RTL_SRCS[@]}" \
        "${TB_SOC_SRCS[@]}"
    info "Running simulation ..."
    cd "${BUILD_DIR}" && vvp sim_soc_top
}

target_sim_firmware() {
    require_tool "${IVERILOG}" "IVERILOG"
    target_firmware
    info "Compiling full SoC simulation with firmware ..."
    "${IVERILOG}" -g2012 -Wall \
        "${INC_FLAGS[@]}" -f "${ROOT}/filelist.f" \
        "${TB_DIR}/soc/tb_soc_firmware.sv" \
        -o "${BUILD_DIR}/sim_soc_firmware"
    info "Running full SoC firmware simulation ..."
    vvp "${BUILD_DIR}/sim_soc_firmware"
}

target_sim_vcs() {
    require_tool "${VCS}" "VCS"
    info "Compiling with Synopsys VCS ..."
    mkdir -p "${BUILD_DIR}"
    "${VCS}" -full64 -sverilog -timescale=1ns/1ps +define+RV_BUILD_AXI4 \
        "${INC_FLAGS[@]}" \
        -o "${BUILD_DIR}/simv_soc_top" \
        "${RTL_SRCS[@]}" \
        "${TB_SOC_SRCS[@]}"
    info "Running VCS simulation ..."
    "${BUILD_DIR}/simv_soc_top"
}

target_clean() {
    info "Cleaning build artefacts ..."
    rm -rf "${BUILD_DIR}" "${SW_DIR}/build" *.vcd *.fsdb *.log
    info "Clean complete."
}

case "${1:-all}" in
    all)          target_sim_firmware ;;
    gen)          target_gen ;;
    firmware)     target_firmware ;;
    sim)          target_sim ;;
    sim_firmware) target_sim_firmware ;;
    sim_vcs)      target_sim_vcs ;;
    clean)        target_clean ;;
    *)            error "Unknown target: $1. Available: all, gen, firmware, sim, sim_firmware, sim_vcs, clean" ;;
esac
