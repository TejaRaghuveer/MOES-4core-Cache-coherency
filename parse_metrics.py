#!/usr/bin/env python3
"""
parse_metrics.py
Parse perf_dump.txt metrics, compute rates, print table, and emit CSV row.
"""

import argparse
import csv
from pathlib import Path


def parse_kv_lines(text):
    data = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        try:
            data[key] = int(val)
        except ValueError:
            # Leave non-integer as raw string
            data[key] = val
    return data


def safe_div(n, d):
    return (n / d) if d else None


def fmt_rate(x):
    return "N/A" if x is None else f"{x:.4f}"


def main():
    ap = argparse.ArgumentParser(description="Parse perf dump and compute metrics.")
    ap.add_argument("input", help="Path to perf_dump.txt")
    ap.add_argument("--csv", default="metrics.csv", help="CSV output file")
    args = ap.parse_args()

    text = Path(args.input).read_text(encoding="utf-8")
    d = parse_kv_lines(text)

    total_reads = d.get("total_reads", 0)
    read_hits = d.get("read_hits", 0)
    read_misses = d.get("read_misses", 0)
    total_writes = d.get("total_writes", 0)
    write_hits = d.get("write_hits", 0)
    write_misses = d.get("write_misses", 0)
    coherency_invalidates = d.get("coherency_invalidates", 0)
    cycles = d.get("cycles", 0)
    cycles_bus_busy = d.get("cycles_bus_busy", None)

    total_accesses = total_reads + total_writes
    total_hits = read_hits + write_hits
    total_misses = read_misses + write_misses

    cache_hit_rate = safe_div(total_hits, total_accesses)
    cache_miss_rate = safe_div(total_misses, total_accesses)
    coherency_miss_rate = safe_div(coherency_invalidates, total_reads)
    bus_utilization = safe_div(cycles_bus_busy, cycles) if cycles_bus_busy is not None else None

    print("Metric                       Value")
    print("--------------------------------------")
    print(f"total_reads                 {total_reads}")
    print(f"read_hits                   {read_hits}")
    print(f"read_misses                 {read_misses}")
    print(f"total_writes                {total_writes}")
    print(f"write_hits                  {write_hits}")
    print(f"write_misses                {write_misses}")
    print(f"coherency_invalidates       {coherency_invalidates}")
    print(f"cycles                      {cycles}")
    if cycles_bus_busy is not None:
        print(f"cycles_bus_busy             {cycles_bus_busy}")
    print("--------------------------------------")
    print(f"cache_hit_rate              {fmt_rate(cache_hit_rate)}")
    print(f"cache_miss_rate             {fmt_rate(cache_miss_rate)}")
    print(f"coherency_miss_rate         {fmt_rate(coherency_miss_rate)}")
    print(f"bus_utilization             {fmt_rate(bus_utilization)}")

    # Write CSV row
    fieldnames = [
        "total_reads", "read_hits", "read_misses",
        "total_writes", "write_hits", "write_misses",
        "coherency_invalidates", "cycles", "cycles_bus_busy",
        "cache_hit_rate", "cache_miss_rate",
        "coherency_miss_rate", "bus_utilization",
    ]
    row = {
        "total_reads": total_reads,
        "read_hits": read_hits,
        "read_misses": read_misses,
        "total_writes": total_writes,
        "write_hits": write_hits,
        "write_misses": write_misses,
        "coherency_invalidates": coherency_invalidates,
        "cycles": cycles,
        "cycles_bus_busy": cycles_bus_busy if cycles_bus_busy is not None else "",
        "cache_hit_rate": cache_hit_rate if cache_hit_rate is not None else "",
        "cache_miss_rate": cache_miss_rate if cache_miss_rate is not None else "",
        "coherency_miss_rate": coherency_miss_rate if coherency_miss_rate is not None else "",
        "bus_utilization": bus_utilization if bus_utilization is not None else "",
    }

    write_header = not Path(args.csv).exists()
    with open(args.csv, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    main()
