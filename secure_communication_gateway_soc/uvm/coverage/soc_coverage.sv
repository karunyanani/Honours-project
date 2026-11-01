// =============================================================================
// File: soc_coverage.sv
// Description: UVM Functional Coverage Collector for Gateway SoC
// Models:
//   - AXI4 2x9 Interconnect Memory Map & Master-Slave Access Crosses
//   - AXI Response Types (OKAY, DECERR)
//   - Gateway Datapath Operations (DMA Modes, AES, SPI, UART, WDT)
// =============================================================================

`ifndef SOC_COVERAGE_SV
`define SOC_COVERAGE_SV

class soc_coverage extends uvm_subscriber #(axi_seq_item);
    `uvm_component_utils(soc_coverage)

    axi_seq_item cur_item;

    covergroup axi_mem_map_cg;
        option.per_instance = 1;
        option.name = "AXI_Memory_Map_Coverage";

        cp_master: coverpoint cur_item.id[7:4] {
            bins CPU = {4'h0};
            bins DMA = {4'h1};
        }

        cp_rw: coverpoint cur_item.rw_type {
            bins READ  = {axi_seq_item::AXI_READ};
            bins WRITE = {axi_seq_item::AXI_WRITE};
        }

        cp_slave: coverpoint cur_item.addr {
            bins IMEM     = {[32'h0000_0000 : 32'h0000_FFFF]};
            bins DMEM     = {[32'h0001_0000 : 32'h0001_FFFF]};
            bins UART     = {[32'h1000_0000 : 32'h1000_00FF]};
            bins TIMER    = {[32'h1000_0100 : 32'h1000_01FF]};
            bins GPIO     = {[32'h1000_0200 : 32'h1000_02FF]};
            bins AES      = {[32'h1000_0300 : 32'h1000_03FF]};
            bins DMA_CFG  = {[32'h1000_0400 : 32'h1000_04FF]};
            bins SPI      = {[32'h1000_0500 : 32'h1000_05FF]};
            bins WDT      = {[32'h1000_0600 : 32'h1000_06FF]};
            bins UNMAPPED = {[32'h2000_0000 : 32'hFFFF_FFFF]};
        }

        cp_resp: coverpoint cur_item.resp {
            bins OKAY   = {2'b00};
            bins DECERR = {2'b11};
        }

        // Cross of Master x Slave x RW type
        cross_access: cross cp_master, cp_slave, cp_rw;

        // Cross of Master x Slave x Response (to verify DECERR on illegal accesses)
        cross_security: cross cp_master, cp_slave, cp_resp;
    endgroup

    function new(string name = "soc_coverage", uvm_component parent = null);
        super.new(name, parent);
        axi_mem_map_cg = new();
    endfunction

    virtual function void write(axi_seq_item t);
        cur_item = t;
        axi_mem_map_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV_REPORT", $sformatf("AXI Interconnect Functional Coverage: %0.2f%%",
            axi_mem_map_cg.get_inst_coverage()), UVM_NONE)
    endfunction

endclass : soc_coverage

`endif // SOC_COVERAGE_SV

