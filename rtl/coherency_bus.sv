// coherency_bus.sv
// Skeleton coherency bus for 4-core snoop system with round-robin arbitration.
// Focuses on request arbitration and broadcast; snoop responses are not included.

module coherency_bus #(
    parameter int NUM_CORES  = 4,
    parameter int ADDR_WIDTH = 64,
    parameter int HOLD_CYCLES = 2  // cycles to hold request on bus
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // Core request inputs
    input  logic [NUM_CORES-1:0]          core_req_valid,
    input  logic [NUM_CORES-1:0]          core_req_type,   // user-defined encoding
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] core_req_addr,

    // Bus broadcast outputs
    output logic                         bus_valid,
    output logic [ADDR_WIDTH-1:0]        bus_addr,
    output logic                         bus_type,
    output logic [1:0]                   granted_core_id
);

    // Simple FSM
    typedef enum logic [1:0] {IDLE, GRANT, HOLD} bus_state_t;
    bus_state_t state, state_n;

    // Round-robin pointer
    logic [1:0] rr_ptr;
    logic [1:0] rr_ptr_n;

    // Hold counter
    logic [$clog2(HOLD_CYCLES+1)-1:0] hold_cnt;
    logic [$clog2(HOLD_CYCLES+1)-1:0] hold_cnt_n;

    // Selected grant
    logic [1:0] grant_id_n;
    logic       grant_valid_n;

    // Arbitration: pick next valid request starting from rr_ptr
    function automatic logic [1:0] next_grant_id(
        input logic [NUM_CORES-1:0] reqs,
        input logic [1:0]           start
    );
        logic [1:0] sel;
        begin
            sel = 2'd0;
            if (reqs[start]) begin
                sel = start;
            end else if (reqs[(start+1) % NUM_CORES]) begin
                sel = (start+1) % NUM_CORES;
            end else if (reqs[(start+2) % NUM_CORES]) begin
                sel = (start+2) % NUM_CORES;
            end else if (reqs[(start+3) % NUM_CORES]) begin
                sel = (start+3) % NUM_CORES;
            end
            return sel;
        end
    endfunction

    function automatic logic has_any_req(input logic [NUM_CORES-1:0] reqs);
        return |reqs;
    endfunction

    // Next-state logic
    always_comb begin
        state_n       = state;
        rr_ptr_n      = rr_ptr;
        hold_cnt_n    = hold_cnt;
        grant_id_n    = granted_core_id;
        grant_valid_n = 1'b0;

        case (state)
            IDLE: begin
                if (has_any_req(core_req_valid)) begin
                    grant_id_n    = next_grant_id(core_req_valid, rr_ptr);
                    grant_valid_n = 1'b1;
                    state_n       = GRANT;
                end
            end

            GRANT: begin
                // Latch request onto bus and start hold
                grant_valid_n = 1'b1;
                hold_cnt_n    = HOLD_CYCLES[$clog2(HOLD_CYCLES+1)-1:0];
                state_n       = HOLD;
                rr_ptr_n      = grant_id_n + 2'd1;
            end

            HOLD: begin
                grant_valid_n = 1'b1;
                if (hold_cnt == 0) begin
                    state_n = IDLE;
                end else begin
                    hold_cnt_n = hold_cnt - 1'b1;
                end
            end

            default: state_n = IDLE;
        endcase
    end

    // State registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            rr_ptr           <= 2'd0;
            hold_cnt         <= '0;
            granted_core_id  <= 2'd0;
        end else begin
            state           <= state_n;
            rr_ptr          <= rr_ptr_n;
            hold_cnt        <= hold_cnt_n;
            if (grant_valid_n) begin
                granted_core_id <= grant_id_n;
            end
        end
    end

    // Bus broadcast signals
    always_comb begin
        bus_valid = (state != IDLE);
        bus_addr  = core_req_addr[granted_core_id];
        bus_type  = core_req_type[granted_core_id];
    end

endmodule
