# MOESI Cache Coherency Protocol - Technical Notes
## For RTL/Verification Engineers

### Overview
MOESI is a cache coherency protocol that extends MESI with an **Owned (O)** state to optimize write-back operations and reduce memory traffic. The protocol maintains coherency across multiple cache levels in a multi-core system through state transitions triggered by local operations and snoop requests.

---

## State Definitions

### Modified (M)
- **Exclusive ownership**: Cache line is exclusively owned by this cache
- **Dirty**: Data differs from main memory (memory is stale)
- **Valid**: Data is valid and can be used
- **Snoop response**: Must supply data and invalidate (or transition to O if another cache needs it)
- **Write-back**: Required on eviction/replacement

**Characteristics:**
- Only one cache can have a line in M state at any time
- Memory does not have valid copy
- Cache must service snoop requests with data

### Owned (O)
- **Shared ownership**: Line may exist in other caches in S state
- **Dirty**: Data differs from main memory (memory is stale)
- **Valid**: Data is valid and can be used
- **Snoop response**: Must supply data but does NOT invalidate (other caches remain in S)
- **Write-back**: Required on eviction/replacement

**Characteristics:**
- Only one cache can have a line in O state at any time
- Other caches may have the same line in S state
- Cache acts as "owner" and services snoop requests
- Memory does not have valid copy

### Exclusive (E)
- **Exclusive ownership**: Cache line is exclusively owned by this cache
- **Clean**: Data matches main memory
- **Valid**: Data is valid and can be used
- **Snoop response**: No snoop requests expected (exclusive ownership)
- **Write-back**: Not required on eviction (clean)

**Characteristics:**
- Only one cache can have a line in E state at any time
- Memory has valid copy
- Silent upgrade to M on local write (no bus transaction needed)

### Shared (S)
- **Shared ownership**: Line may exist in other caches
- **Clean**: Data matches main memory (or matches O state cache)
- **Valid**: Data is valid and can be used
- **Snoop response**: No response needed (not the owner)
- **Write-back**: Not required on eviction (clean)

**Characteristics:**
- Multiple caches can have the same line in S state
- If O state exists, S state caches match the O state cache, not memory
- Cannot silently upgrade to M (must invalidate other copies)

### Invalid (I)
- **No ownership**: Cache line is not present or not valid
- **Invalid**: Data cannot be used
- **Snoop response**: No response (no data to supply)

**Characteristics:**
- Default state for unused cache lines
- No coherency obligations

---

## Why MOESI vs MESI?

### Key Advantage: Reduced Memory Traffic

**MESI Problem:**
- When a cache in M state receives a snoop read, it must:
  1. Supply data to requester
  2. Invalidate itself (M → I)
  3. Write-back to memory (to make memory valid)
- This causes unnecessary memory write-back even when other caches are reading

**MOESI Solution:**
- When a cache in M state receives a snoop read, it can:
  1. Supply data to requester
  2. Transition to O state (M → O)
  3. Requester transitions to S state
  4. **No write-back to memory** (O state cache maintains dirty data)
- Memory write-back only occurs when O state cache evicts the line

### Benefits:
1. **Bandwidth savings**: Avoids write-back on read-for-ownership transitions
2. **Lower latency**: No memory write-back delay for shared reads
3. **Better scalability**: Reduces memory controller load
4. **Maintains correctness**: O state ensures single point of truth for dirty data

### Trade-off:
- More complex state machine (5 states vs 4)
- O state cache must service snoop requests (additional responsibility)

---

## Comprehensive MOESI State Transition Table

**System Assumptions:**
- 4-core snoop-based system on shared bus
- Bus transactions: BusRd (read), BusRdX (read for exclusive), BusUpgr (upgrade)
- All caches snoop all bus transactions

