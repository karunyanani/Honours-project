#!/bin/bash
# =============================================================================
# Script: run_all_uvm_tests.sh
# Description: Automated UVM Regression Runner for Secure Communication Gateway SoC
# Compatible with Synopsys VCS, QuestaSim, Cadence Xcelium
# Usage:
#   ./scripts/run_all_uvm_tests.sh --all
#   ./scripts/run_all_uvm_tests.sh <test_name>
#   ./scripts/run_all_uvm_tests.sh --block <aes|dma|watchdog|interconnect>
# =============================================================================

set -e

BUILD_DIR=build
mkdir -p ${BUILD_DIR}

UVM_TESTS=(
    "soc_gateway_pipeline_test"
    "soc_reg_access_test"
    "soc_access_control_test"
    "soc_wdt_recovery_test"
    "soc_aes_test"
    "soc_dma_test"
    "soc_mem_test"
    "soc_stress_test"
    "soc_spi_test"
    "soc_uart_test"
)

echo "============================================================================="
echo " Secure Communication Gateway SoC – UVM Verification Suite"
echo "============================================================================="

# -----------------------------------------------------------------------------
# Handle Block-Level UVM Testbenches
# -----------------------------------------------------------------------------
if [ "$1" == "--block" ]; then
    BLOCK=${2:-aes}
    echo ">>> Running Block-Level UVM Testbench: tb_${BLOCK}_uvm <<<"
    FILELIST="uvm/uvm_${BLOCK}_filelist.f"
    if [ ! -f "$FILELIST" ]; then
        echo "Error: Filelist $FILELIST not found!"
        exit 1
    fi

    vcs -full64 -sverilog \
        -ntb_opts uvm-1.2 \
        -timescale=1ns/1ps \
        +define+DUMP_FSDB \
        -kdb -lca \
        -f ${FILELIST} \
        -o ${BUILD_DIR}/simv_uvm_${BLOCK} \
        -l ${BUILD_DIR}/vcs_compile_${BLOCK}.log

    ./${BUILD_DIR}/simv_uvm_${BLOCK} \
        +UVM_TESTNAME=soc_${BLOCK}_test \
        +UVM_VERBOSITY=UVM_MEDIUM \
        -l ${BUILD_DIR}/sim_uvm_${BLOCK}.log

    echo ">>> Block Testbench tb_${BLOCK}_uvm Complete! Log: ${BUILD_DIR}/sim_uvm_${BLOCK}.log <<<"
    exit 0
fi

# -----------------------------------------------------------------------------
# Compile Top-Level SoC UVM Simulation Binary (once for all top tests)
# -----------------------------------------------------------------------------
echo ">>> Compiling Top-Level SoC UVM Verification Model <<<"
vcs -full64 -sverilog \
    -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    +define+DUMP_FSDB \
    -kdb -lca \
    -f uvm/uvm_filelist.f \
    -o ${BUILD_DIR}/simv_uvm \
    -l ${BUILD_DIR}/vcs_compile.log

echo ">>> Compilation Successful! <<<"

# -----------------------------------------------------------------------------
# Execute Single Test or Full Regression
# -----------------------------------------------------------------------------
RUN_ALL=0
if [ "$1" == "--all" ] || [ -z "$1" ]; then
    RUN_ALL=1
    TEST_LIST=("${UVM_TESTS[@]}")
else
    TEST_LIST=("$1")
fi

PASSED=0
FAILED=0
declare -a FAIL_LIST

for test in "${TEST_LIST[@]}"; do
    echo "-----------------------------------------------------------------------------"
    echo " [UVM TEST] Running: ${test}"
    echo "-----------------------------------------------------------------------------"
    LOG_FILE="${BUILD_DIR}/sim_${test}.log"

    set +e
    ./${BUILD_DIR}/simv_uvm \
        +UVM_TESTNAME=${test} \
        +UVM_VERBOSITY=UVM_MEDIUM \
        -l ${LOG_FILE}
    RET=$?
    set -e

    if [ $RET -eq 0 ] && grep -q "UVM_ERROR :    0" ${LOG_FILE} && grep -q "UVM_FATAL :    0" ${LOG_FILE}; then
        echo "  [PASS] ${test}"
        ((PASSED++))
    else
        echo "  [FAIL] ${test} (check ${LOG_FILE})"
        ((FAILED++))
        FAIL_LIST+=("${test}")
    fi
done

echo "============================================================================="
echo " UVM Regression Summary"
echo " Total : $((PASSED + FAILED))"
echo " Passed: ${PASSED}"
echo " Failed: ${FAILED}"
if [ ${FAILED} -eq 0 ]; then
    echo " ALL UVM REGRESSION TESTS PASSED (100% SUCCESS)"
else
    echo " FAILED TESTS: ${FAIL_LIST[*]}"
fi
echo "============================================================================="

exit ${FAILED}

