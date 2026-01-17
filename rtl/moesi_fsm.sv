// moesi_fsm.sv
// Combinational MOESI next-state logic based on local and snoop events.
// Encoding: M=3'b001, O=3'b010, E=3'b100, S=3'b101, I=3'b000

module moesi_fsm (
    input  logic [2:0] curr_state,
    input  logic       local_read_hit,
    input  logic       local_read_miss,
    input  logic       local_write_hit,
    input  logic       local_write_miss,
    input  logic       snoop_read,
    input  logic       snoop_write,
    input  logic       snoop_invalidate,
    output logic [2:0] next_state,
    output logic       provide_data,
    output logic       cache_invalidated
);

    // MOESI encoding (as requested)
    localparam logic [2:0] MOESI_M = 3'b001;
    localparam logic [2:0] MOESI_O = 3'b010;
    localparam logic [2:0] MOESI_E = 3'b100;
    localparam logic [2:0] MOESI_S = 3'b101;
    localparam logic [2:0] MOESI_I = 3'b000;

    // Default outputs
    always_comb begin
        next_state        = curr_state;
        provide_data      = 1'b0;
        cache_invalidated = 1'b0;

        case (curr_state)
            MOESI_M: begin
                // Priority: snoop_invalidate > snoop_write > snoop_read > local_write_miss > local_write_hit > local_read_miss > local_read_hit
                if (snoop_invalidate) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1; // explicit invalidate
                end else if (snoop_write) begin
                    next_state        = MOESI_I;
                    provide_data      = 1'b1; // supply data on BusRdX/Upgr
                    cache_invalidated = 1'b1;
                end else if (snoop_read) begin
                    next_state   = MOESI_O;
                    provide_data = 1'b1; // supply data, downgrade M->O
                end else if (local_write_miss) begin
                    next_state = MOESI_M; // already M
                end else if (local_write_hit) begin
                    next_state = MOESI_M; // already M
                end else if (local_read_miss) begin
                    next_state = MOESI_M; // miss should not occur in M
                end else if (local_read_hit) begin
                    next_state = MOESI_M;
                end
            end

            MOESI_O: begin
                if (snoop_invalidate) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1;
                end else if (snoop_write) begin
                    next_state        = MOESI_I;
                    provide_data      = 1'b1; // owner supplies data
                    cache_invalidated = 1'b1;
                end else if (snoop_read) begin
                    next_state   = MOESI_O;
                    provide_data = 1'b1; // owner supplies data
                end else if (local_write_miss) begin
                    next_state = MOESI_M; // upgrade to M (invalidate others externally)
                end else if (local_write_hit) begin
                    next_state = MOESI_M; // upgrade to M (invalidate others externally)
                end else if (local_read_miss) begin
                    next_state = MOESI_O; // miss should not occur in O
                end else if (local_read_hit) begin
                    next_state = MOESI_O;
                end
            end

            MOESI_E: begin
                if (snoop_invalidate) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1;
                end else if (snoop_write) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1; // BusRdX/Upgr invalidates
                end else if (snoop_read) begin
                    next_state   = MOESI_S;
                    provide_data = 1'b0; // E/S do not supply data per spec
                end else if (local_write_miss) begin
                    next_state = MOESI_M; // write miss alloc -> M
                end else if (local_write_hit) begin
                    next_state = MOESI_M; // silent upgrade
                end else if (local_read_miss) begin
                    next_state = MOESI_E; // miss should not occur in E
                end else if (local_read_hit) begin
                    next_state = MOESI_E;
                end
            end

            MOESI_S: begin
                if (snoop_invalidate) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1;
                end else if (snoop_write) begin
                    next_state        = MOESI_I;
                    cache_invalidated = 1'b1; // invalidate on write/upgrade
                end else if (snoop_read) begin
                    next_state   = MOESI_S;
                    provide_data = 1'b0; // not owner
                end else if (local_write_miss) begin
                    next_state = MOESI_M; // write miss alloc -> M
                end else if (local_write_hit) begin
                    next_state = MOESI_M; // upgrade to M (invalidate others externally)
                end else if (local_read_miss) begin
                    next_state = MOESI_S; // miss should not occur in S
                end else if (local_read_hit) begin
                    next_state = MOESI_S;
                end
            end

            MOESI_I: begin
                if (snoop_invalidate) begin
                    next_state = MOESI_I; // already invalid
                end else if (snoop_write) begin
                    next_state = MOESI_I; // no line to invalidate
                end else if (snoop_read) begin
                    next_state = MOESI_I; // no line to supply
                end else if (local_write_miss) begin
                    next_state = MOESI_M; // write miss alloc -> M
                end else if (local_write_hit) begin
                    next_state = MOESI_I; // invalid hit should not occur
                end else if (local_read_miss) begin
                    // Without a shared indicator, default to E (exclusive).
                    // External logic can override to S when sharers are detected.
                    next_state = MOESI_E;
                end else if (local_read_hit) begin
                    next_state = MOESI_I; // invalid hit should not occur
                end
            end

            default: begin
                next_state        = MOESI_I;
                provide_data      = 1'b0;
                cache_invalidated = 1'b0;
            end
        endcase
    end

endmodule
