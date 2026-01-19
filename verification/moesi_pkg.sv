// moesi_pkg.sv
// UVM package containing request object and base sequence for MOESI system.

package moesi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // -------------------------------------------------------------------------
    // MOESI request object
    // -------------------------------------------------------------------------
    class moesi_request extends uvm_sequence_item;
        // Core identifier
        rand int unsigned core_id;

        // Address and data
        rand bit [63:0]   addr;
        rand bit [511:0]  wdata;
        bit  [511:0]      rdata;

        // Request type matches core_req_type (2'b01=READ, 2'b10=WRITE, 2'b11=UPGRADE)
        rand bit [1:0]    req_type;

        // Observed metrics
        int unsigned      latency;
        bit [2:0]         final_state;

        // Constraints
        constraint c_core_id { core_id inside {[0:3]}; }
        constraint c_req_type { req_type inside {2'b01, 2'b10, 2'b11}; }

        `uvm_object_utils_begin(moesi_request)
            `uvm_field_int(core_id,    UVM_ALL_ON)
            `uvm_field_int(addr,       UVM_ALL_ON)
            `uvm_field_int(req_type,   UVM_ALL_ON)
            `uvm_field_int(wdata,      UVM_ALL_ON)
            `uvm_field_int(rdata,      UVM_ALL_ON)
            `uvm_field_int(latency,    UVM_ALL_ON)
            `uvm_field_int(final_state,UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "moesi_request");
            super.new(name);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // Base sequence: random traffic generator
    // -------------------------------------------------------------------------
    class moesi_base_seq extends uvm_sequence #(moesi_request);
        // Configurable ratios (percentages)
        rand int unsigned read_ratio;
        rand int unsigned write_ratio;
        rand int unsigned upgrade_ratio;

        // Number of transactions to generate
        rand int unsigned num_trans;

        constraint c_ratios {
            read_ratio + write_ratio + upgrade_ratio == 100;
            read_ratio   inside {[0:100]};
            write_ratio  inside {[0:100]};
            upgrade_ratio inside {[0:100]};
        }

        constraint c_num_trans { num_trans inside {[1:1000]}; }

        `uvm_object_utils_begin(moesi_base_seq)
            `uvm_field_int(read_ratio,    UVM_ALL_ON)
            `uvm_field_int(write_ratio,   UVM_ALL_ON)
            `uvm_field_int(upgrade_ratio, UVM_ALL_ON)
            `uvm_field_int(num_trans,     UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "moesi_base_seq");
            super.new(name);
            // Default ratios: 50% reads, 40% writes, 10% upgrades
            read_ratio    = 50;
            write_ratio   = 40;
            upgrade_ratio = 10;
            num_trans     = 100;
        endfunction

        virtual task body();
            moesi_request req;
            int unsigned  r;
            int unsigned  i;
            bit [1:0]     desired_type;

            for (i = 0; i < num_trans; i++) begin
                req = moesi_request::type_id::create("req");

                // Pick request type based on ratios
                r = $urandom_range(0, 99);
                if (r < read_ratio) begin
                    desired_type = 2'b01; // READ
                end else if (r < (read_ratio + write_ratio)) begin
                    desired_type = 2'b10; // WRITE
                end else begin
                    desired_type = 2'b11; // UPGRADE
                end
                req.req_type = desired_type;

                // Randomize remaining fields
                if (!req.randomize() with { req.req_type == desired_type; }) begin
                    `uvm_warning("MOESI_SEQ", "Request randomization failed")
                end

                // Send transaction
                start_item(req);
                finish_item(req);
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Derived sequence: read_hit_seq
    // Targets a small working set to encourage cache hits after warm-up.
    // -------------------------------------------------------------------------
    class read_hit_seq extends moesi_base_seq;
        `uvm_object_utils(read_hit_seq)

        function new(string name = "read_hit_seq");
            super.new(name);
            read_ratio    = 90;
            write_ratio   = 10;
            upgrade_ratio = 0;
            num_trans     = 200;
        endfunction

        virtual task body();
            moesi_request req;
            int unsigned i;
            bit [63:0] hot_base;
            hot_base = 64'h0000_1000;

            // Small address window to promote cache reuse (read hits).
            for (i = 0; i < num_trans; i++) begin
                req = moesi_request::type_id::create("req");
                req.req_type = 2'b01; // READ
                if (!req.randomize() with {
                    req.req_type == 2'b01;
                    req.addr inside {[hot_base : hot_base + 64*8]}; // 8 lines window
                }) begin
                    `uvm_warning("READ_HIT_SEQ", "Request randomization failed")
                end
                start_item(req);
                finish_item(req);
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Derived sequence: read_miss_seq
    // Targets a wide, cold address space to maximize miss rate.
    // -------------------------------------------------------------------------
    class read_miss_seq extends moesi_base_seq;
        `uvm_object_utils(read_miss_seq)

        function new(string name = "read_miss_seq");
            super.new(name);
            read_ratio    = 100;
            write_ratio   = 0;
            upgrade_ratio = 0;
            num_trans     = 200;
        endfunction

        virtual task body();
            moesi_request req;
            int unsigned i;

            // Use large stride to avoid reusing cached lines.
            for (i = 0; i < num_trans; i++) begin
                req = moesi_request::type_id::create("req");
                req.req_type = 2'b01; // READ
                if (!req.randomize() with {
                    req.req_type == 2'b01;
                    req.addr == (64'h0001_0000 + (i * 64'h1000));
                }) begin
                    `uvm_warning("READ_MISS_SEQ", "Request randomization failed")
                end
                start_item(req);
                finish_item(req);
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Derived sequence: write_coherency_seq
    // Creates shared lines, then writes to force S->M invalidation.
    // -------------------------------------------------------------------------
    class write_coherency_seq extends moesi_base_seq;
        `uvm_object_utils(write_coherency_seq)

        function new(string name = "write_coherency_seq");
            super.new(name);
            read_ratio    = 50;
            write_ratio   = 50;
            upgrade_ratio = 0;
            num_trans     = 100;
        endfunction

        virtual task body();
            moesi_request req;
            int unsigned i;
            bit [63:0] shared_addr;
            shared_addr = 64'h0000_2000;

            // Phase 1: reads from multiple cores to create shared lines (S state).
            for (i = 0; i < 8; i++) begin
                req = moesi_request::type_id::create("req");
                req.req_type = 2'b01; // READ
                if (!req.randomize() with {
                    req.req_type == 2'b01;
                    req.core_id inside {[0:3]};
                    req.addr == shared_addr;
                }) begin
                    `uvm_warning("WRITE_COH_SEQ", "Read phase randomization failed")
                end
                start_item(req);
                finish_item(req);
            end

            // Phase 2: writes to same line to force invalidation (S->M).
            for (i = 0; i < 8; i++) begin
                req = moesi_request::type_id::create("req");
                req.req_type = 2'b10; // WRITE
                if (!req.randomize() with {
                    req.req_type == 2'b10;
                    req.core_id inside {[0:3]};
                    req.addr == shared_addr;
                }) begin
                    `uvm_warning("WRITE_COH_SEQ", "Write phase randomization failed")
                end
                start_item(req);
                finish_item(req);
            end
        endtask
    endclass

endpackage
