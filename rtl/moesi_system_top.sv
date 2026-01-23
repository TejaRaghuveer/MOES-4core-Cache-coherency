// moesi_system_top.sv
// Top-level wiring of 4 cache controllers to a shared coherency bus.

module moesi_system_top #(
    parameter int NUM_CORES  = 4,
    parameter int SETS       = 128,
    parameter int WAYS       = 4,
    parameter int LINE_BYTES = 64,
    parameter int DATA_WIDTH = LINE_BYTES * 8,
    parameter int ADDR_WIDTH = 64
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Core-side request/response interfaces (one per core)
    input  logic [NUM_CORES-1:0]          core_req_valid,
    input  logic [NUM_CORES-1:0][1:0]     core_req_type,  // 2'b01=READ, 2'b10=WRITE, 2'b11=UPGRADE?
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] core_addr,
    input  logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_wdata,
    output logic [NUM_CORES-1:0]          core_resp_valid,
    output logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_rdata
);

    // Bus request arrays from cores
    logic [NUM_CORES-1:0]          bus_req_valid;
    logic [NUM_CORES-1:0][1:0]     bus_req_type;
    logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] bus_req_addr;
    logic [NUM_CORES-1:0]          bus_req_ready;
    logic [NUM_CORES-1:0]          bus_resp_valid;
    logic [NUM_CORES-1:0][DATA_WIDTH-1:0] bus_resp_data;

    // Broadcast snoop signals from bus to all caches
    logic                          bus_valid;
    logic [ADDR_WIDTH-1:0]         bus_addr;
    logic [1:0]                    bus_type;
    logic [1:0]                    granted_core_id;

    // Snoop response vector (from caches)
    logic [NUM_CORES-1:0]          snoop_resp;

    // Shared memory interface
    logic                          mem_req_valid;
    logic                          mem_req_write;
    logic [ADDR_WIDTH-1:0]         mem_req_addr;
    logic [DATA_WIDTH-1:0]         mem_req_wdata;
    logic                          mem_req_ready;
    logic                          mem_resp_valid;
    logic [DATA_WIDTH-1:0]         mem_resp_rdata;

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

    // Shared memory (simple model)
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

    // Generate per-core cache controllers
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
                .bus_resp_data(bus_resp_data[i]),

                // Snoop inputs (broadcast)
                .snoop_valid(bus_valid),
                .snoop_type(bus_type),
                .snoop_addr(bus_addr),
                .snoop_resp(snoop_resp[i])
            );

            // Simple ready: granted core sees ready during broadcast
            assign bus_req_ready[i]  = (bus_valid && (granted_core_id == i[1:0]));
            assign bus_resp_valid[i] = (mem_resp_valid && (granted_core_id == i[1:0]));
            assign bus_resp_data[i]  = (mem_resp_valid && (granted_core_id == i[1:0]))
                                     ? mem_resp_rdata
                                     : '0;
        end
    endgenerate

endmodule
