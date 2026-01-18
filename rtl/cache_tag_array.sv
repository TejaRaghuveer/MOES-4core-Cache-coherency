// cache_tag_array.sv
// Tag array for 4-way set-associative cache with MOESI state and LRU bits.
// Provides read of all ways for a set and write update for a single way.

module cache_tag_array #(
    parameter int SETS        = 128,
    parameter int WAYS        = 4,
    parameter int ADDR_WIDTH  = 32,
    // Tag width derived from sets and 64B line size (6 offset bits).
    parameter int TAG_WIDTH   = ADDR_WIDTH - $clog2(SETS) - 6,
    // Simple LRU storage width per way (no update logic in this module).
    parameter int LRU_BITS    = 2
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // Read interface (core): read all ways for a set
    input  logic [$clog2(SETS)-1:0]        core_read_set,
    output logic [WAYS-1:0][TAG_WIDTH-1:0] core_read_tags,
    output logic [WAYS-1:0]                core_read_valids,
    output logic [WAYS-1:0][2:0]           core_read_states,
    output logic [WAYS-1:0][LRU_BITS-1:0]  core_read_lru,

    // Read interface (snoop): read all ways for a set
    input  logic [$clog2(SETS)-1:0]        snoop_read_set,
    output logic [WAYS-1:0][TAG_WIDTH-1:0] snoop_read_tags,
    output logic [WAYS-1:0]                snoop_read_valids,
    output logic [WAYS-1:0][2:0]           snoop_read_states,
    output logic [WAYS-1:0][LRU_BITS-1:0]  snoop_read_lru,

    // Write interface: update a single way in a set
    input  logic                         write_en,
    input  logic [$clog2(SETS)-1:0]       write_set,
    input  logic [$clog2(WAYS)-1:0]       write_way,
    input  logic [TAG_WIDTH-1:0]         write_tag,
    input  logic                         write_valid,
    input  logic [2:0]                   write_state,
    input  logic [LRU_BITS-1:0]          write_lru
);

    // MOESI encoding (explicit, as requested)
    localparam logic [2:0] MOESI_M = 3'b001;
    localparam logic [2:0] MOESI_O = 3'b010;
    localparam logic [2:0] MOESI_E = 3'b100;
    localparam logic [2:0] MOESI_S = 3'b101;
    localparam logic [2:0] MOESI_I = 3'b000;

    // Storage arrays: [set][way]
    logic [TAG_WIDTH-1:0]   tag_mem   [0:SETS-1][0:WAYS-1];
    logic                   valid_mem [0:SETS-1][0:WAYS-1];
    logic [2:0]             state_mem [0:SETS-1][0:WAYS-1];
    logic [LRU_BITS-1:0]    lru_mem   [0:SETS-1][0:WAYS-1];

    integer set_i;
    integer way_i;

    // Reset: invalidate all entries and set state to I.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (set_i = 0; set_i < SETS; set_i = set_i + 1) begin
                for (way_i = 0; way_i < WAYS; way_i = way_i + 1) begin
                    tag_mem[set_i][way_i]   <= '0;
                    valid_mem[set_i][way_i] <= 1'b0;
                    state_mem[set_i][way_i] <= MOESI_I;
                    lru_mem[set_i][way_i]   <= '0;
                end
            end
        end else begin
            if (write_en) begin
                tag_mem[write_set][write_way]   <= write_tag;
                valid_mem[write_set][write_way] <= write_valid;
                state_mem[write_set][write_way] <= write_state;
                lru_mem[write_set][write_way]   <= write_lru;
            end
        end
    end

    // Combinational read of all ways in a set (core port).
    always_comb begin
        for (way_i = 0; way_i < WAYS; way_i = way_i + 1) begin
            core_read_tags[way_i]   = tag_mem[core_read_set][way_i];
            core_read_valids[way_i] = valid_mem[core_read_set][way_i];
            core_read_states[way_i] = state_mem[core_read_set][way_i];
            core_read_lru[way_i]    = lru_mem[core_read_set][way_i];
        end
    end

    // Combinational read of all ways in a set (snoop port).
    always_comb begin
        for (way_i = 0; way_i < WAYS; way_i = way_i + 1) begin
            snoop_read_tags[way_i]   = tag_mem[snoop_read_set][way_i];
            snoop_read_valids[way_i] = valid_mem[snoop_read_set][way_i];
            snoop_read_states[way_i] = state_mem[snoop_read_set][way_i];
            snoop_read_lru[way_i]    = lru_mem[snoop_read_set][way_i];
        end
    end

endmodule
