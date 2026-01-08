# MOESI Cache Coherency System - SystemVerilog Architecture
## 4-Core Snoop-Based Implementation

---

## System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SHARED MEMORY CONTROLLER                        │
│                         (shared_memory.sv)                              │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                │ Memory Bus (addr, data, rw, valid, ready)
                                │
        ┌───────────────────────┴───────────────────────┐
        │                                               │
        │         COHERENCY BUS (coherency_bus.sv)     │
        │  ┌─────────────────────────────────────────┐ │
        │  │ BusRd, BusRdX, BusUpgr, SnoopResp       │ │
        │  │ Addr[31:0], Data[63:0], CacheID[1:0]    │ │
        │  │ SnoopValid, SnoopReady, DataValid       │ │
        │  └─────────────────────────────────────────┘ │
        │                                               │
        ├──────────┬──────────┬──────────┬─────────────┤
        │          │          │          │             │
┌───────▼──────┐ ┌─▼──────┐ ┌─▼──────┐ ┌─▼──────┐     │
│   CORE 0     │ │ CORE 1 │ │ CORE 2 │ │ CORE 3 │     │
│              │ │        │ │        │ │        │     │
│ ┌──────────┐ │ │┌──────┐│ │┌──────┐│ │┌──────┐│     │
│ │   CPU    │ │ ││ CPU  ││ ││ CPU  ││ ││ CPU  ││     │
│ └────┬─────┘ │ │└──┬───┘│ │└──┬───┘│ │└──┬───┘│     │
│      │       │ │   │    │ │   │    │ │   │    │     │
│ ┌────▼─────┐ │ │┌──▼───┐│ │┌──▼───┐│ │┌──▼───┐│     │
│ │L1 D-Cache│ │ ││L1 DC ││ ││L1 DC ││ ││L1 DC ││     │
│ │          │ │ ││      ││ ││      ││ ││      ││     │
│ │┌────────┐│ │ ││┌────┐││ ││┌────┐││ ││┌────┐││     │
│ ││Cache   ││ │ │││Cache││ │││Cache││ │││Cache││     │
│ ││Ctrl    ││ │ │││Ctrl ││ │││Ctrl ││ │││Ctrl ││     │
│ ││(moesi_ ││ │ │││(moesi││ │││(moesi││ │││(moesi│     │
│ ││_fsm)   ││ │ │││_fsm)││ │││_fsm)││ │││_fsm)││     │
│ │└────────┘│ │ ││└────┘││ ││└────┘││ ││└────┘││     │
│ │┌────────┐│ │ ││┌────┐││ ││┌────┐││ ││┌────┐││     │
│ ││Tag     ││ │ │││Tag ││ │││Tag ││ │││Tag ││     │
│ ││Array   ││ │ │││Array││ │││Array││ │││Array││     │
│ │└────────┘│ │ ││└────┘││ ││└────┘││ ││└────┘││     │
│ │┌────────┐│ │ ││┌────┐││ ││┌────┐││ ││┌────┐││     │
│ ││Data    ││ │ │││Data││ │││Data││ │││Data││     │
│ ││Array   ││ │ │││Array││ │││Array││ │││Array││     │
│ │└────────┘│ │ ││└────┘││ ││└────┘││ ││└────┘││     │
│ │┌────────┐│ │ ││┌────┐││ ││┌────┐││ ││┌────┐││     │
│ ││Snoop   ││ │ │││Snoop││ │││Snoop││ │││Snoop││     │
│ ││Handler ││ │ │││Hndlr││ │││Hndlr││ │││Hndlr││     │
│ │└────────┘│ │ ││└────┘││ ││└────┘││ ││└────┘││     │
│ └────┬─────┘ │ │└──┬───┘│ │└──┬───┘│ │└──┬───┘│     │
└──────┼───────┘ └───┼────┘ └───┼────┘ └───┼────┘     │
       │             │          │          │          │
       └─────────────┴──────────┴──────────┴──────────┘
                      │
                      │ Snoop Bus (all cores snoop all transactions)
                      │