| Source State | Event | Target State | Effect on Other Caches | Data Source | Reason |
|--------------|-------|--------------|------------------------|-------------|--------|
| **M** | local_read_hit | M | None | Cache (local) | Already have valid modified data, no change needed |
| **M** | local_write_hit | M | None | Cache (local) | Already modified, no bus transaction needed |
| **M** | local_read_miss | N/A | N/A | N/A | Cannot have miss if line is in M state (invalid transition) |
| **M** | local_write_miss | N/A | N/A | N/A | Cannot have miss if line is in M state (invalid transition) |
| **M** | snoop_read (BusRd) | O | Requester: I→S; Other S: remain S | Cache (supply data) | Share data without write-back; transition to O maintains ownership |
| **M** | snoop_write (BusRdX) | I | Requester: I→M; All S: S→I; O: O→I | Cache (supply data) | Exclusive write request; must invalidate all and supply data |
| **M** | snoop_write (BusUpgr) | I | Requester: S→M; All S: S→I; O: O→I | Cache (supply data) | Upgrade request; invalidate all and supply data |
| **O** | local_read_hit | O | None | Cache (local) | Already have valid owned data, remain owner |
| **O** | local_write_hit | M | All S: S→I | Cache (local) + BusRdX | Need exclusive ownership; issue BusRdX to invalidate shared copies |
| **O** | local_read_miss | N/A | N/A | N/A | Cannot have miss if line is in O state (invalid transition) |
| **O** | local_write_miss | N/A | N/A | N/A | Cannot have miss if line is in O state (invalid transition) |
| **O** | snoop_read (BusRd) | O | Requester: I→S; Other S: remain S | Cache (supply data) | Supply data as owner; remain in O (other S caches stay S) |
| **O** | snoop_write (BusRdX) | I | Requester: I→M; All S: S→I | Cache (supply data) | Exclusive write request; invalidate all and supply data |
| **O** | snoop_write (BusUpgr) | I | Requester: S→M; All S: S→I | Cache (supply data) | Upgrade request; invalidate all and supply data |
| **E** | local_read_hit | E | None | Cache (local) | Already have valid exclusive data, no change |
| **E** | local_write_hit | M | None | Cache (local) | Silent upgrade; exclusive ownership allows modification without bus |
| **E** | local_read_miss | N/A | N/A | N/A | Cannot have miss if line is in E state (invalid transition) |
| **E** | local_write_miss | N/A | N/A | N/A | Cannot have miss if line is in E state (invalid transition) |
| **E** | snoop_read (BusRd) | S | Requester: I→S | Cache (supply data) | Share exclusive line; transition to S (shared, clean) |
| **E** | snoop_write (BusRdX) | I | Requester: I→M | Cache (supply data) | Exclusive write request; invalidate and supply data |
| **E** | snoop_write (BusUpgr) | I | Requester: S→M | Cache (supply data) | Upgrade request; invalidate and supply data |
| **S** | local_read_hit | S | None | Cache (local) | Already have valid shared data, no change |
| **S** | local_write_hit | M | All S: S→I; O: O→I (if exists) | Cache (local) + BusRdX | Need exclusive ownership; issue BusRdX to invalidate all other copies |
| **S** | local_read_miss | N/A | N/A | N/A | Cannot have miss if line is in S state (invalid transition) |
| **S** | local_write_miss | N/A | N/A | N/A | Cannot have miss if line is in S state (invalid transition) |
| **S** | snoop_read (BusRd) | S | Requester: I→S (if O exists) or I→E (if exclusive) | Memory or O cache | Not owner; no response needed; O cache or memory supplies data |
| **S** | snoop_write (BusRdX) | I | Requester: I→M | None (not owner) | Invalidate on exclusive write request; owner (M/O) supplies data |
| **S** | snoop_write (BusUpgr) | I | Requester: S→M | None (not owner) | Invalidate on upgrade request; owner (M/O) supplies data |
| **I** | local_read_hit | N/A | N/A | N/A | Cannot have hit if line is in I state (invalid transition) |
| **I** | local_read_miss (shared response) | S | M→O, E→S, O→O (if owner exists) | Cache (M/O/E) or Memory | BusRd issued; get data from owner cache or memory; transition to S |
| **I** | local_read_miss (exclusive) | E | None | Memory | BusRd issued; no other caches have line; get exclusive clean copy |
| **I** | local_write_hit | N/A | N/A | N/A | Cannot have hit if line is in I state (invalid transition) |
| **I** | local_write_miss | M | All M/O/E/S: M→I, O→I, E→I, S→I | Cache (M/O) or Memory | BusRdX issued; invalidate all copies; get data from owner or memory |
| **I** | snoop_read (BusRd) | I | None | None | Invalid state; no data to supply; requester gets data elsewhere |
| **I** | snoop_write (BusRdX) | I | None | None | Invalid state; no action needed; requester gets exclusive ownership |
| **I** | snoop_write (BusUpgr) | I | None | None | Invalid state; no action needed; requester upgrades to M |

