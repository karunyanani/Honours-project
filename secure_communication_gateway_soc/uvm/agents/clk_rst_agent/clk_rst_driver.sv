// =============================================================================
// File: clk_rst_driver.sv
// Description: UVM Driver for Clock and Reset Generator VIP
// =============================================================================

`ifndef CLK_RST_DRIVER_SV
`define CLK_RST_DRIVER_SV

class clk_rst_driver extends uvm_driver #(clk_rst_seq_item);
    `uvm_component_utils(clk_rst_driver)

    virtual clk_rst_if vif;
    clk_rst_agent_config cfg;

    time cur_half_period;

    function new(string name = "clk_rst_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual clk_rst_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(clk_rst_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = clk_rst_agent_config::type_id::create("default_clk_rst_cfg");
        end
        cur_half_period = cfg.clk_period_ns / 2;
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Start clock generator process in background
        fork
            clock_gen_process();
        join_none

        // Initial reset state
        if (cfg.start_in_reset) begin
            vif.rst   <= 1'b1;
            vif.rst_n <= 1'b0;
            #(cfg.reset_duration_ns);
            vif.rst   <= 1'b0;
            vif.rst_n <= 1'b1;
        end

        forever begin
            seq_item_port.get_next_item(req);
            execute_op(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task clock_gen_process();
        vif.clk = 1'b0;
        forever begin
            #(cur_half_period);
            vif.clk = ~vif.clk;
        end
    endtask

    virtual task execute_op(clk_rst_seq_item item);
        case (item.op_type)
            clk_rst_seq_item::CLK_SET_FREQ: begin
                cur_half_period = item.new_period_ns / 2;
            end

            clk_rst_seq_item::RST_ASSERT: begin
                vif.rst   <= 1'b1;
                vif.rst_n <= 1'b0;
            end

            clk_rst_seq_item::RST_DEASSERT: begin
                vif.rst   <= 1'b0;
                vif.rst_n <= 1'b1;
            end

            clk_rst_seq_item::RST_PULSE: begin
                vif.rst   <= 1'b1;
                vif.rst_n <= 1'b0;
                #(item.duration_ns);
                vif.rst   <= 1'b0;
                vif.rst_n <= 1'b1;
            end

            clk_rst_seq_item::RST_GLITCH: begin
                vif.rst   <= 1'b1;
                vif.rst_n <= 1'b0;
                #1ns;
                vif.rst   <= 1'b0;
                vif.rst_n <= 1'b1;
            end
        endcase
    endtask

endclass : clk_rst_driver

`endif // CLK_RST_DRIVER_SV