```

---

## RTL Module Hierarchy

### Top-Level Module
- **moesi_top.sv**: System top-level, instantiates 4 cores, coherency bus, shared memory

### Per-Core Modules (4 instances)
- **cache_controller.sv**: Main cache controller, orchestrates all cache operations
- **moesi_fsm.sv**: MOESI state machine (M, O, E, S, I states)
- **cache_tag_array.sv**: Tag array with MOESI state bits
- **cache_data_array.sv**: Data array (4-way set-associative)
- **lru_4way.sv**: LRU replacement logic for 4-way set-associative cache
- **snoop_handler.sv**: Handles snoop requests from bus

### Shared Modules
- **coherency_bus.sv**: Bus arbiter and transaction router
- **shared_memory.sv**: Main memory controller

---

## Module Signal Interfaces

### 1. cache_controller.sv

```systemverilog
module cache_controller #(
    parameter CORE_ID = 0,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter CACHE_SIZE = 32*1024,  // 32KB
    parameter LINE_SIZE = 64,        // 64 bytes
    parameter ASSOC = 4               // 4-way
)(
    // Clock and Reset
    input  logic clk,
    input  logic rst_n,
    
    // CPU Interface
    input  logic                    cpu_req,
    input  logic                    cpu_wr,
    input  logic [ADDR_WIDTH-1:0]   cpu_addr,
    input  logic [DATA_WIDTH-1:0]   cpu_wdata,
    output logic                    cpu_ready,
    output logic [DATA_WIDTH-1:0]   cpu_rdata,
    
    // Tag Array Interface
    output logic                    tag_req,
    output logic                    tag_wr,
    output logic [ADDR_WIDTH-1:0]   tag_addr,
    output logic [2:0]              tag_state_out,  // MOESI state
    input  logic                    tag_hit,
    input  logic [2:0]              tag_state_in,   // Current MOESI state
    input  logic [ASSOC-1:0]        tag_match_way,
    
    // Data Array Interface
    output logic                    data_req,
    output logic                    data_wr,
    output logic [ADDR_WIDTH-1:0]   data_addr,
    output logic [DATA_WIDTH-1:0]   data_wdata,
    input  logic [DATA_WIDTH-1:0]  data_rdata,
    
    // LRU Interface
    output logic [ADDR_WIDTH-1:0]   lru_addr,
    output logic                    lru_update,
    input  logic [$clog2(ASSOC)-1:0] lru_way,
    
    // MOESI FSM Interface
    output logic [2:0]              fsm_state_req,  // Requested state
    output logic                    fsm_state_valid,
    input  logic [2:0]              fsm_state_curr, // Current state
    input  logic                    fsm_state_ack,
    
    // Snoop Handler Interface
    input  logic                    snoop_req,
    input  logic [ADDR_WIDTH-1:0]   snoop_addr,
    input  logic [1:0]              snoop_type,    // BusRd, BusRdX, BusUpgr
    output logic                    snoop_ack,
    output logic                    snoop_hit,
    output logic [2:0]              snoop_state,
    output logic                    snoop_data_valid,
    output logic [DATA_WIDTH-1:0]   snoop_data,
    
    // Coherency Bus Interface
    output logic                    bus_req,
    output logic [1:0]              bus_type,      // BusRd, BusRdX, BusUpgr
    output logic [ADDR_WIDTH-1:0]   bus_addr,
    output logic [DATA_WIDTH-1:0]   bus_wdata,
    input  logic                    bus_grant,
    input  logic                    bus_data_valid,
    input  logic [DATA_WIDTH-1:0]  bus_rdata,
    input  logic                    bus_snoop_resp, // Another cache responded
    
    // Memory Interface
    output logic                    mem_req,
    output logic                    mem_wr,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    output logic [DATA_WIDTH-1:0]  mem_wdata,
    input  logic                    mem_ready,
    input  logic [DATA_WIDTH-1:0]  mem_rdata
);
```

### 2. moesi_fsm.sv

```systemverilog
module moesi_fsm (
    input  logic clk,
    input  logic rst_n,
    
    // State Request
    input  logic [2:0] state_req,      // Requested state (M=000, O=001, E=010, S=011, I=100)
    input  logic       state_req_valid,
    output logic       state_req_ack,
    
    // Current State
    output logic [2:0] state_curr,     // Current MOESI state
    
    // Transition Conditions
    input  logic       local_read_hit,
    input  logic       local_read_miss,
    input  logic       local_write_hit,
    input  logic       local_write_miss,
    input  logic       snoop_read,     // BusRd observed
    input  logic       snoop_write,    // BusRdX/BusUpgr observed
    
    // Write-back Control
    output logic       wb_required,    // Write-back needed on eviction
    output logic       wb_valid,       // Write-back data valid
    output logic [63:0] wb_data,
    output logic [31:0] wb_addr
);
```

### 3. cache_tag_array.sv

```systemverilog
module cache_tag_array #(
    parameter ADDR_WIDTH = 32,
    parameter ASSOC = 4,
    parameter INDEX_WIDTH = 10,  // For 32KB cache, 4-way, 64B line
    parameter TAG_WIDTH = 20     // 32 - INDEX_WIDTH - 6 (offset)
)(
    input  logic clk,
    input  logic rst_n,
    
    // Request Interface
    input  logic                    req,
    input  logic                    wr,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [2:0]              state_in,      // MOESI state to write
    input  logic [ASSOC-1:0]        way_sel,
    
    // Response Interface
    output logic                    hit,
    output logic [ASSOC-1:0]        match_way,     // One-hot match
    output logic [2:0]              state_out,     // MOESI state of matched way
    output logic [TAG_WIDTH-1:0]    tag_out
);
```

### 4. cache_data_array.sv

```systemverilog
module cache_data_array #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ASSOC = 4,
    parameter LINE_SIZE = 64        // 64 bytes per line
)(
    input  logic clk,
    input  logic rst_n,
    
    // Request Interface
    input  logic                    req,
    input  logic                    wr,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [ASSOC-1:0]        way_sel,
    
    // Response Interface
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic                    ready
);
```

### 5. snoop_handler.sv

```systemverilog
module snoop_handler #(
    parameter CORE_ID = 0,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)(
    input  logic clk,
    input  logic rst_n,
    
    // Bus Snoop Interface
    input  logic                    bus_snoop_valid,
    input  logic [ADDR_WIDTH-1:0]   bus_snoop_addr,
    input  logic [1:0]              bus_snoop_type,  // BusRd, BusRdX, BusUpgr
    input  logic [1:0]              bus_snoop_core,   // Requesting core ID
    
    // Tag Array Lookup
    output logic                    tag_lookup_req,
    output logic [ADDR_WIDTH-1:0]  tag_lookup_addr,
    input  logic                    tag_lookup_hit,
    input  logic [2:0]              tag_lookup_state,
    
    // Data Array Read
    output logic                    data_read_req,
    output logic [ADDR_WIDTH-1:0]  data_read_addr,
    input  logic [DATA_WIDTH-1:0]  data_read_data,
    
    // Snoop Response
    output logic                    snoop_resp_valid,
    output logic [DATA_WIDTH-1:0]  snoop_resp_data,
    output logic                    snoop_resp_hit,
    output logic [2:0]              snoop_resp_state,
    
    // State Update to Cache Controller
    output logic                    state_update_req,
    output logic [2:0]              state_update_new_state
);
```

### 6. coherency_bus.sv

```systemverilog
module coherency_bus #(
    parameter NUM_CORES = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)(
    input  logic clk,
    input  logic rst_n,
    
    // Core Interfaces (4 cores)
    input  logic [NUM_CORES-1:0]                core_req,
    input  logic [NUM_CORES-1:0][1:0]          core_type,      // BusRd, BusRdX, BusUpgr
    input  logic [NUM_CORES-1:0][ADDR_WIDTH-1:0] core_addr,
    input  logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_wdata,
    output logic [NUM_CORES-1:0]               core_grant,
    output logic [NUM_CORES-1:0]               core_data_valid,
    output logic [NUM_CORES-1:0][DATA_WIDTH-1:0] core_rdata,
    output logic [NUM_CORES-1:0]               core_snoop_resp, // Another cache responded
    
    // Snoop Broadcast (all cores see all transactions)
    output logic                                snoop_valid,
    output logic [ADDR_WIDTH-1:0]               snoop_addr,
    output logic [1:0]                          snoop_type,
    output logic [1:0]                          snoop_core_id,
    
    // Snoop Response (from snooping caches)
    input  logic [NUM_CORES-1:0]                snoop_resp_valid,
    input  logic [NUM_CORES-1:0][DATA_WIDTH-1:0] snoop_resp_data,
    input  logic [NUM_CORES-1:0]                snoop_resp_hit,
    
    // Memory Interface
    output logic                                mem_req,
    output logic                                mem_wr,
    output logic [ADDR_WIDTH-1:0]               mem_addr,
    output logic [DATA_WIDTH-1:0]               mem_wdata,
    input  logic                                mem_ready,
    input  logic [DATA_WIDTH-1:0]               mem_rdata
);
```

### 7. lru_4way.sv

```systemverilog
module lru_4way #(
    parameter INDEX_WIDTH = 10
)(
    input  logic clk,
    input  logic rst_n,
    
    // Lookup/Update Interface
    input  logic [INDEX_WIDTH-1:0]  index,
    input  logic                     update,
    input  logic [1:0]               accessed_way,  // Which way was accessed
    
    // LRU Way Output
    output logic [1:0]               lru_way       // Least recently used way
);
```

### 8. shared_memory.sv

```systemverilog
module shared_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter MEM_SIZE = 1024*1024*1024  // 1GB
)(
    input  logic clk,
    input  logic rst_n,
    
    // Memory Interface
    input  logic                    mem_req,
    input  logic                    mem_wr,
    input  logic [ADDR_WIDTH-1:0]  mem_addr,
    input  logic [DATA_WIDTH-1:0]   mem_wdata,
    output logic                    mem_ready,
    output logic [DATA_WIDTH-1:0]   mem_rdata
);
```

---

## Cycle-by-Cycle Operation: Read Miss Path

### Scenario: Core 0 read miss, line not in any cache

**Initial State:**
- Core 0: Line X in I state
- All other cores: Line X in I state
- CPU requests read from address 0x1000

**Cycle-by-Cycle:**

| Cycle | Core 0 Cache Controller | Core 0 MOESI FSM | Coherency Bus | Memory | Other Cores |
|-------|-------------------------|------------------|---------------|--------|-------------|
| **C0** | CPU req detected, tag lookup | State: I | Idle | Idle | Idle |
| **C1** | Tag miss detected, issue BusRd | State: I | Arbiter: grant Core 0 | Idle | Snoop BusRd |
| **C2** | BusRd on bus, wait for response | State: I | Broadcast BusRd(0x1000) | Receive req | All cores snoop |
| **C3** | Wait for snoop responses | State: I | Collect snoop responses (all miss) | Process req | All respond: miss |
| **C4** | No cache response, wait for memory | State: I | Route to memory | Read data | Idle |
| **C5** | Receive memory data | State: I→E | Memory data on bus | Data ready | Idle |
| **C6** | Write tag (E state), write data array | State: E | Transaction complete | Idle | Idle |
| **C7** | CPU ready, return data | State: E | Idle | Idle | Idle |

**Detailed Signal Flow:**

**Cycle 0:**
- `cpu_req = 1`, `cpu_addr = 0x1000`, `cpu_wr = 0`
- Cache controller: `tag_req = 1`, `tag_addr = 0x1000`
- MOESI FSM: `state_curr = 3'b100` (I)