**Notes on Table:**
- **local_read_hit/local_write_hit**: Cache line is present and valid in this cache
- **local_read_miss/local_write_miss**: Cache line is invalid (I state) in this cache
- **snoop_read**: This cache observes BusRd transaction on shared bus
- **snoop_write**: This cache observes BusRdX or BusUpgr transaction on shared bus
- **Data Source**: Where the requesting cache gets data from
- **Effect on Other Caches**: State transitions in other caches due to this operation

**Key Observations:**
1. **M → O on snoop_read**: Core MOESI optimization - avoids write-back to memory
2. **E → M on local_write_hit**: Silent upgrade, no bus transaction (exclusive ownership)
3. **O → M on local_write_hit**: Requires BusRdX to invalidate other S state copies
4. **S → M on local_write_hit**: Requires BusRdX to invalidate other copies (including O)
5. **I → S/E on local_read_miss**: Depends on whether other caches have the line
6. **I → M on local_write_miss**: Always requires BusRdX to invalidate all copies

---

## State Transitions

### Local Operations

#### Read Miss (Cache line in I state)
1. **Issue BusRd** (Bus Read) on interconnect
2. **Snoop responses**:
   - If any cache has line in M/O/E: supplies data, transitions M→O, E→S, O→O (no change)
   - If any cache has line in S: no data supplied (memory has valid copy or O cache has it)
3. **Memory response**: Supplies data if no M/O/E cache responded
4. **Local transition**: I → S (if other caches responded) or I → E (if exclusive)

#### Write Miss (Cache line in I state)
1. **Issue BusRdX** (Bus Read for eXclusive) or **BusUpgr** (Bus Upgrade) on interconnect
2. **Snoop responses**:
   - All caches with line in M/O/E/S: invalidate (M→I, O→I, E→I, S→I)
   - M/O caches: supply data
3. **Memory response**: Supplies data if no M/O cache responded
4. **Local transition**: I → M

#### Write Hit (Cache line in E or M state)
- **E state**: Silent upgrade E → M (no bus transaction)
- **M state**: No change (already modified)

#### Write Hit (Cache line in S state)
1. **Issue BusUpgr** (Bus Upgrade) or **BusRdX** on interconnect
2. **Snoop responses**: All S state caches invalidate (S → I)
3. **Local transition**: S → M

### Snoop Operations

#### Snoop Read (BusRd observed)
- **M state**: Supply data, transition M → O
- **O state**: Supply data, remain O (no change)
- **E state**: Supply data, transition E → S
- **S state**: No response needed (not owner)
- **I state**: No response

#### Snoop Write (BusRdX/BusUpgr observed)
- **M state**: Supply data, transition M → I
- **O state**: Supply data, transition O → I
- **E state**: Supply data (if needed), transition E → I
- **S state**: Transition S → I (invalidate)
- **I state**: No response

#### Snoop Invalidate (BusInv observed, if supported)
- **M/O/E/S states**: Transition to I
- **I state**: No change

---

## Example 1: Read Sharing Pattern

**Scenario**: Core 0 writes, Core 1 reads, Core 2 reads

**Initial State**: All caches have line X in I state

