// cache_controller.sv
// Skeleton cache controller for 4-way MOESI L1 D-cache.
// Instantiates data/tag arrays, LRU, MOESI FSM, and snoop handler.

module cache_controller #(
    parameter int SETS        = 128,
    parameter int WAYS        = 4,
    parameter int LINE_BYTES  = 64,
    parameter int DATA_WIDTH  = LINE_BYTES * 8, // 512-bit line
    parameter int ADDR_WIDTH  = 64
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // CPU side
    input  logic                  core_req_valid,
    input  logic                  core_req_type,   // 0=READ, 1=WRITE
    input  logic [ADDR_WIDTH-1:0] core_addr,
    input  logic [DATA_WIDTH-1:0] core_wdata,
    output logic                  core_resp_valid,
    output logic [DATA_WIDTH-1:0] core_rdata,

    // Bus side
    output logic                  bus_req_valid,
    output logic [1:0]            bus_req_type,     // BusRd/BusRdX/BusUpgr
    output logic [ADDR_WIDTH-1:0] bus_req_addr,

    // Snoop inputs
    input  logic [1:0]            snoop_type,       // 2'b01=READ, 2'b10=WRITE, 2'b11=UPGRADE
    input  logic [ADDR_WIDTH-1:0] snoop_addr,
    input  logic                  snoop_valid
);

    // -------------------------------------------------------------------------
    // Address breakdown
    // -------------------------------------------------------------------------
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS  = $clog2(SETS);
    localparam int TAG_WIDTH   = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    logic [INDEX_BITS-1:0] req_set;
    logic [TAG_WIDTH-1:0]  req_tag;

    assign req_set = core_addr[OFFSET_BITS +: INDEX_BITS];
    assign req_tag = core_addr[ADDR_WIDTH-1 -: TAG_WIDTH];

    // -------------------------------------------------------------------------
    // Tag array signals
    // -------------------------------------------------------------------------
    logic [WAYS-1:0][TAG_WIDTH-1:0] tag_read_tags;
    logic [WAYS-1:0]               tag_read_valids;
    logic [WAYS-1:0][2:0]          tag_read_states;
    logic [WAYS-1:0][1:0]          tag_read_lru;

    logic                          tag_write_en;
    logic [INDEX_BITS-1:0]         tag_write_set;
    logic [$clog2(WAYS)-1:0]       tag_write_way;
    logic [TAG_WIDTH-1:0]          tag_write_tag;
    logic                          tag_write_valid;
    logic [2:0]                    tag_write_state;
    logic [1:0]                    tag_write_lru;

    // -------------------------------------------------------------------------
    // Data array signals
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]         data_read_data;
    logic [INDEX_BITS-1:0]         data_read_set;
    logic [$clog2(WAYS)-1:0]       data_read_way;

    logic [INDEX_BITS-1:0]         data_write_set;
    logic [$clog2(WAYS)-1:0]       data_write_way;
    logic [DATA_WIDTH-1:0]         data_write_data;
    logic [LINE_BYTES-1:0]         data_write_mask;

    // -------------------------------------------------------------------------
    // LRU signals
    // -------------------------------------------------------------------------
    logic [INDEX_BITS-1:0]         lru_access_set;
    logic [$clog2(WAYS)-1:0]       lru_access_way;
    logic                          lru_access_valid;
    logic [$clog2(WAYS)-1:0]       lru_victim_way;

    // -------------------------------------------------------------------------
    // MOESI FSM signals
    // -------------------------------------------------------------------------
    logic [2:0]                    curr_state;
    logic [2:0]                    next_state;
    logic                          provide_data;
    logic                          cache_invalidated;

    logic                          local_read_hit;
    logic                          local_read_miss;
    logic                          local_write_hit;
    logic                          local_write_miss;

    // -------------------------------------------------------------------------
    // Snoop handler signals
    // -------------------------------------------------------------------------
    logic [2:0]                    snoop_new_state;
    logic                          snoop_provide_data;
    logic                          snoop_must_invalidate;

    logic                          snoop_tag_match;
    logic                          snoop_line_valid;

    // -------------------------------------------------------------------------
    // Instantiate tag array
    // -------------------------------------------------------------------------
    cache_tag_array #(
        .SETS(SETS),
        .WAYS(WAYS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .LRU_BITS(2)
    ) u_tag_array (
        .clk(clk),
        .rst_n(rst_n),
        .read_set(req_set),
        .read_tags(tag_read_tags),
        .read_valids(tag_read_valids),
        .read_states(tag_read_states),
        .read_lru(tag_read_lru),
        .write_en(tag_write_en),
        .write_set(tag_write_set),
        .write_way(tag_write_way),
        .write_tag(tag_write_tag),
        .write_valid(tag_write_valid),
        .write_state(tag_write_state),
        .write_lru(tag_write_lru)
    );

    // -------------------------------------------------------------------------
    // Instantiate data array
    // -------------------------------------------------------------------------
    cache_data_array #(
        .SETS(SETS),
        .WAYS(WAYS),
        .LINE_BYTES(LINE_BYTES),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_data_array (
        .clk(clk),
        .rst_n(rst_n),
        .read_set(data_read_set),
        .read_way(data_read_way),
        .read_data(data_read_data),
        .write_set(data_write_set),
        .write_way(data_write_way),
        .write_data(data_write_data),
        .write_mask(data_write_mask)
    );

    // -------------------------------------------------------------------------
    // Instantiate LRU
    // -------------------------------------------------------------------------
    lru_4way #(
        .SETS(SETS)
    ) u_lru (
        .clk(clk),
        .rst_n(rst_n),
        .access_set(lru_access_set),
        .access_way(lru_access_way),
        .access_valid(lru_access_valid),
        .victim_way(lru_victim_way)
    );

    // -------------------------------------------------------------------------
    // Instantiate MOESI FSM (combinational)
    // -------------------------------------------------------------------------
    moesi_fsm u_moesi_fsm (
        .curr_state(curr_state),
        .local_read_hit(local_read_hit),
        .local_read_miss(local_read_miss),
        .local_write_hit(local_write_hit),
        .local_write_miss(local_write_miss),
        .snoop_read(snoop_valid && (snoop_type == 2'b01)),
        .snoop_write(snoop_valid && (snoop_type == 2'b10 || snoop_type == 2'b11)),
        .snoop_invalidate(1'b0), // TODO: connect explicit invalidate if used
        .next_state(next_state),
        .provide_data(provide_data),
        .cache_invalidated(cache_invalidated)
    );

    // -------------------------------------------------------------------------
    // Instantiate snoop handler (combinational)
    // -------------------------------------------------------------------------
    snoop_handler u_snoop_handler (
        .snoop_type(snoop_type),
        .snoop_addr(snoop_addr),
        .tag_match(snoop_tag_match),
        .line_valid(snoop_line_valid),
        .curr_state(curr_state),
        .new_state(snoop_new_state),
        .provide_data(snoop_provide_data),
        .must_invalidate(snoop_must_invalidate)
    );

    // -------------------------------------------------------------------------
    // TODO: Control logic
    // -------------------------------------------------------------------------
    // TODO: Tag lookup and hit/miss detection.
    // TODO: Determine curr_state from matching way (tag/valid).
    // TODO: Set local_read_hit/miss, local_write_hit/miss signals.
    // TODO: On hit, read data, update LRU, respond to core.
    // TODO: On miss, issue bus request, allocate line, update tag/data/LRU.
    // TODO: Use moesi_fsm next_state to update tag array state.
    // TODO: Implement write mask for partial writes.

    // TODO: Snoop handling
    // TODO: Perform snoop tag lookup and set snoop_tag_match/line_valid.
    // TODO: Update state using snoop_new_state; if must_invalidate, clear valid.
    // TODO: If snoop_provide_data, place data on bus (not shown).

    // Placeholder defaults to avoid latches in skeleton
    always_comb begin
        core_resp_valid = 1'b0;
        core_rdata      = '0;

        bus_req_valid   = 1'b0;
        bus_req_type    = 2'b00;
        bus_req_addr    = core_addr;

        // Default tag write controls
        tag_write_en    = 1'b0;
        tag_write_set   = req_set;
        tag_write_way   = '0;
        tag_write_tag   = req_tag;
        tag_write_valid = 1'b0;
        tag_write_state = 3'b000;
        tag_write_lru   = 2'b00;

        // Default data array controls
        data_read_set   = req_set;
        data_read_way   = '0;
        data_write_set  = req_set;
        data_write_way  = '0;
        data_write_data = core_wdata;
        data_write_mask = '0;

        // Default LRU controls
        lru_access_set   = req_set;
        lru_access_way   = '0;
        lru_access_valid = 1'b0;

        // Default local event flags
        local_read_hit   = 1'b0;
        local_read_miss  = 1'b0;
        local_write_hit  = 1'b0;
        local_write_miss = 1'b0;

        // Default snoop inputs
        snoop_tag_match  = 1'b0;
        snoop_line_valid = 1'b0;

        // Default curr_state (will be set from tag match)
        curr_state       = 3'b000;
    end

endmodule
