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
    input  logic [1:0]            core_req_type,   // 2'b01=READ, 2'b10=WRITE, 2'b11=UPGRADE?
    input  logic [ADDR_WIDTH-1:0] core_addr,
    input  logic [DATA_WIDTH-1:0] core_wdata,
    output logic                  core_resp_valid,
    output logic [DATA_WIDTH-1:0] core_rdata,

    // Bus side
    output logic                  bus_req_valid,
    output logic [1:0]            bus_req_type,     // BusRd/BusRdX/BusUpgr
    output logic [ADDR_WIDTH-1:0] bus_req_addr,
    input  logic                  bus_req_ready,

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

    localparam logic [1:0] BUS_READ  = 2'b01;
    localparam logic [1:0] BUS_WRITE = 2'b10; // BusRdX
    localparam logic [1:0] BUS_UPGR  = 2'b11; // BusUpgr

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
    // Read path FSM (IDLE, WAIT_MEM)
    // -------------------------------------------------------------------------
    typedef enum logic {IDLE, WAIT_MEM} rd_state_t;
    rd_state_t rd_state, rd_state_n;
    logic [ADDR_WIDTH-1:0] pending_addr;
    logic [INDEX_BITS-1:0] pending_set;
    logic [TAG_WIDTH-1:0]  pending_tag;

    // -------------------------------------------------------------------------
    // Write path FSM (IDLE, WAIT_BUS, UPDATE_LINE)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_WAIT_BUS, W_UPDATE_LINE} wr_state_t;
    wr_state_t wr_state, wr_state_n;
    logic [ADDR_WIDTH-1:0] pending_waddr;
    logic [INDEX_BITS-1:0] pending_wset;
    logic [TAG_WIDTH-1:0]  pending_wtag;
    logic [$clog2(WAYS)-1:0] pending_wway;

    // Tag match / hit signals
    logic                  rd_hit;
    logic [$clog2(WAYS)-1:0] rd_hit_way;
    logic [2:0]            rd_hit_state;
    integer                w;

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

    // Hit detection for current request set
    always_comb begin
        rd_hit       = 1'b0;
        rd_hit_way   = '0;
        rd_hit_state = 3'b000;
        for (w = 0; w < WAYS; w = w + 1) begin
            if (tag_read_valids[w] && (tag_read_tags[w] == req_tag)) begin
                if (!rd_hit) begin
                    rd_hit       = 1'b1;
                    rd_hit_way   = w[$clog2(WAYS)-1:0];
                    rd_hit_state = tag_read_states[w];
                end
            end
        end
    end

    // Read FSM sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state     <= IDLE;
            pending_addr <= '0;
            pending_set  <= '0;
            pending_tag  <= '0;
        end else begin
            rd_state <= rd_state_n;
            if (rd_state == IDLE && core_req_valid && core_req_type == BUS_READ && !rd_hit) begin
                // Latch pending miss request
                pending_addr <= core_addr;
                pending_set  <= req_set;
                pending_tag  <= req_tag;
            end
        end
    end

    // Write FSM sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= W_IDLE;
            pending_waddr <= '0;
            pending_wset  <= '0;
            pending_wtag  <= '0;
            pending_wway  <= '0;
        end else begin
            wr_state <= wr_state_n;
            if (wr_state == W_IDLE && core_req_valid && core_req_type == BUS_WRITE) begin
                pending_waddr <= core_addr;
                pending_wset  <= req_set;
                pending_wtag  <= req_tag;
                pending_wway  <= rd_hit_way;
            end
        end
    end

    // Read FSM combinational next-state
    always_comb begin
        rd_state_n = rd_state;
        case (rd_state)
            IDLE: begin
                if (core_req_valid && core_req_type == BUS_READ && !rd_hit) begin
                    rd_state_n = WAIT_MEM; // miss pending
                end
            end
            WAIT_MEM: begin
                // TODO: replace bus_req_ready with memory response valid
                if (bus_req_ready) begin
                    rd_state_n = IDLE;
                end
            end
            default: rd_state_n = IDLE;
        endcase
    end

    // Write FSM combinational next-state
    always_comb begin
        wr_state_n = wr_state;
        case (wr_state)
            W_IDLE: begin
                if (core_req_valid && core_req_type == BUS_WRITE) begin
                    if (rd_hit) begin
                        // Hit: may need bus upgrade for S/O
                        if (rd_hit_state == 3'b101 || rd_hit_state == 3'b010) begin
                            wr_state_n = W_WAIT_BUS;
                        end else begin
                            wr_state_n = W_UPDATE_LINE;
                        end
                    end else begin
                        // Miss: request bus write (RdX)
                        wr_state_n = W_WAIT_BUS;
                    end
                end
            end
            W_WAIT_BUS: begin
                if (bus_req_ready) begin
                    wr_state_n = W_UPDATE_LINE;
                end
            end
            W_UPDATE_LINE: begin
                // One-cycle update placeholder
                wr_state_n = W_IDLE;
            end
            default: wr_state_n = W_IDLE;
        endcase
    end

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
        data_read_way   = rd_hit_way;
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
        curr_state       = rd_hit ? rd_hit_state : 3'b000;

        // ---------------------------------------------------------------------
        // Read path behavior (IDLE / WAIT_MEM)
        // ---------------------------------------------------------------------
        if (rd_state == IDLE) begin
            if (core_req_valid && core_req_type == BUS_READ) begin
                if (rd_hit) begin
                    // Read hit: return data immediately
                    local_read_hit = 1'b1;
                    core_resp_valid = 1'b1;
                    core_rdata = data_read_data;

                    // Update LRU on hit
                    lru_access_valid = 1'b1;
                    lru_access_way   = rd_hit_way;
                end else begin
                    // Read miss: issue bus read request
                    local_read_miss = 1'b1;
                    bus_req_valid   = 1'b1;
                    bus_req_type    = BUS_READ;
                    bus_req_addr    = core_addr;
                end
            end
        end else begin
            // WAIT_MEM: keep asserting bus request until response
            bus_req_valid = 1'b1;
            bus_req_type  = BUS_READ;
            bus_req_addr  = pending_addr;

            if (bus_req_ready) begin
                // TODO: replace with memory/bus response data
                core_resp_valid = 1'b1;
                core_rdata      = '0;
            end
        end

        // ---------------------------------------------------------------------
        // Write path behavior (IDLE / WAIT_BUS / UPDATE_LINE)
        // ---------------------------------------------------------------------
        if (wr_state == W_IDLE) begin
            if (core_req_valid && core_req_type == BUS_WRITE) begin
                if (rd_hit) begin
                    // Write hit: call MOESI FSM with local_write_hit
                    local_write_hit = 1'b1;
                    // If hit state is S/O, request bus upgrade
                    if (rd_hit_state == 3'b101 || rd_hit_state == 3'b010) begin
                        bus_req_valid = 1'b1;
                        bus_req_type  = BUS_UPGR;
                        bus_req_addr  = core_addr;
                    end
                end else begin
                    // Write miss: call MOESI FSM with local_write_miss, request BusRdX
                    local_write_miss = 1'b1;
                    bus_req_valid    = 1'b1;
                    bus_req_type     = BUS_WRITE;
                    bus_req_addr     = core_addr;
                end
            end
        end else if (wr_state == W_WAIT_BUS) begin
            // Keep asserting bus request during wait
            bus_req_valid = 1'b1;
            bus_req_type  = rd_hit ? BUS_UPGR : BUS_WRITE;
            bus_req_addr  = pending_waddr;
        end else begin
            // UPDATE_LINE: update data/tag/LRU for write hit/miss
            // TODO: merge write data for partial write; assume full-line write for now.
            data_write_set  = pending_wset;
            data_write_way  = pending_wway;
            data_write_data = core_wdata;
            data_write_mask = {LINE_BYTES{1'b1}};

            tag_write_en    = 1'b1;
            tag_write_set   = pending_wset;
            tag_write_way   = pending_wway;
            tag_write_tag   = pending_wtag;
            tag_write_valid = 1'b1;
            tag_write_state = next_state; // from MOESI FSM
            tag_write_lru   = 2'b00; // TODO: update via LRU logic

            lru_access_valid = 1'b1;
            lru_access_way   = pending_wway;

            core_resp_valid  = 1'b1;
        end
    end

endmodule
