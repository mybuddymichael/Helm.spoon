--- Generic performance benchmark library for Helm.spoon
--- Usage: local benchmark = require("benchmark")
---        benchmark.compare({ baseline = fn1, optimized = fn2 })

local benchmark = {}

local DEFAULT_ITERATIONS = 100
local DEFAULT_WARMUP = 10

--- Calculate statistics from an array of timing values
--- @param times table Array of timing values (in ms)
--- @return table Statistics { avg, median, min, max, p95 }
function benchmark.stats(times)
	if #times == 0 then
		return { avg = 0, median = 0, min = 0, max = 0, p95 = 0 }
	end

	local sorted = {}
	for i, t in ipairs(times) do sorted[i] = t end
	table.sort(sorted)

	local sum = 0
	for _, t in ipairs(sorted) do sum = sum + t end

	local median_idx = math.max(1, math.floor(#sorted / 2) + 1)
	local p95_idx = math.max(1, math.min(#sorted, math.floor(#sorted * 0.95) + 1))

	return {
		avg = sum / #sorted,
		median = sorted[median_idx],
		min = sorted[1],
		max = sorted[#sorted],
		p95 = sorted[p95_idx],
	}
end

--- Get current time in nanoseconds
local function now()
	return hs.timer.absoluteTime()
end

--- Time a single function execution
--- @param fn function Function to time
--- @param data any Data to pass to the function
--- @return number Elapsed time in milliseconds
local function timeIt(fn, data)
	local start = now()
	fn(data)
	return (now() - start) / 1000000
end

--- Measure performance of a single function
--- @param fn function Function to measure
--- @param opts table Options { iterations, warmup, setup, teardown }
--- @return table Statistics { avg, median, min, max, p95 }
function benchmark.measure(fn, opts)
	opts = opts or {}
	local iterations = opts.iterations or DEFAULT_ITERATIONS
	local warmup = opts.warmup or DEFAULT_WARMUP
	local setup = opts.setup
	local teardown = opts.teardown

	local data = setup and setup() or nil

	for _ = 1, warmup do
		fn(data)
	end

	local times = {}
	for _ = 1, iterations do
		table.insert(times, timeIt(fn, data))
		if teardown then teardown() end
	end

	return benchmark.stats(times)
end

--- Compare two or more implementations
--- @param implementations table Map of name -> function
--- @param opts table Options { iterations, warmup, setup, teardown }
--- @return table Results with stats for each implementation and speedup
function benchmark.compare(implementations, opts)
	opts = opts or {}

	local names = {}
	for name in pairs(implementations) do
		table.insert(names, name)
	end
	table.sort(names)

	local results = {}
	for _, name in ipairs(names) do
		results[name] = benchmark.measure(implementations[name], opts)
	end

	if results.baseline and results.optimized then
		results.speedup = results.baseline.avg / results.optimized.avg
	elseif results.slow and results.fast then
		results.speedup = results.slow.avg / results.fast.avg
	elseif #names == 2 then
		local first = results[names[1]]
		local second = results[names[2]]
		results.speedup = first.avg / second.avg
	else
		results.speedup = 1
	end

	return results
end

--- Format time value with appropriate units
--- @param ms number Time in milliseconds
--- @return string Formatted time string
function benchmark.format(ms)
	if ms < 0.001 then
		return string.format("%.2f ns", ms * 1000000)
	elseif ms < 1 then
		return string.format("%.2f μs", ms * 1000)
	elseif ms < 1000 then
		return string.format("%.2f ms", ms)
	else
		return string.format("%.2f s", ms / 1000)
	end
end

--- Generate a formatted report from comparison results
--- @param results table Results from benchmark.compare()
--- @return string Formatted report
function benchmark.report(results)
	local lines = {}
	table.insert(lines, "=== Benchmark Results ===\n")

	local names = {}
	for name in pairs(results) do
		if type(results[name]) == "table" and results[name].avg then
			table.insert(names, name)
		end
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local r = results[name]
		table.insert(lines, string.format("%s:", name))
		table.insert(lines, string.format("  avg=%s median=%s p95=%s",
			benchmark.format(r.avg),
			benchmark.format(r.median),
			benchmark.format(r.p95)))
	end

	if results.speedup then
		table.insert(lines, string.format("\nSpeedup: %.1fx", results.speedup))
	end

	return table.concat(lines, "\n")
end

--- Run a benchmark and print results
--- @param implementations table Map of name -> function
--- @param opts table Options { iterations, warmup, setup, teardown, name }
function benchmark.run(implementations, opts)
	opts = opts or {}
	local name = opts.name or "Benchmark"

	print(string.format("\n=== %s ===", name))
	print(string.format("Iterations: %d, Warmup: %d",
		opts.iterations or DEFAULT_ITERATIONS,
		opts.warmup or DEFAULT_WARMUP))

	local results = benchmark.compare(implementations, opts)
	print(benchmark.report(results))

	return results
end

return benchmark