**Cycle 1:**
- Tag array: `tag_hit = 0` (miss)
- Cache controller: `bus_req = 1`, `bus_type = 2'b00` (BusRd), `bus_addr = 0x1000`
- Coherency bus: `snoop_valid = 1`, `snoop_addr = 0x1000`, `snoop_type = 2'b00`, `snoop_core_id = 2'b00`

**Cycle 2:**
- Coherency bus: `core_grant[0] = 1`
- All cores: `snoop_handler` receives BusRd
- Core 1/2/3: Tag lookup, all miss (`snoop_resp_hit = 0`)

**Cycle 3:**
- Coherency bus: Collects snoop responses, all `snoop_resp_hit = 0`
- Coherency bus: `core_snoop_resp[0] = 0` (no cache responded)
- Coherency bus: `mem_req = 1`, `mem_addr = 0x1000`

**Cycle 4:**
- Memory: Processing read request
- Cache controller: Waiting for data

**Cycle 5:**
- Memory: `mem_ready = 1`, `mem_rdata = [data]`
- Coherency bus: `core_data_valid[0] = 1`, `core_rdata[0] = [data]`
- Cache controller: Receives data, prepares to write cache

**Cycle 6:**
- Cache controller: `tag_wr = 1`, `tag_state_out = 3'b010` (E), `tag_addr = 0x1000`
- Cache controller: `data_wr = 1`, `data_addr = 0x1000`, `data_wdata = [data]`
- MOESI FSM: `state_req = 3'b010` (E), `state_req_valid = 1`
- MOESI FSM: `state_curr = 3'b010` (E)

