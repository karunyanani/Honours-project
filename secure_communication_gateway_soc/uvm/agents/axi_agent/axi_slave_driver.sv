// =============================================================================
// File: axi_slave_driver.sv
// Description: UVM Slave Driver / Memory Responder Model for AXI4 VIP
// =============================================================================

`ifndef AXI_SLAVE_DRIVER_SV
`define AXI_SLAVE_DRIVER_SV

class axi_slave_driver extends uvm_driver #(axi_seq_item);
    `uvm_component_utils(axi_slave_driver)

    virtual axi_if vif;
    axi_agent_config cfg;

    // Internal associative memory array [byte_addr] -> byte
    byte mem[bit [31:0]];

    function new(string name = "axi_slave_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(axi_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = axi_agent_config::type_id::create("default_axi_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.awready <= 1'b1;
        vif.wready  <= 1'b1;
        vif.bvalid  <= 1'b0;
        vif.arready <= 1'b1;
        vif.rvalid  <= 1'b0;

        wait (vif.rst === 1'b0);

        fork
            handle_write_channel();
            handle_read_channel();
        join
    endtask

    virtual task handle_write_channel();
        bit [31:0] cur_awaddr;
        bit [7:0]  cur_awid;

        forever begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.awready) begin
                cur_awaddr = vif.awaddr;
                cur_awid   = vif.awid;

                while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);

                // Write 4 bytes according to wstrb
                for (int b = 0; b < 4; b++) begin
                    if (vif.wstrb[b]) begin
                        mem[cur_awaddr + b] = vif.wdata[b*8 +: 8];
                    end
                end

                // Respond on B channel
                repeat (cfg.bvalid_delay) @(posedge vif.clk);
                vif.bid    <= cur_awid;
                vif.bresp  <= 2'b00; // OKAY
                vif.bvalid <= 1'b1;

                do @(posedge vif.clk); while (!vif.bready);
                vif.bvalid <= 1'b0;
            end
        end
    endtask

    virtual task handle_read_channel();
        bit [31:0] cur_araddr;
        bit [7:0]  cur_arid;
        bit [31:0] rdata_word;

        forever begin
            @(posedge vif.clk);
            if (vif.arvalid && vif.arready) begin
                cur_araddr = vif.araddr;
                cur_arid   = vif.arid;

                // Assemble 4 bytes from memory
                for (int b = 0; b < 4; b++) begin
                    if (mem.exists(cur_araddr + b))
                        rdata_word[b*8 +: 8] = mem[cur_araddr + b];
                    else
                        rdata_word[b*8 +: 8] = 8'h00;
                end

                repeat (cfg.rvalid_delay) @(posedge vif.clk);
                vif.rid    <= cur_arid;
                vif.rdata  <= rdata_word;
                vif.rresp  <= 2'b00; // OKAY
                vif.rlast  <= 1'b1;
                vif.rvalid <= 1'b1;

                do @(posedge vif.clk); while (!vif.rready);
                vif.rvalid <= 1'b0;
            end
        end
    endtask

endclass : axi_slave_driver

`endif // AXI_SLAVE_DRIVER_SV