| Step | Operation | Core 0 | Core 1 | Core 2 | Core 3 | Bus Transaction | Notes |
|------|-----------|--------|--------|--------|--------|-----------------|-------|
| 0 | Initial | I | I | I | I | - | All invalid |
| 1 | Core 0: Write X | **M** | I | I | I | BusRdX | Core 0 gets exclusive ownership |
| 2 | Core 1: Read X | **O** | **S** | I | I | BusRd (snoop) | Core 0 supplies data, transitions to O |
| 3 | Core 2: Read X | O | S | **S** | I | BusRd (snoop) | Core 0 supplies data, Core 2 gets S |
| 4 | Core 1: Write X | **I** | **M** | **I** | I | BusRdX (snoop) | Core 1 invalidates others, gets M |

**Detailed Step-by-Step:**

**Step 1**: Core 0 write miss
- Core 0 issues BusRdX for line X
- No snoop responses (all caches invalid)
- Memory supplies data
- Core 0: I → M

**Step 2**: Core 1 read miss
- Core 1 issues BusRd for line X
- Core 0 snoops BusRd, detects M state
- Core 0 supplies data on bus, transitions M → O
- Core 1 receives data, transitions I → S
- **No memory write-back** (key MOESI advantage)

**Step 3**: Core 2 read miss
- Core 2 issues BusRd for line X
- Core 0 snoops BusRd, detects O state
- Core 0 supplies data on bus, remains O
- Core 2 receives data, transitions I → S
- Core 1 snoops but remains S (no action needed)

**Step 4**: Core 1 write hit (S state)
- Core 1 issues BusRdX for line X
- Core 0 snoops BusRdX, supplies data, transitions O → I
- Core 2 snoops BusRdX, transitions S → I
- Core 1 receives data (from Core 0), transitions S → M

---

## Example 2: Write-Back Optimization

**Scenario**: Core 0 writes, Core 1 reads, Core 0 evicts, Core 2 reads

**Initial State**: All caches have line X in I state

| Step | Operation | Core 0 | Core 1 | Core 2 | Core 3 | Bus Transaction | Notes |
|------|-----------|--------|--------|--------|--------|-----------------|-------|
| 0 | Initial | I | I | I | I | - | All invalid |
| 1 | Core 0: Write X | **M** | I | I | I | BusRdX | Exclusive write |
| 2 | Core 1: Read X | **O** | **S** | I | I | BusRd (snoop) | Core 0 transitions to O, no write-back |
| 3 | Core 0: Evict X | **I** | **O** | I | I | - | Core 0 write-backs, Core 1 becomes owner |
| 4 | Core 2: Read X | I | O | **S** | I | BusRd (snoop) | Core 1 supplies data, remains O |

**Detailed Step-by-Step:**

**Step 1**: Core 0 write miss
- Core 0: I → M
- Memory does not have valid copy

**Step 2**: Core 1 read miss
- Core 0 snoops BusRd, supplies data, transitions M → O
- Core 1: I → S
- **Key point**: No memory write-back occurs (MOESI optimization)
- Memory still has stale data, but Core 0 (now O) maintains correct data

**Step 3**: Core 0 evicts line X
- Core 0 must write-back (O state is dirty)
- Core 0 issues write-back to memory
- Core 0: O → I
- **Core 1 automatically becomes owner** (only O state cache remaining)
- Memory now has valid copy

**Step 4**: Core 2 read miss
- Core 2 issues BusRd
- Core 1 snoops BusRd, detects O state
- Core 1 supplies data, remains O
- Core 2: I → S
- Memory also has valid copy, but Core 1 supplies data (lower latency)

---

## Example 3: Complex Multi-Core Interaction

**Scenario**: Core 0 writes, Core 1 reads, Core 2 writes, Core 3 reads, Core 1 writes

**Initial State**: All caches have line X in I state

