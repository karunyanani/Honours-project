#!/usr/bin/env bash
# =============================================================================
# run_tests.sh – Automated regression test runner
#
# Runs each individual self-checking testbench and the full SoC testbench.
# Exits with a non-zero code if any test fails.
#
# Usage:
#   ./scripts/run_tests.sh [OPTIONS] [TESTBENCH...]
#
# Options:
#   --vcs         Use VCS instead of Icarus Verilog
#   --waves       Dump waveforms to build/waves/<tb_name>.vcd
#   --keep        Keep build artefacts after run
#   --list        List available testbenches and exit
#   --help        Show this help and exit
#
# Examples:
#   ./scripts/run_tests.sh                     # run all tests with iverilog
#   ./scripts/run_tests.sh --vcs               # run all tests with VCS
#   ./scripts/run_tests.sh tb_aes tb_watchdog  # run specific tests
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RTL_DIR="${ROOT}/rtl"
TB_DIR="${ROOT}/tb"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"

IVERILOG="${IVERILOG:-iverilog}"
VCS="${VCS:-vcs}"

INC_FLAGS=( "-I${RTL_DIR}/interconnect" "-I${TB_DIR}" "-I${RTL_DIR}/top" )

# ---------------------------------------------------------------------------
# Common RTL dependencies for each testbench
# ---------------------------------------------------------------------------
RTL_COMMON=(
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

# ---------------------------------------------------------------------------
# Testbench definitions: name -> (rtl_files...) tb_file
# ---------------------------------------------------------------------------
declare -A TB_RTL
declare -A TB_FILE

# tb_interconnect: needs interconnect wrapper + all slaves
TB_RTL[tb_interconnect]="${RTL_DIR}/third_party/verilog-axi/rtl/arbiter.v \
    ${RTL_DIR}/third_party/verilog-axi/rtl/priority_encoder.v \
    ${RTL_DIR}/third_party/verilog-axi/rtl/axi_interconnect.v \
    ${RTL_DIR}/interconnect/soc_axi_interconnect_wrap_2x9.v \
    ${RTL_DIR}/memory/instruction_memory.v \
    ${RTL_DIR}/memory/data_memory.v \
    ${RTL_DIR}/peripherals/uart.v \
    ${RTL_DIR}/peripherals/spi.v \
    ${RTL_DIR}/peripherals/gpio.v \
    ${RTL_DIR}/peripherals/timer.v \
    ${RTL_DIR}/peripherals/watchdog.v \
    ${RTL_DIR}/security/aes.v \
    ${RTL_DIR}/dma/dma.v"
TB_FILE[tb_interconnect]="${TB_DIR}/interconnect/tb_interconnect.sv"

# tb_cpu_adapter: needs adapter and cpu wrapper only
TB_RTL[tb_cpu_adapter]="${RTL_DIR}/cpu/cpu_axi_adapter.v \
    ${RTL_DIR}/cpu/veer_el2_wrapper.v"
TB_FILE[tb_cpu_adapter]="${TB_DIR}/cpu/tb_cpu_adapter.sv"

# tb_aes: AES engine only
TB_RTL[tb_aes]="${RTL_DIR}/security/aes.v"
TB_FILE[tb_aes]="${TB_DIR}/ip/tb_aes.sv"

# tb_dma: DMA + peripherals it talks to
TB_RTL[tb_dma]="${RTL_DIR}/dma/dma.v \
    ${RTL_DIR}/security/aes.v \
    ${RTL_DIR}/peripherals/uart.v \
    ${RTL_DIR}/peripherals/spi.v"
TB_FILE[tb_dma]="${TB_DIR}/ip/tb_dma.sv"

# tb_watchdog: watchdog + DMA + AES + SPI (scoped reset targets)
TB_RTL[tb_watchdog]="${RTL_DIR}/peripherals/watchdog.v \
    ${RTL_DIR}/dma/dma.v \
    ${RTL_DIR}/security/aes.v \
    ${RTL_DIR}/peripherals/spi.v"
TB_FILE[tb_watchdog]="${TB_DIR}/ip/tb_watchdog.sv"

# tb_soc_top: full system
TB_RTL[tb_soc_top]="${RTL_COMMON[*]}"
TB_FILE[tb_soc_top]="${TB_DIR}/soc/tb_soc_top.sv"

# tb_soc_firmware: full system with firmware
TB_RTL[tb_soc_firmware]="${RTL_COMMON[*]}"
TB_FILE[tb_soc_firmware]="${TB_DIR}/soc/tb_soc_firmware.sv"

ALL_TESTBENCHES=( tb_interconnect tb_cpu_adapter tb_aes tb_dma tb_watchdog tb_soc_top tb_soc_firmware )

USE_VCS=0
DUMP_WAVES=0
KEEP_BUILD=0
SELECTED_TBS=()

for arg in "$@"; do
    case "${arg}" in
        --vcs)   USE_VCS=1 ;;
        --waves) DUMP_WAVES=1 ;;
        --keep)  KEEP_BUILD=1 ;;
        --list)
            echo "Available testbenches:"
            for tb in "${ALL_TESTBENCHES[@]}"; do
                echo "  ${tb}  (${TB_FILE[${tb}]})"
            done
            exit 0
            ;;
        --help|-h)
            sed -n '2,20p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: ${arg}" >&2
            exit 1
            ;;
        *)
            if [[ -v "TB_FILE[${arg}]" ]]; then
                SELECTED_TBS+=( "${arg}" )
            else
                echo "ERROR: Unknown testbench: ${arg}" >&2
                echo "Run with --list to see available testbenches." >&2
                exit 1
            fi
            ;;
    esac
