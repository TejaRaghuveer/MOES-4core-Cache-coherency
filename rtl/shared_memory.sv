// shared_memory.sv
// Simple 8MB memory with 64-byte line interface and fixed read latency.
// Single-port, serialized requests. One outstanding read in a small queue.

module shared_memory #(
    parameter int MEM_BYTES  = 8 * 1024 * 1024,
    parameter int LINE_BYTES = 64,
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = LINE_BYTES * 8,
    parameter int READ_LATENCY = 4
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Request interface
    input  logic                  req_valid,
    input  logic                  req_write,   // 1=write, 0=read
    input  logic [ADDR_WIDTH-1:0] req_addr,
    input  logic [DATA_WIDTH-1:0] req_wdata,
    output logic                  req_ready,

    // Response interface (read only)
    output logic                  resp_valid,
    output logic [DATA_WIDTH-1:0] resp_rdata
);

    localparam int MEM_LINES  = MEM_BYTES / LINE_BYTES;
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS  = $clog2(MEM_LINES);

    // Memory as bytes: mem[line][byte]
    logic [7:0] mem [0:MEM_LINES-1][0:LINE_BYTES-1];

    // Small pending read queue (single entry)
    logic                     pending_valid;
    logic [INDEX_BITS-1:0]     pending_line;
    logic [$clog2(READ_LATENCY+1)-1:0] pending_cnt;
    localparam int READ_LAT_INIT = (READ_LATENCY > 0) ? (READ_LATENCY - 1) : 0;

    // Ready when no pending read (single outstanding)
    assign req_ready = !pending_valid;

    // Helper: assemble a 64-byte line from memory bytes
    function automatic logic [DATA_WIDTH-1:0] assemble_line(
        input logic [INDEX_BITS-1:0] line_idx
    );
        logic [DATA_WIDTH-1:0] line_data;
        int i;
        begin
            line_data = '0;
            for (i = 0; i < LINE_BYTES; i = i + 1) begin
                line_data[i*8 +: 8] = mem[line_idx][i];
            end
            return line_data;
        end
    endfunction

    // Write data into memory bytes
    task automatic write_line(
        input logic [INDEX_BITS-1:0] line_idx,
        input logic [DATA_WIDTH-1:0] line_data
    );
        int i;
        begin
            for (i = 0; i < LINE_BYTES; i = i + 1) begin
                mem[line_idx][i] = line_data[i*8 +: 8];
            end
        end
    endtask

    // Sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_valid <= 1'b0;
            pending_line  <= '0;
            pending_cnt   <= '0;
            resp_valid    <= 1'b0;
            resp_rdata    <= '0;
        end else begin
            resp_valid <= 1'b0; // default, pulse when read completes

            // Accept a new request if ready
            if (req_valid && req_ready) begin
                if (req_write) begin
                    // Write completes immediately (single-port serialized)
                    write_line(req_addr[OFFSET_BITS +: INDEX_BITS], req_wdata);
                end else begin
                    // Queue read with fixed latency
                    pending_valid <= 1'b1;
                    pending_line  <= req_addr[OFFSET_BITS +: INDEX_BITS];
                    pending_cnt   <= READ_LAT_INIT[$clog2(READ_LATENCY+1)-1:0];
                end
            end

            // Handle pending read
            if (pending_valid) begin
                if (pending_cnt == 0) begin
                    resp_valid  <= 1'b1;
                    resp_rdata  <= assemble_line(pending_line);
                    pending_valid <= 1'b0;
                end else begin
                    pending_cnt <= pending_cnt - 1'b1;
                end
            end
        end
    end

endmodule