**Cycle 7:**
- Cache controller: `cpu_ready = 1`, `cpu_rdata = [data]`
- CPU: Accepts data, transaction complete

---

## Cycle-by-Cycle Operation: Write Miss Path

### Scenario: Core 0 write miss, Core 1 has line in O state

**Initial State:**
- Core 0: Line X in I state
- Core 1: Line X in O state (with data)
- Core 2/3: Line X in I state
- CPU requests write to address 0x2000

**Cycle-by-Cycle:**

| Cycle | Core 0 Cache Controller | Core 0 MOESI FSM | Core 1 Snoop Handler | Coherency Bus | Memory |
|-------|-------------------------|------------------|---------------------|---------------|--------|
| **C0** | CPU req detected, tag lookup | State: I | Idle | Idle | Idle |
| **C1** | Tag miss detected, issue BusRdX | State: I | Idle | Arbiter: grant Core 0 | Idle |
| **C2** | BusRdX on bus | State: I | Snoop BusRdX detected | Broadcast BusRdX | Idle |
| **C3** | Wait for snoop responses | State: I | Tag lookup: hit, state=O | Collect responses | Idle |
| **C4** | Wait for data | State: I | Read data array | Core 1: snoop_resp_valid=1 | Idle |
| **C5** | Receive data from Core 1 | State: I | Supply data on bus | Route data to Core 0 | Idle |
| **C6** | Write tag (M state), write data | State: I→M | State: O→I | Transaction complete | Idle |
| **C7** | Write CPU data, CPU ready | State: M | State: I | Idle | Idle |

