---
name: benchmarking
description: Measures Lua performance optimizations in Helm.spoon. Use when optimizing code, comparing implementations, or measuring execution time.
---

# Lua Benchmarking for Helm.spoon

Use the `benchmark.lua` library to measure and compare performance of Lua implementations.

## Quick Start

```lua
local benchmark = require("benchmark")

-- Compare two implementations
local results = benchmark.compare({
    baseline = function() original_code() end,
    optimized = function() improved_code() end,
}, { iterations = 100 })

print(benchmark.report(results))
```

## API Reference

### benchmark.measure(fn, opts)

Measure a single function's performance.

**Options:**
- `iterations` (default: 100) - Number of timed runs
- `warmup` (default: 10) - Warmup iterations before timing
- `setup` - Function returning data passed to `fn`
- `teardown` - Called after each iteration

**Returns:** `{ avg, median, min, max, p95 }` in milliseconds

### benchmark.compare(implementations, opts)

Compare multiple implementations.

**Arguments:**
- `implementations` - Table mapping names to functions
- Use `baseline` and `optimized` keys for automatic speedup calculation

**Returns:** Stats for each implementation plus `speedup` ratio

### benchmark.run(implementations, opts)

Compare and print results. Same as `compare` but outputs to console.

### benchmark.stats(times)

Calculate statistics from raw timing array.

### benchmark.format(ms)

Format milliseconds with appropriate units (ns/μs/ms/s).

### benchmark.report(results)

Generate formatted report string from comparison results.

## Workflow for Performance Optimization

1. **Write benchmark test first:**
   ```lua
   -- spec/my_feature_benchmark_spec.lua
   describe("my feature performance", function()
       it("optimized version is faster", function()
           local results = benchmark.compare({
               baseline = function() old_implementation(test_data) end,
               optimized = function() new_implementation(test_data) end,
           }, { iterations = 100 })

           assert.is_true(results.speedup > 1.5, "Expected 1.5x speedup")
       end)
   end)
   ```

2. **Run benchmark to establish baseline:**
   ```bash
   busted spec/my_feature_benchmark_spec.lua
   ```

3. **Implement optimization**

4. **Re-run benchmark to verify improvement**

## Example: Reducing IPC Calls

```lua
-- Problem: frame() is called O(n log n) times during sort
local function sortOriginal(windows)
    table.sort(windows, function(a, b)
        return a:frame().x < b:frame().x
    end)
    return windows
end

-- Solution: Cache frames before sorting (O(n) calls)
local function sortOptimized(windows)
    local cached = {}
    for i, win in ipairs(windows) do
        cached[i] = { win = win, x = win:frame().x }
    end
    table.sort(cached, function(a, b) return a.x < b.x end)
    for i, entry in ipairs(cached) do cached[i] = entry.win end
    return cached
end

-- Benchmark
benchmark.run({
    baseline = function() sortOriginal(windows) end,
    optimized = function() sortOptimized(windows) end,
}, { 
    iterations = 1000,
    setup = function() return generateTestWindows(20) end,
})
```

## Running Benchmarks in Hammerspoon

For real-world testing with actual Hammerspoon APIs (windows, screens, etc.), update the benchmark hotkey in `~/.hammerspoon/init.lua`:

```lua
hs.hotkey.bind({ "cmd", "ctrl" }, "b", function()
    local benchmark = require("benchmark")
    -- Replace with your current benchmark code
    benchmark.run({
        baseline = function() ... end,
        optimized = function() ... end,
    }, { iterations = 100, name = "My Optimization" })
end)
```

After updating, reload Hammerspoon (cmd+ctrl+r) and press cmd+ctrl+b to run. Results appear in the Hammerspoon console.

## Tips

- Use `setup` to create fresh test data for each iteration
- Higher `iterations` = more stable results
- Use `warmup` to avoid JIT/cache cold-start effects
- Name implementations `baseline`/`optimized` for automatic speedup
- Update the hotkey to test with real Hammerspoon objects
