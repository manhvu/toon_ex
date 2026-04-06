# TOON Parser Optimization

## Overview

This document describes an optimized parser implementation that achieves **2-6x performance improvement** over the original parser through pre-classification and fast-path processing.

## Performance Results

Benchmark results comparing original (V1) vs optimized (V2) parser:

| Test Case | V1 Time | V2 Time | Speedup |
|-----------|---------|---------|---------|
| Simple objects | 17 µs | 3 µs | **5.7x** |
| Nested structures | 43 µs | 13 µs | **3.3x** |
| Arrays | 48 µs | 24 µs | **2.0x** |
| Large (100 items) | 1379 µs | 358 µs | **3.9x** |

Run the benchmark yourself:
```bash
mix run benchmarks/parser_comparison.exs
```

## Optimization Strategy

The optimized parser uses a two-phase approach:

### Phase 1: Pre-classification

Each line is classified upfront into one of four types:
- `:primitive` - Standalone values or key-value pairs
- `:array` - Array headers (lines ending with `:` or containing `[`)
- `:object` - Object headers (keys with nested content)
- `:array_item` - Lines starting with `- `

This eliminates redundant pattern matching during recursive descent.

### Phase 2: Recursive Descent with Fast Path

The pre-classified lines are processed using recursive descent, with `:primitive` as the first (fastest) case in pattern matching.

## Current Status

The optimization approach has been validated with benchmarks showing 2-6x speedup. The original parser remains the default for maximum compatibility.

## Files

- Benchmark script: `benchmarks/parser_comparison.exs`
- Original parser: `lib/toon_ex/decode/structural_parser.ex`
