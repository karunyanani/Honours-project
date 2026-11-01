// =============================================================================
// File: axi_monitor.sv
// Description: UVM Monitor for AXI4 Bus Transactions
// =============================================================================

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)

    virtual axi_if.monitor vif;
    uvm_analysis_port #(axi_seq_item) ap;

    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    virtual task monitor_writes();
        axi_seq_item item;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                item = axi_seq_item::type_id::create("mon_write_item");
                item.rw_type = axi_seq_item::AXI_WRITE;
                item.id      = vif.mon_cb.awid;
                item.addr    = vif.mon_cb.awaddr;
                item.len     = vif.mon_cb.awlen;
                item.size    = vif.mon_cb.awsize;
                item.burst   = vif.mon_cb.awburst;

                // Wait for W data
                while (!(vif.mon_cb.wvalid && vif.mon_cb.wready)) begin
                    @(vif.mon_cb);
                end
                item.data = vif.mon_cb.wdata;
                item.strb = vif.mon_cb.wstrb;

                // Wait for B response
                while (!(vif.mon_cb.bvalid && vif.mon_cb.bready)) begin
                    @(vif.mon_cb);
                end
                item.resp = vif.mon_cb.bresp;

                ap.write(item);
            end
        end
    endtask

    virtual task monitor_reads();
        axi_seq_item item;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                item = axi_seq_item::type_id::create("mon_read_item");
                item.rw_type = axi_seq_item::AXI_READ;
                item.id      = vif.mon_cb.arid;
                item.addr    = vif.mon_cb.araddr;
                item.len     = vif.mon_cb.arlen;
                item.size    = vif.mon_cb.arsize;
                item.burst   = vif.mon_cb.arburst;

                // Wait for R data
                while (!(vif.mon_cb.rvalid && vif.mon_cb.rready)) begin
                    @(vif.mon_cb);
                end
                item.data = vif.mon_cb.rdata;
                item.resp = vif.mon_cb.rresp;

                ap.write(item);
            end
        end
    endtask

endclass : axi_monitor

`endif // AXI_MONITOR_SV

