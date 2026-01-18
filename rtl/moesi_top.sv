// moesi_top.sv
// Top-level MOESI system with 4 cache controllers, coherency bus, and shared memory.
// Includes simple CPU stubs that generate random read/write requests for sanity sims.

module moesi_top #(
    parameter int NUM_CORES   = 4,
    parameter int SETS        = 128,
    parameter int WAYS        = 4,
    parameter int LINE_BYTES  = 64,
    parameter int DATA_WIDTH  = LINE_BYTES * 8,
    parameter int ADDR_WIDTH  = 64
) (
    input  logic clk,
    input  logic rst_n
);

    // Core request/response signals
    logic [NUM_CORES-1:0]              core_req_valid;
    logic [NUM_CORES-1:0][1:0]         core_req_type;   // 2'b01=READ, 2'b10=WRITE
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] core_addr;
    logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_wdata;
    logic [NUM_CORES-1:0]              core_resp_valid;
    logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_rdata;

    // Bus request arrays from caches
    logic [NUM_CORES-1:0]              bus_req_valid;
    logic [NUM_CORES-1:0][1:0]         bus_req_type;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] bus_req_addr;
    logic [NUM_CORES-1:0]              bus_req_ready;
    logic [NUM_CORES-1:0]              bus_resp_valid;
    logic [DATA_WIDTH-1:0]             bus_resp_data;

    // Coherency bus broadcast
    logic                              bus_valid;
    logic [ADDR_WIDTH-1:0]             bus_addr;
    logic [1:0]                        bus_type;
    logic [1:0]                        granted_core_id;

    // Snoop response vector (from caches)
    logic [NUM_CORES-1:0]              snoop_resp;

    // Memory interface (placeholder hookup)
    logic                              mem_req_valid;
    logic                              mem_req_write;
    logic [ADDR_WIDTH-1:0]             mem_req_addr;
    logic [DATA_WIDTH-1:0]             mem_req_wdata;
    logic                              mem_req_ready;
    logic                              mem_resp_valid;
    logic [DATA_WIDTH-1:0]             mem_resp_rdata;

    // -------------------------------------------------------------------------
    // Coherency bus
    // -------------------------------------------------------------------------
    coherency_bus #(
        .NUM_CORES(NUM_CORES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bus (
        .clk(clk),
        .rst_n(rst_n),
        .core_req_valid(bus_req_valid),
        .core_req_type(bus_req_type),
        .core_req_addr(bus_req_addr),
        .bus_valid(bus_valid),
        .bus_addr(bus_addr),
        .bus_type(bus_type),
        .granted_core_id(granted_core_id),
        .snoop_resp(snoop_resp)
    );

    // snoop_resp driven by cache controllers

    // -------------------------------------------------------------------------
    // Shared memory (placeholder: not yet connected to bus)
    // -------------------------------------------------------------------------
    shared_memory #(
        .MEM_BYTES(8 * 1024 * 1024),
        .LINE_BYTES(LINE_BYTES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_LATENCY(4)
    ) u_mem (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(mem_req_valid),
        .req_write(mem_req_write),
        .req_addr(mem_req_addr),
        .req_wdata(mem_req_wdata),
        .req_ready(mem_req_ready),
        .resp_valid(mem_resp_valid),
        .resp_rdata(mem_resp_rdata)
    );

    // Connect coherency bus to shared memory (read-only for now)
    assign mem_req_valid = bus_valid;
    assign mem_req_write = 1'b0;
    assign mem_req_addr  = bus_addr;
    assign mem_req_wdata = '0;

    // Route memory response to the granted core
    assign bus_resp_data = mem_resp_rdata;

    // -------------------------------------------------------------------------
    // Cache controllers
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : gen_cores
            cache_controller #(
                .SETS(SETS),
                .WAYS(WAYS),
                .LINE_BYTES(LINE_BYTES),
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_cache_controller (
                .clk(clk),
                .rst_n(rst_n),
                // Core side
                .core_req_valid(core_req_valid[i]),
                .core_req_type(core_req_type[i]),
                .core_addr(core_addr[i]),
                .core_wdata(core_wdata[i]),
                .core_resp_valid(core_resp_valid[i]),
                .core_rdata(core_rdata[i]),
                // Bus side
                .bus_req_valid(bus_req_valid[i]),
                .bus_req_type(bus_req_type[i]),
                .bus_req_addr(bus_req_addr[i]),
                .bus_req_ready(bus_req_ready[i]),
                .bus_resp_valid(bus_resp_valid[i]),
                .bus_resp_data(bus_resp_data),
                // Snoop inputs
                .snoop_valid(bus_valid),
                .snoop_type(bus_type),
                .snoop_addr(bus_addr),
                .snoop_resp(snoop_resp[i])
            );

            // Simple ready: granted core sees ready during broadcast
            assign bus_req_ready[i]  = (bus_valid && (granted_core_id == i[1:0]));
            assign bus_resp_valid[i] = (mem_resp_valid && (granted_core_id == i[1:0]));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Simple CPU stubs (random traffic)
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    integer seed [0:NUM_CORES-1];
    integer j;
    initial begin
        for (j = 0; j < NUM_CORES; j = j + 1) begin
            seed[j] = 32'h1234_0000 + j;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_req_valid <= '0;
            core_req_type  <= '0;
            core_addr      <= '0;
            core_wdata     <= '0;
        end else begin
            for (j = 0; j < NUM_CORES; j = j + 1) begin
                // Issue a request with low probability each cycle
                core_req_valid[j] <= ($urandom(seed[j]) % 8 == 0);
                core_req_type[j]  <= ($urandom(seed[j]) % 2) ? 2'b01 : 2'b10;
                core_addr[j]      <= {48'h0, $urandom(seed[j])}; // simple 16-bit address space
                core_wdata[j]     <= {$urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]),
                                      $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]),
                                      $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]),
                                      $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j]), $urandom(seed[j])};
            end
        end
    end
`else
    always_comb begin
        core_req_valid = '0;
        core_req_type  = '0;
        core_addr      = '0;
        core_wdata     = '0;
    end
`endif

endmodule
