// coherency_bus.sv
// Coherency bus for 4-core snoop system with round-robin arbitration.
// Broadcasts one granted request at a time and collects snoop responses.

module coherency_bus #(
    parameter int NUM_CORES  = 4,
    parameter int ADDR_WIDTH = 64
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // Core request inputs
    input  logic [NUM_CORES-1:0]          core_req_valid,
    input  logic [NUM_CORES-1:0][1:0]     core_req_type,   // user-defined encoding
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] core_req_addr,

    // Bus broadcast outputs
    output logic                         bus_valid,
    output logic [ADDR_WIDTH-1:0]        bus_addr,
    output logic [1:0]                   bus_type,
    output logic [1:0]                   granted_core_id,

    // Snoop response inputs (one bit per core)
    input  logic [NUM_CORES-1:0]         snoop_resp
);

    // Simple FSM
    typedef enum logic [1:0] {IDLE, BROADCAST, COMPLETE} bus_state_t;
    bus_state_t state, state_n;

    // Round-robin pointer
    logic [1:0] rr_ptr;
    logic [1:0] rr_ptr_n;

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

    // Snoop response collection (placeholder: OR of all responses)
    logic snoop_any_resp;
    assign snoop_any_resp = |snoop_resp;

    // Next-state logic
    always_comb begin
        state_n       = state;
        rr_ptr_n      = rr_ptr;
        grant_id_n    = granted_core_id;
        grant_valid_n = 1'b0;

        case (state)
            IDLE: begin
                if (has_any_req(core_req_valid)) begin
                    grant_id_n    = next_grant_id(core_req_valid, rr_ptr);
                    grant_valid_n = 1'b1;
                    state_n       = BROADCAST;
                end
            end

            BROADCAST: begin
                // Broadcast granted request for one cycle
                grant_valid_n = 1'b1;
                state_n       = COMPLETE;
                rr_ptr_n      = grant_id_n + 2'd1;
            end

            COMPLETE: begin
                // Placeholder: could wait for snoop responses here
                // For now, complete in one cycle.
                if (snoop_any_resp || !snoop_any_resp) begin
                    state_n = IDLE;
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
            granted_core_id  <= 2'd0;
        end else begin
            state           <= state_n;
            rr_ptr          <= rr_ptr_n;
            if (grant_valid_n) begin
                granted_core_id <= grant_id_n;
            end
        end
    end

    // Bus broadcast signals
    always_comb begin
        bus_valid = (state == BROADCAST);
        bus_addr  = core_req_addr[granted_core_id];
        bus_type  = core_req_type[granted_core_id];
    end

    // Basic assertions: only one grant at a time
    // When broadcasting, the granted core must have a valid request.
    always_ff @(posedge clk) begin
        if (state == BROADCAST) begin
            assert (core_req_valid[granted_core_id])
                else $fatal(1, "coherency_bus: granted core has no valid request");
        end
    end

endmodule