**Detailed Signal Flow:**

**Cycle 0:**
- `cpu_req = 1`, `cpu_addr = 0x2000`, `cpu_wr = 1`, `cpu_wdata = [write_data]`
- Cache controller: `tag_req = 1`, `tag_addr = 0x2000`
- MOESI FSM: `state_curr = 3'b100` (I)

**Cycle 1:**
- Tag array: `tag_hit = 0` (miss)
- Cache controller: `bus_req = 1`, `bus_type = 2'b01` (BusRdX), `bus_addr = 0x2000`
- Coherency bus: `snoop_valid = 1`, `snoop_addr = 0x2000`, `snoop_type = 2'b01`, `snoop_core_id = 2'b00`

**Cycle 2:**
- Coherency bus: `core_grant[0] = 1`
- Core 1 snoop handler: `bus_snoop_valid = 1`, `bus_snoop_type = 2'b01` (BusRdX)
- Core 1: `tag_lookup_req = 1`, `tag_lookup_addr = 0x2000`

**Cycle 3:**
- Core 1 tag array: `tag_lookup_hit = 1`, `tag_lookup_state = 3'b001` (O)
- Core 1 snoop handler: `data_read_req = 1`, `data_read_addr = 0x2000`
- Core 1 MOESI FSM: `snoop_write = 1`, prepares state transition O→I

