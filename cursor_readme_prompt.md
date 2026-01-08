# MOESI Cache Coherency Project - Cursor AI Context

This document provides context and guidance for working with this MOESI cache coherency project using Cursor AI.

## Project Overview

This repository contains documentation and architecture specifications for a 4-core snoop-based MOESI cache coherency system implemented in SystemVerilog.

## Project Structure

```
MOESI cache coherency/
├── MOESI_Protocol_Notes.md              # Detailed MOESI protocol documentation
├── MOESI_SystemVerilog_Architecture.md  # SystemVerilog implementation architecture
├── System_Architecture.md                # Design specification document
└── cursor_readme_prompt.md               # This file
```

## Key Documents

### 1. MOESI_Protocol_Notes.md
- **Purpose:** Comprehensive MOESI protocol reference
- **Contents:**
  - State definitions (M, O, E, S, I)
  - MOESI vs MESI comparison
  - Complete state transition table (36 rows)
  - Three multi-core examples with step-by-step state evolution
  - Implementation considerations for RTL/verification engineers

### 2. MOESI_SystemVerilog_Architecture.md
- **Purpose:** Detailed SystemVerilog implementation guide
- **Contents:**
  - ASCII block diagram
  - Module hierarchy and interfaces
  - Signal definitions with widths
  - Cycle-by-cycle operation descriptions
  - Module instantiation templates

### 3. System_Architecture.md
- **Purpose:** Formal design specification document
- **Contents:**
  - System overview
  - Cache hierarchy specifications
  - Module responsibilities
  - Bus and signal definitions
  - Example transaction flows

## System Specifications

### Cache Configuration
- **Size:** 32 KB per core (L1 data cache)
- **Associativity:** 4-way set-associative
- **Line Size:** 64 bytes
- **Sets:** 128 sets per cache
- **Protocol:** MOESI (Modified, Owned, Exclusive, Shared, Invalid)

### Architecture
- **Cores:** 4 independent processor cores
- **Topology:** Snoop-based shared bus
- **Memory:** Unified shared memory controller
- **Bus:** Coherency bus with snoop broadcast

### RTL Modules
1. `moesi_top.sv` - System top-level
2. `cache_controller.sv` - Main cache controller
3. `moesi_fsm.sv` - MOESI state machine
4. `cache_tag_array.sv` - Tag array with state bits
5. `cache_data_array.sv` - Data array (4-way)
6. `lru_4way.sv` - LRU replacement logic
7. `snoop_handler.sv` - Snoop request handler
8. `coherency_bus.sv` - Bus arbiter and router
9. `shared_memory.sv` - Memory controller

## Key Concepts for Cursor AI

When working on this project with Cursor AI, keep in mind:

### MOESI Protocol States
- **M (Modified):** Exclusive, dirty, must write-back on eviction
- **O (Owned):** Shared, dirty, owner supplies data on snoop
- **E (Exclusive):** Exclusive, clean, silent upgrade to M on write
- **S (Shared):** Shared, clean, multiple copies allowed
- **I (Invalid):** Not present or invalid

### Key MOESI Advantage
The O state allows sharing dirty data without writing back to memory, reducing memory traffic compared to MESI.

### Bus Transactions
- **BusRd:** Read request (shared)
- **BusRdX:** Read exclusive request (for write)
- **BusUpgr:** Upgrade request (S→M transition)

### State Transitions
Refer to the comprehensive state transition table in `MOESI_Protocol_Notes.md` for all valid transitions.

## Common Tasks

### Implementing RTL Modules
1. Start with `moesi_fsm.sv` - implement state machine first
2. Implement `cache_tag_array.sv` and `cache_data_array.sv`
3. Build `cache_controller.sv` to orchestrate operations
4. Implement `snoop_handler.sv` for snoop processing
5. Create `coherency_bus.sv` for bus arbitration
6. Integrate everything in `moesi_top.sv`

### Verification Focus Areas
- All state transitions from the transition table
- Snoop response timing (2-3 cycles)
- Write-back conditions (M/O states)
- Bus arbitration fairness
- Race condition handling
- Data correctness (no corruption)

### Design Considerations
- Tag lookup latency: 1 cycle
- Data array access: 1 cycle
- Snoop response: 2-3 cycles
- Memory access: 10-20 cycles (configurable)
- Write-back buffer needed for M/O evictions

## Usage with Cursor AI

When asking Cursor AI to help with this project:

1. **Reference specific documents:** "Based on System_Architecture.md, implement..."
2. **Specify module:** "Implement the moesi_fsm module according to..."
3. **State transitions:** "Verify all transitions from the state table in MOESI_Protocol_Notes.md"
4. **Signal interfaces:** "Use the signal definitions from System_Architecture.md section 4"

## Example Prompts for Cursor AI

- "Implement the moesi_fsm module with all state transitions from the state table"
- "Create the cache_controller module using the interfaces defined in System_Architecture.md"
- "Generate a testbench for the snoop_handler module based on the transaction flows"
- "Verify the write miss path matches the cycle-by-cycle description in MOESI_SystemVerilog_Architecture.md"

## Next Steps

1. Review all documentation files
2. Implement RTL modules starting with MOESI FSM
3. Create verification testbenches
4. Verify against state transition table
5. Test transaction flows (read miss, write miss, snoop operations)

---

**Note:** This project is focused on RTL design and verification. All modules should follow SystemVerilog best practices and be synthesizable.
