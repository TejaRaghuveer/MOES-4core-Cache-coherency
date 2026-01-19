// snoop_handler.sv
// Combinational snoop response logic for MOESI cache.

module snoop_handler (
    input  logic [1:0]  snoop_type,   // 2'b01=READ, 2'b10=WRITE, 2'b11=UPGRADE
    input  logic [63:0] snoop_addr,   // unused here, provided for completeness
    input  logic        tag_match,    // 1 if this cache has the line
    input  logic        line_valid,   // line is valid
    input  logic [2:0]  curr_state,   // MOESI state
    output logic [2:0]  new_state,
    output logic        provide_data,
    output logic        must_invalidate
);

    // MOESI encoding
    localparam logic [2:0] MOESI_M = 3'b000;
    localparam logic [2:0] MOESI_O = 3'b001;
    localparam logic [2:0] MOESI_E = 3'b010;
    localparam logic [2:0] MOESI_S = 3'b011;
    localparam logic [2:0] MOESI_I = 3'b100;

    // Snoop type encoding
    localparam logic [1:0] SNOOP_READ    = 2'b01;
    localparam logic [1:0] SNOOP_WRITE   = 2'b10;
    localparam logic [1:0] SNOOP_UPGRADE = 2'b11;

    always_comb begin
        // Default: no effect
        new_state       = curr_state;
        provide_data    = 1'b0;
        must_invalidate = 1'b0;

        // If line not present or invalid, no action
        if (!tag_match || !line_valid) begin
            new_state       = curr_state;
            provide_data    = 1'b0;
            must_invalidate = 1'b0;
        end else begin
            case (snoop_type)
                SNOOP_READ: begin
                    // READ: M/O supply data, E/S do not supply
                    case (curr_state)
                        MOESI_M: begin
                            new_state    = MOESI_O; // M->O on shared read
                            provide_data = 1'b1;
                        end
                        MOESI_O: begin
                            new_state    = MOESI_O; // O stays O
                            provide_data = 1'b1;
                        end
                        MOESI_E: begin
                            new_state    = MOESI_S; // E->S
                            provide_data = 1'b1; // E supplies data on BusRd
                        end
                        MOESI_S: begin
                            new_state    = MOESI_S; // S stays S
                            provide_data = 1'b0;
                        end
                        default: begin
                            new_state    = curr_state;
                            provide_data = 1'b0;
                        end
                    endcase
                end

                SNOOP_WRITE,
                SNOOP_UPGRADE: begin
                    // WRITE/UPGRADE: any valid state -> I
                    new_state       = MOESI_I;
                    must_invalidate = 1'b1;
                    // M/O/E can supply data on write/upgrade snoop
                    provide_data    = (curr_state == MOESI_M) ||
                                      (curr_state == MOESI_O) ||
                                      (curr_state == MOESI_E);
                end

                default: begin
                    new_state       = curr_state;
                    provide_data    = 1'b0;
                    must_invalidate = 1'b0;
                end
            endcase
        end
    end

endmodule