| Step | Operation | Core 0 | Core 1 | Core 2 | Core 3 | Bus Transaction | Notes |
|------|-----------|--------|--------|--------|--------|-----------------|-------|
| 0 | Initial | I | I | I | I | - | All invalid |
| 1 | Core 0: Write X | **M** | I | I | I | BusRdX | Exclusive ownership |
| 2 | Core 1: Read X | **O** | **S** | I | I | BusRd (snoop) | Shared read, Core 0 → O |
| 3 | Core 2: Write X | **I** | **I** | **M** | I | BusRdX (snoop) | Core 2 invalidates all, gets M |
| 4 | Core 3: Read X | I | I | **O** | **S** | BusRd (snoop) | Core 2 → O, Core 3 → S |
| 5 | Core 1: Write X | I | **M** | **I** | **I** | BusRdX (snoop) | Core 1 invalidates all, gets M |

**Detailed Step-by-Step:**

**Step 1**: Core 0 write miss
- Core 0: I → M
- Exclusive ownership established

**Step 2**: Core 1 read miss
- Core 0 snoops BusRd
- Core 0 supplies data, transitions M → O
- Core 1: I → S
- Line is now shared (O in Core 0, S in Core 1)

**Step 3**: Core 2 write miss
- Core 2 issues BusRdX
- Core 0 snoops BusRdX, supplies data, transitions O → I
- Core 1 snoops BusRdX, transitions S → I
- Core 2 receives data (from Core 0), transitions I → M
- Line is now exclusively owned by Core 2

**Step 4**: Core 3 read miss
- Core 3 issues BusRd
- Core 2 snoops BusRd, supplies data, transitions M → O
- Core 3: I → S
- Line is shared again (O in Core 2, S in Core 3)

**Step 5**: Core 1 write miss
- Core 1 issues BusRdX
- Core 2 snoops BusRdX, supplies data, transitions O → I
- Core 3 snoops BusRdX, transitions S → I
- Core 1 receives data (from Core 2), transitions I → M
- Line is now exclusively owned by Core 1

---

## Implementation Considerations for RTL/Verification

### State Machine Encoding
- **Minimum bits**: 3 bits per cache line (5 states)
- **Encoding options**:
  - One-hot: 5 bits (easier for synthesis, more area)
  - Binary: 3 bits (area efficient, requires decoder)
  - Gray code: 3 bits (reduces glitches during transitions)

### Snoop Filtering
- Track which caches may have line in S/O states
- Reduces unnecessary snoop broadcasts
- Critical for scalability beyond 4 cores

### Write-Back Conditions
- **M → I**: Always write-back
- **O → I**: Always write-back
- **E → I**: No write-back (clean)
- **S → I**: No write-back (clean)

### Race Conditions
- **Snoop vs Local Write**: Local write in progress when snoop arrives
- **Multiple Snoops**: Handle concurrent snoop requests
- **Eviction vs Snoop**: Eviction in progress when snoop arrives

### Verification Checklist
- [ ] All state transitions covered
- [ ] Snoop response timing verified
- [ ] Write-back conditions tested
- [ ] Race conditions handled
- [ ] Deadlock prevention verified
- [ ] Livelock prevention verified
- [ ] Correctness: no data loss or corruption
- [ ] Performance: O state reduces memory traffic

### Common Bugs
1. **Forgotten write-back**: O → I without write-back
2. **Double write-back**: Multiple caches writing back same line
3. **Stale data**: S state cache not invalidated on write
4. **Snoop response missing**: O/M cache not responding to BusRd
5. **State corruption**: Concurrent operations corrupting state bits

---

## Summary

MOESI extends MESI with the **Owned (O)** state to optimize write-back operations. The key insight is that when a modified cache line is read by another core, it can transition to O state and share the data without writing back to memory. This reduces memory bandwidth and improves performance in read-sharing workloads.

The protocol maintains correctness through:
- **Exclusive ownership** for M and E states
- **Single owner** for O state (with multiple S state copies)
- **Proper invalidation** on write operations
- **Write-back** on eviction of dirty states (M, O)

For verification engineers, focus on:
- Complete state transition coverage
- Snoop response correctness
- Write-back conditions
- Race condition handling
- Performance verification (O state optimization)