**Cycle 4:**
- Core 1 data array: `data_read_data = [cached_data]`
- Core 1 snoop handler: `snoop_resp_valid = 1`, `snoop_resp_data = [cached_data]`, `snoop_resp_hit = 1`
- Coherency bus: `snoop_resp_valid[1] = 1`, routes data to Core 0

**Cycle 5:**
- Coherency bus: `core_data_valid[0] = 1`, `core_rdata[0] = [cached_data]`
- Coherency bus: `core_snoop_resp[0] = 1` (cache responded)
- Cache controller: Receives data from Core 1

**Cycle 6:**
- Cache controller: `tag_wr = 1`, `tag_state_out = 3'b000` (M), `tag_addr = 0x2000`
- Cache controller: `data_wr = 1`, `data_addr = 0x2000`, `data_wdata = [cached_data]` (merge with write data)
- Core 1 MOESI FSM: `state_req = 3'b100` (I), `state_req_valid = 1`
- Core 1 MOESI FSM: `state_curr = 3'b100` (I)
- Core 0 MOESI FSM: `state_req = 3'b000` (M), `state_req_valid = 1`
- Core 0 MOESI FSM: `state_curr = 3'b000` (M)

**Cycle 7:**
- Cache controller: Write CPU data to cache line (byte-level write enable)
- Cache controller: `cpu_ready = 1`
- CPU: Transaction complete

**Note:** If Core 2 or Core 3 had line in S state, they would also receive BusRdX snoop and transition S→I in Cycle 3-4.

---

## Additional Implementation Notes

### Bus Transaction Types Encoding
```systemverilog
localparam BUS_RD    = 2'b00;  // Bus Read (shared)
localparam BUS_RDX   = 2'b01;  // Bus Read Exclusive (for write)
localparam BUS_UPGR  = 2'b10;  // Bus Upgrade (S→M transition)
```

### MOESI State Encoding
```systemverilog
localparam STATE_M = 3'b000;  // Modified
localparam STATE_O = 3'b001;  // Owned
localparam STATE_E = 3'b010;  // Exclusive
localparam STATE_S = 3'b011;  // Shared
localparam STATE_I = 3'b100;  // Invalid
```

### Critical Timing Considerations

1. **Snoop Response Timing**: Snoop handlers must respond within 2-3 cycles to avoid bus stall
2. **Tag Lookup Pipeline**: Tag lookup should be pipelined for better performance
3. **Write-Back Buffer**: O and M state evictions require write-back; use buffer to avoid stalling
4. **Bus Arbitration**: Round-robin or priority-based arbitration to prevent starvation
5. **Memory Latency**: Account for memory access latency (typically 10-20 cycles)

### Verification Checklist

- [ ] All state transitions from MOESI table implemented
- [ ] Snoop response timing verified (within spec)
- [ ] Write-back on M/O eviction verified
- [ ] Bus arbitration fairness verified
- [ ] Race conditions handled (concurrent snoops)
- [ ] Deadlock prevention (no circular dependencies)
- [ ] Data correctness (no corruption, no stale data)

---

## Module Instantiation Template

```systemverilog
module moesi_top (
    input  logic clk,
    input  logic rst_n,
    // CPU interfaces (4 cores)
    input  logic [3:0] cpu_req,
    // ... other CPU signals
);

// Coherency Bus
coherency_bus #(
    .NUM_CORES(4),
    .ADDR_WIDTH(32),
    .DATA_WIDTH(64)
) u_coherency_bus (
    .clk(clk),
    .rst_n(rst_n),
    // ... connect to cores and memory
);

// Shared Memory
shared_memory u_memory (
    .clk(clk),
    .rst_n(rst_n),
    // ... connect to bus
);

// Core 0
cache_controller #(.CORE_ID(0)) u_core0_cache_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    // ... connect CPU, tag, data, snoop, bus, memory
);

// ... repeat for Core 1, 2, 3

endmodule
```

---

This architecture provides a complete foundation for implementing a 4-core MOESI cache coherency system in SystemVerilog. Each module has well-defined interfaces and responsibilities, making the RTL implementation straightforward.
