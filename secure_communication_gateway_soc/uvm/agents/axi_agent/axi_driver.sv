// =============================================================================
// File: axi_driver.sv
// Description: UVM Driver for AXI4 Master Interface
// =============================================================================

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

class axi_driver extends uvm_driver #(axi_seq_item);
    `uvm_component_utils(axi_driver)

    virtual axi_if.master vif;

    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_signals();
        wait (vif.rst === 1'b0);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.rw_type == axi_seq_item::AXI_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        vif.m_cb.awvalid <= 1'b0;
        vif.m_cb.wvalid  <= 1'b0;
        vif.m_cb.bready  <= 1'b0;
        vif.m_cb.arvalid <= 1'b0;
        vif.m_cb.rready  <= 1'b0;
        vif.m_cb.awaddr  <= 32'h0;
        vif.m_cb.wdata   <= 32'h0;
        vif.m_cb.wstrb   <= 4'h0;
        vif.m_cb.araddr  <= 32'h0;
    endtask

    virtual task drive_write(axi_seq_item item);
        bit aw_done = 0;
        bit w_done  = 0;

        @(vif.m_cb);
        vif.m_cb.awid    <= item.id;
        vif.m_cb.awaddr  <= item.addr;
        vif.m_cb.awlen   <= item.len;
        vif.m_cb.awsize  <= item.size;
        vif.m_cb.awburst <= item.burst;
        vif.m_cb.awvalid <= 1'b1;

        vif.m_cb.wdata   <= item.data;
        vif.m_cb.wstrb   <= item.strb;
        vif.m_cb.wlast   <= 1'b1;
        vif.m_cb.wvalid  <= 1'b1;

        while (!(aw_done && w_done)) begin
            @(vif.m_cb);
            if (!aw_done && vif.m_cb.awready) begin
                aw_done = 1;
                vif.m_cb.awvalid <= 1'b0;
            end
            if (!w_done && vif.m_cb.wready) begin
                w_done = 1;
                vif.m_cb.wvalid <= 1'b0;
            end
        end

        // Wait for B response
        vif.m_cb.bready <= 1'b1;
        do begin
            @(vif.m_cb);
        end while (!vif.m_cb.bvalid);

        item.resp = vif.m_cb.bresp;
        vif.m_cb.bready <= 1'b0;
    endtask

    virtual task drive_read(axi_seq_item item);
        @(vif.m_cb);
        vif.m_cb.arid    <= item.id;
        vif.m_cb.araddr  <= item.addr;
        vif.m_cb.arlen   <= item.len;
        vif.m_cb.arsize  <= item.size;
        vif.m_cb.arburst <= item.burst;
        vif.m_cb.arvalid <= 1'b1;

        do begin
            @(vif.m_cb);
        end while (!vif.m_cb.arready);
        vif.m_cb.arvalid <= 1'b0;

        // Await R data
        vif.m_cb.rready <= 1'b1;
        do begin
            @(vif.m_cb);
        end while (!vif.m_cb.rvalid);

        item.data = vif.m_cb.rdata;
        item.resp = vif.m_cb.rresp;
        vif.m_cb.rready <= 1'b0;
    endtask

endclass : axi_driver

`endif // AXI_DRIVER_SV

