--- Tests for the generic benchmark library
local mock_hs = require("spec.mock_hammerspoon")

describe("benchmark", function()
	local benchmark

	before_each(function()
		mock_hs.reset()
		-- Add absoluteTime to mock timer for benchmarking
		_G.hs.timer.absoluteTime = function()
			return os.clock() * 1e9 -- nanoseconds
		end
		package.loaded["benchmark"] = nil
		benchmark = require("benchmark")
	end)

	describe("measure", function()
		it("returns timing statistics for a function", function()
			local fn = function() return 1 + 1 end
			local result = benchmark.measure(fn, { iterations = 10 })

			assert.is_table(result)
			assert.is_number(result.avg)
			assert.is_number(result.median)
			assert.is_number(result.min)
			assert.is_number(result.max)
			assert.is_number(result.p95)
			assert.is_true(result.avg >= 0)
			assert.is_true(result.min <= result.avg)
			assert.is_true(result.avg <= result.max)
		end)

		it("runs warmup iterations before measuring", function()
			local callCount = 0
			local fn = function() callCount = callCount + 1 end

			benchmark.measure(fn, { iterations = 10, warmup = 5 })
			assert.equals(15, callCount)
		end)

		it("passes setup result to measured function", function()
			local receivedData
			local setup = function() return { value = 42 } end
			local fn = function(data) receivedData = data end

			benchmark.measure(fn, { iterations = 1, setup = setup })
			assert.is_table(receivedData)
			assert.equals(42, receivedData.value)
		end)

		it("calls teardown after each iteration", function()
			local teardownCount = 0
			local fn = function() end
			local teardown = function() teardownCount = teardownCount + 1 end

			benchmark.measure(fn, { iterations = 5, teardown = teardown })
			assert.equals(5, teardownCount)
		end)
	end)

	describe("compare", function()
		it("compares two implementations", function()
			local baseline = function() for i = 1, 100 do end end
			local optimized = function() for i = 1, 10 do end end

			local result = benchmark.compare({
				baseline = baseline,
				optimized = optimized,
			}, { iterations = 10 })

			assert.is_table(result)
			assert.is_table(result.baseline)
			assert.is_table(result.optimized)
			assert.is_number(result.speedup)
		end)

		it("calculates speedup correctly", function()
			local slowFn = function()
				local x = 0
				for i = 1, 10000 do x = x + i end
			end
			local fastFn = function()
				local x = 0
				for i = 1, 100 do x = x + i end
			end

			local result = benchmark.compare({
				slow = slowFn,
				fast = fastFn,
			}, { iterations = 50 })

			assert.is_true(result.speedup > 1, "Fast fn should be faster than slow fn")
		end)
	end)

	describe("stats", function()
		it("calculates statistics from raw times", function()
			local times = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
			local result = benchmark.stats(times)

			assert.equals(5.5, result.avg)
			assert.is_true(result.median >= 5 and result.median <= 6)
			assert.equals(1, result.min)
			assert.equals(10, result.max)
		end)

		it("handles single value", function()
			local result = benchmark.stats({ 5 })
			assert.equals(5, result.avg)
			assert.equals(5, result.min)
			assert.equals(5, result.max)
		end)
	end)

	describe("format", function()
		it("formats milliseconds appropriately", function()
			assert.matches("μs", benchmark.format(0.001))
			assert.matches("ms", benchmark.format(1.5))
			assert.matches("s", benchmark.format(1500))
		end)
	end)

	describe("report", function()
		it("generates formatted report from comparison results", function()
			local result = {
				baseline = { avg = 0.5, median = 0.45, p95 = 0.7, min = 0.3, max = 0.9 },
				optimized = { avg = 0.1, median = 0.09, p95 = 0.15, min = 0.05, max = 0.2 },
				speedup = 5.0,
			}

			local report = benchmark.report(result)
			assert.is_string(report)
			assert.matches("baseline", report)
			assert.matches("optimized", report)
			assert.matches("5.0x", report)
		end)
	end)
end)
