#!/bin/bash
# =============================================================================
# Script: run_verdi.sh
# Description: Launch Synopsys Verdi waveform debugging on generated FSDB
# Usage: ./scripts/run_verdi.sh [fsdb_file]
# =============================================================================

FSDB_FILE=${1:-soc_uvm.fsdb}

if [ ! -f "${FSDB_FILE}" ]; then
    echo "Error: FSDB file '${FSDB_FILE}' not found. Run simulation first."
    exit 1
fi

echo "Launching Synopsys Verdi with ${FSDB_FILE}..."
verdi -ssf ${FSDB_FILE} -f uvm/uvm_filelist.f &

