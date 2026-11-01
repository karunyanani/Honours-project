#!/bin/bash
# =============================================================================
# Script: run_vcs_uvm.sh
# Description: Synopsys VCS compilation and execution script for UVM Suite
# Usage: ./scripts/run_vcs_uvm.sh [test_name]
# Available Tests:
#   - soc_reg_access_test
#   - soc_access_control_test
#   - soc_gateway_pipeline_test
#   - soc_wdt_recovery_test
# =============================================================================

set -e

TEST_NAME=${1:-soc_gateway_pipeline_test}
BUILD_DIR=build
mkdir -p ${BUILD_DIR}

echo "=================================================================="
echo " Starting VCS UVM Compilation for Test: ${TEST_NAME}"
echo "=================================================================="

vcs -full64 -sverilog \
    -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    +define+DUMP_FSDB \
    -kdb -lca \
    -f uvm/uvm_filelist.f \
    -o ${BUILD_DIR}/simv_uvm \
    -l ${BUILD_DIR}/vcs_compile.log

echo "=================================================================="
echo " Running VCS UVM Simulation: ${TEST_NAME}"
echo "=================================================================="

./${BUILD_DIR}/simv_uvm \
    +UVM_TESTNAME=${TEST_NAME} \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -l ${BUILD_DIR}/sim_${TEST_NAME}.log

echo "=================================================================="
echo " Simulation Complete! Log: ${BUILD_DIR}/sim_${TEST_NAME}.log"
echo " FSDB Waveform: soc_uvm.fsdb"
echo "=================================================================="

