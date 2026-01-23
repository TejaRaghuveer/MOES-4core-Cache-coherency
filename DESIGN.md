# DESIGN.md
# 4-Core MOESI Cache Coherency System

---

## Overview
- 4-core snoop-based cache coherency system in SystemVerilog.
- Private L1 data caches per core, shared coherency bus, shared memory.
- Implements MOESI protocol with UVM verification infrastructure.

---

## System Architecture
**Block Diagram (conceptual):**
```
  Core0  Core1  Core2  Core3
    |      |      |      |
  L1D0   L1D1   L1D2   L1D3
    \      |      |      /
     \     |      |     /
      +----+------+----+---- Coherency Bus
                     |
                 Shared Memory
```

**Notes:**
- Snoop-based bus: all caches observe all transactions.
- Single shared memory model with fixed read latency.
- Per-core cache controllers manage MOESI state transitions.

---

## MOESI Protocol Summary
- **States**: Modified (M), Owned (O), Exclusive (E), Shared (S), Invalid (I).
- **Key behaviors:**
  - M/O supply data on snoop read; M→O on read snoop.
  - E supplies data on snoop read; E→S.
  - S does not supply data on snoop read.
  - BusRdX/BusUpgr invalidates other copies.
- **Optimization**: Owned state avoids immediate memory write-back on shared reads.

---

## Cache Controller Design
**Submodules:**
- `cache_tag_array`: dual-port read (core + snoop), single write.
- `cache_data_array`: line storage, byte-mask writes.
- `moesi_fsm`: combinational next-state logic.
- `snoop_handler`: snoop response/invalidations.
- `lru_4way`: replacement policy.
- `perf_counters`: optional metrics collection.

**Interfaces:**
- **Core**: `core_req_valid`, `core_req_type`, `core_addr`, `core_wdata`, `core_resp_valid`, `core_rdata`.
- **Bus**: `bus_req_valid`, `bus_req_type`, `bus_req_addr`, `bus_req_ready`, `bus_resp_valid`, `bus_resp_data`.
- **Snoop**: `snoop_valid`, `snoop_type`, `snoop_addr`, `snoop_resp`.

**Key behaviors:**
- Read hit: return data (1-cycle delayed).
- Read miss: issue BusRd, fill line on response.
- Write hit: upgrade to M as needed.
- Write miss: issue BusRdX, allocate line in M.
- Snoop: update state and optionally supply data.

---

## Coherency Bus Design
- Round-robin arbitration among 4 cores.
- FSM: IDLE → BROADCAST → COMPLETE.
- Broadcasts `bus_valid`, `bus_addr`, `bus_type`.
- Collects snoop responses (bit-vector placeholder).

---

## Shared Memory Model
- 8MB memory, 64-byte line interface.
- Fixed read latency (default: 4 cycles).
- Single outstanding read (1-entry queue).
- Writes complete immediately.

---

## Performance Counters
- 64-bit saturating counters:
  - total_reads, read_hits, read_misses
  - total_writes, write_hits, write_misses
  - coherency_invalidates
  - data_supplied, data_from_mem
- CSV + text parsing supported by `parse_metrics.py`.

---

## Verification Strategy
- UVM-based driver, monitor, scoreboard, and coverage.
- Targeted sequences to hit missing bins:
  - `owner_transitions_seq`
  - `shared_read_write_seq`
  - `exclusive_read_seq`
- Scoreboard enforces invariants:
  - At most one M per address.
  - M implies all others I.
  - Read data matches last write.

---

## Results (Placeholders)
- **Cache hit rate**: XX %
- **Cache miss rate**: XX %
- **Coherency miss rate**: XX %
- **Functional coverage**: XX %
- **Code coverage**: XX %