done

if [[ ${#SELECTED_TBS[@]} -eq 0 ]]; then
    SELECTED_TBS=( "${ALL_TESTBENCHES[@]}" )
fi

mkdir -p "${BUILD_DIR}"
WAVES_DIR="${BUILD_DIR}/waves"
[[ ${DUMP_WAVES} -eq 1 ]] && mkdir -p "${WAVES_DIR}"

# Build firmware first if tb_soc_firmware is selected
for tb in "${SELECTED_TBS[@]}"; do
    if [[ "${tb}" == "tb_soc_firmware" ]]; then
        make -C "${ROOT}" firmware >/dev/null 2>&1
        break
    fi
done

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_NAMES=()

echo "============================================================================="
echo " Secure Communication Gateway SoC – Automated Regression Test Suite"
echo " Tool: $(if [[ ${USE_VCS} -eq 1 ]]; then echo "Synopsys VCS"; else echo "Icarus Verilog"; fi)"
echo " Tests: ${SELECTED_TBS[*]}"
echo "============================================================================="

for tb in "${SELECTED_TBS[@]}"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "-----------------------------------------------------------------------------"
    echo " [${TOTAL_TESTS}/${#SELECTED_TBS[@]}] Running: ${tb}"
    echo "-----------------------------------------------------------------------------"

    TB_BUILD_DIR="${BUILD_DIR}/${tb}"
    mkdir -p "${TB_BUILD_DIR}"
    LOG_FILE="${TB_BUILD_DIR}/${tb}.log"

    SIM_EXE="${TB_BUILD_DIR}/sim_${tb}"
    COMPILE_OK=1

    EXTRA_DEFINES=()
    if [[ ${DUMP_WAVES} -eq 1 ]]; then
        EXTRA_DEFINES+=( "+define+DUMP_WAVES" "+define+WAVE_FILE=\"${WAVES_DIR}/${tb}.vcd\"" )
    fi

    if [[ ${USE_VCS} -eq 1 ]]; then
        vcs -full64 -sverilog -timescale=1ns/1ps \
            +define+RV_BUILD_AXI4 \
            "${EXTRA_DEFINES[@]}" \
            "${INC_FLAGS[@]}" \
            -o "${SIM_EXE}_vcs" \
            ${TB_RTL[${tb}]} \
            "${TB_FILE[${tb}]}" \
            > "${TB_BUILD_DIR}/compile.log" 2>&1 || COMPILE_OK=0
    else
        iverilog -g2012 -Wall \
            "${EXTRA_DEFINES[@]}" \
            "${INC_FLAGS[@]}" \
            -o "${SIM_EXE}" \
            ${TB_RTL[${tb}]} \
            "${TB_FILE[${tb}]}" \
            > "${TB_BUILD_DIR}/compile.log" 2>&1 || COMPILE_OK=0
    fi

    if [[ ${COMPILE_OK} -ne 1 ]]; then
        echo "  [FAIL] Compilation error in ${tb}"
        cat "${TB_BUILD_DIR}/compile.log" | tail -n 20
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_NAMES+=( "${tb} (compile)" )
        continue
    fi

    RUN_OK=1
    if [[ ${USE_VCS} -eq 1 ]]; then
        "${SIM_EXE}_vcs" > "${LOG_FILE}" 2>&1 || RUN_OK=0
    else
        vvp "${SIM_EXE}" > "${LOG_FILE}" 2>&1 || RUN_OK=0
    fi

    tail -n 15 "${LOG_FILE}"

    if grep -qE "ALL TESTS PASSED|ALL SOC INTEGRATION AND FIRMWARE PIPELINE TESTS PASSED" "${LOG_FILE}" && [[ ${RUN_OK} -eq 1 ]]; then
        echo "  [PASS] ${tb}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  [FAIL] ${tb} did not report ALL TESTS PASSED (exit=${RUN_OK})"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_NAMES+=( "${tb}" )
    fi
done

echo ""
echo "============================================================================="
echo " Regression Summary"
echo " Total : ${TOTAL_TESTS}"
echo " Passed: ${PASSED_TESTS}"
echo " Failed: ${FAILED_TESTS}"
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    echo " Failed tests: ${FAILED_NAMES[*]}"
    echo "============================================================================="
    exit 1
else
    echo " ALL REGRESSION TESTS PASSED (100% SUCCESS)"
    echo "============================================================================="
    exit 0
fi
