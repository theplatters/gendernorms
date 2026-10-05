# Paired same-revision micro-benchmark of the labour best-response solver
# of `MDR-0017` (see `TASK-0023`): the specialized
# `best_response_1d(::BestResponseObjective, ::Float64)` (safeguarded
# derivative solve with the seeded Brent fallback) against the legacy
# `MDR-0002` expression `maximize_1d(obj, 0.0, 1.0, h_start,
# BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)` on the same prepared
# objectives, plus `mutual_best_response` against a benchmark-local copy
# of its alternation loop using the legacy expression. Both paths are
# callable in one build; every cell times many samples after warm-up and
# reports the median per-call time. Applicable cells are classified by
# route (tier-1 seed certificate, boundary, interior root, fallback)
# through `GN._derivative_best_response`, and a final allocation
# section reports the allocated bytes per call of both paths. Run with:
# `julia --project=. benchmark/derivative_solver_benchmark.jl`.

using GenderNorms
const GN = GenderNorms

const SPECS = (
    ("multiplicative", GN.Multiplicative()),
    ("mult_weighted", GN.MultiplicativeWeighted()),
    ("additive", GN.Additive()),
    ("ces_beta_0.5", GN.CES(beta = 0.5)),
    ("ces_beta_0.2", GN.CES(beta = 0.2)),
    ("ces_beta_0.9", GN.CES(beta = 0.9)),
    ("ces_beta_1.0", GN.CES(beta = 1.0)),
)

const ROUNDS = 31
const INNER = 201

"""
    time_per_call(f, arg)::Float64

Median per-call nanoseconds of `f(arg)` over `ROUNDS` timed rounds of
`INNER` calls each, after a warm-up call. Every result feeds a `Ref`
sink so the compiler cannot dead-code-eliminate the timed calls.
"""
function time_per_call(f, arg)::Float64
    sink = Ref(0.0)
    sink[] = f(arg)
    samples = Vector{Float64}(undef, ROUNDS)
    for round in 1:ROUNDS
        t0 = time_ns()
        for _ in 1:INNER
            sink[] = f(arg)
        end
        samples[round] = (time_ns() - t0) / INNER
    end
    sort!(samples)
    return samples[div(ROUNDS + 1, 2)]
end

legacy_solve(obj, h) =
    GN.maximize_1d(obj, 0.0, 1.0, h, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL)

"""
    route_label(obj, h)::String

Route classification of one specialized solve through
`GN._derivative_best_response`: `fallback` (the legacy path runs),
`tier1` (the `MDR-0017` seed certificate keeps the seed),
`boundary` (an endpoint is selected), or `interior` (a bracketed root
is returned).
"""
function route_label(obj, h)::String
    candidate, ok = GN._derivative_best_response(obj, h)
    ok || return "fallback"
    if candidate == h
        return GN._derivative_seed_certificate(obj, h) ? "tier1" : "interior"
    end
    (candidate == 0.0 || candidate == 1.0) && return "boundary"
    return "interior"
end

"""
    settle_mbr(hw, hm, theta, pw, pm, config)

Bitwise settled fixed point of `mutual_best_response`: restart the
alternation at its own output until it returns it unchanged (the
`test/test_household_bargaining.jl` settle loop), so the `settled`
seeds exercise the `MDR-0017` tier-1 seed certificate of a converged
sweep.
"""
function settle_mbr(
        hw::Float64, hm::Float64, theta::Float64,
        pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config::GN.UtilityConfig,
    )
    for _ in 1:40
        hw_next, hm_next = GN.mutual_best_response(hw, hm, theta, pw, pm, config)
        (hw_next == hw && hm_next == hm) && break
        hw, hm = hw_next, hm_next
    end
    return (hw, hm)
end

function main()
    # Household scenarios: the `test/test_household_bargaining.jl`
    # sharply-peaked pair and a plain zero-conformism pair, per spec and
    # role. Every objective is the role's own at the role's transfer
    # `theta0 = 0.05` (the woman is the recipient, the man the payer of
    # that transfer-to-woman), with `h_spouse` at the settled fixed
    # point of the same transfer. `settled` seeds are the partner's own
    # settled hours (the converged-sweep case), `near` perturbs them by
    # `+0.002` (the production warm-start shape), `far_lo`/`far_hi`
    # come from the domain ends.
    println(
        "solve-level micro-benchmark (ns per call, median of ",
        ROUNDS, " rounds x ", INNER, " calls)"
    )
    println()
    header = rpad("spec", 16) * rpad("role", 9) * rpad("start", 8) *
        rpad("legacy", 10) * rpad("new", 10) * rpad("speedup", 9) * "route"
    println(header)
    totals_legacy = Float64[]
    totals_new = Float64[]
    route_counts = Dict{String, Int}("tier1" => 0, "boundary" => 0, "interior" => 0, "fallback" => 0)
    spec_rows = Dict{String, Tuple{Vector{Float64}, Vector{Float64}}}()
    for (spec_name, spec) in SPECS, (role, gender) in (("recipient", GN.Female()), ("payer", GN.Male()))
        for (wage_self, wage_spouse, alpha, conformism) in (
                (0.9, 1.0, 0.48, 10.0), (1.2, 0.8, 0.5, 0.0),
            )
            theta0 = 0.05
            config = GN.UtilityConfig(func = spec)
            p0 = GN.AgentPayoffParams{typeof(gender)}(
                wage_self = wage_self, wage_spouse = wage_spouse, alpha = alpha,
                conformism = conformism, N_h = 0.36, N_theta = 0.0, N_h_spouse = 0.77,
            )
            partner = GN.AgentPayoffParams{gender isa GN.Female ? GN.Male : GN.Female}(
                wage_self = wage_spouse, wage_spouse = wage_self, alpha = alpha,
                conformism = conformism, N_h = 0.77, N_theta = 0.0, N_h_spouse = 0.36,
            )
            hw_eq, hm_eq = settle_mbr(0.36, 0.77, theta0, p0, partner, config)
            # `p0` is the first `mutual_best_response` argument, so its
            # settled own hours are `hw_eq` and its spouse hours `hm_eq`
            # (independent of which partner is the woman).
            own_eq = hw_eq
            spouse_eq = hm_eq
            obj = GN.BestResponseObjective(theta0, spouse_eq, p0, config)
            for (start_name, h_start) in (
                    ("settled", own_eq), ("near", min(own_eq + 0.002, 1.0)),
                    ("far_lo", 0.05), ("far_hi", 0.95),
                )
                # Both timed closures share the objective and seed; the
                # paired medians differ only in the solver expression.
                t_legacy = time_per_call(h -> legacy_solve(obj, h), h_start)
                t_new = time_per_call(h -> GN.best_response_1d(obj, h), h_start)
                route = route_label(obj, h_start)
                route_counts[route] += 1
                push!(totals_legacy, t_legacy)
                push!(totals_new, t_new)
                rows = get!(spec_rows, spec_name, (Float64[], Float64[]))
                push!(rows[1], t_legacy)
                push!(rows[2], t_new)
                println(
                    rpad(spec_name, 16) * rpad(role, 9) * rpad(start_name, 8) *
                        rpad(round(t_legacy, digits = 1), 10) * rpad(round(t_new, digits = 1), 10) *
                        rpad(round(t_legacy / t_new, digits = 2), 9) * route
                )
            end
        end
    end
    println()
    println("per-spec medians (ns per call, all roles and starts)")
    println(rpad("spec", 16) * rpad("legacy", 10) * rpad("new", 10) * "speedup")
    for (spec_name, _) in SPECS
        rows = spec_rows[spec_name]
        ml = sort(rows[1])[div(length(rows[1]) + 1, 2)]
        mn = sort(rows[2])[div(length(rows[2]) + 1, 2)]
        println(
            rpad(spec_name, 16) * rpad(round(ml, digits = 1), 10) *
                rpad(round(mn, digits = 1), 10) * rpad(round(ml / mn, digits = 2), 7)
        )
    end
    mix_legacy = sort(totals_legacy)[div(length(totals_legacy) + 1, 2)]
    mix_new = sort(totals_new)[div(length(totals_new) + 1, 2)]
    println()
    println(
        "applicable mix median: legacy ", round(mix_legacy, digits = 1),
        " ns, new ", round(mix_new, digits = 1), " ns, speedup ",
        round(mix_legacy / mix_new, digits = 2), "x"
    )
    n = length(totals_legacy)
    return println("routes: ", join(["$k=$(round(100 * v / n, digits = 1))%" for (k, v) in sort(collect(route_counts))], " "))
end

"""
    mbr_sum(hours)::Float64

Sum of a `mutual_best_response` hour pair, so the timed call returns one
`Float64` for the `time_per_call` sink.
"""
mbr_sum(hours)::Float64 = hours[1] + hours[2]

"""
    mbr_legacy(hw_init, hm_init, theta, pw, pm, config)

Benchmark-local copy of the `mutual_best_response` alternation loop of
`src/optim/labour_optimization.jl` (lines 498-511) with each best
response run through the legacy `MDR-0002` expression instead of the
specialized solver.
"""
function mbr_legacy(
        hw_init::Float64, hm_init::Float64, theta::Float64,
        pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config::GN.UtilityConfig;
        eps = 1.0e-3, max_sweeps = 100,
    )
    hw = clamp(hw_init, 0.0, 1.0)
    hm = clamp(hm_init, 0.0, 1.0)
    for _ in 1:max_sweeps
        hw_new = legacy_solve(GN.BestResponseObjective(theta, hm, pw, config), hw)
        isfinite(hw_new) || (hw_new = hw)
        hm_new = legacy_solve(GN.BestResponseObjective(theta, hw_new, pm, config), hm)
        isfinite(hm_new) || (hm_new = hm)
        change = abs(hw_new - hw) + abs(hm_new - hm)
        hw = clamp(hw_new, 0, 1)
        hm = clamp(hm_new, 0, 1)
        change <= eps && break
    end
    return (hw, hm)
end

function mbr_benchmark()
    println()
    println(
        "mutual_best_response alternation (ns per call, median of ",
        ROUNDS, " rounds x ", INNER, " calls)"
    )
    println()
    println(
        rpad("spec", 16) * rpad("start", 8) * rpad("legacy", 10) *
            rpad("new", 10) * rpad("speedup", 9) * "dh_w, dh_m (new vs legacy)"
    )
    pairs = (
        ("peaked", (0.9, 1.0, 0.48, 10.0), (1.0, 0.9, 0.45, 10.0)),
        ("plain", (1.2, 0.8, 0.5, 0.0), (0.8, 1.2, 0.5, 0.0)),
    )
    theta0 = 0.05
    for (spec_name, spec) in SPECS, (pair_name, (ww, ws, a, c), (mw, ms, am, cm)) in pairs
        pw = GN.AgentPayoffParams{GN.Female}(
            wage_self = ww, wage_spouse = ws, alpha = a, conformism = c,
            N_h = 0.36, N_theta = 0.0, N_h_spouse = 0.77,
        )
        pm = GN.AgentPayoffParams{GN.Male}(
            wage_self = mw, wage_spouse = ms, alpha = am, conformism = cm,
            N_h = 0.77, N_theta = 0.0, N_h_spouse = 0.36,
        )
        config = GN.UtilityConfig(func = spec)
        h_fixed = settle_mbr(0.36, 0.77, theta0, pw, pm, config)
        for (start_name, init) in (
                ("near", h_fixed), ("pert", (min(h_fixed[1] + 0.01, 1.0), max(h_fixed[2] - 0.01, 0.0))),
                ("far", (0.05, 0.95)),
            )
            args = (init[1], init[2], theta0, pw, pm, config)
            t_legacy = time_per_call(a -> mbr_sum(mbr_legacy(a...)), args)
            t_new = time_per_call(a -> mbr_sum(GN.mutual_best_response(a...)), args)
            lhw, lhm = mbr_legacy(args...)
            nhw, nhm = GN.mutual_best_response(args...)
            println(
                rpad(spec_name * "/" * pair_name, 16) * rpad(start_name, 8) *
                    rpad(round(t_legacy, digits = 1), 10) * rpad(round(t_new, digits = 1), 10) *
                    rpad(round(t_legacy / t_new, digits = 2), 9) *
                    string(
                    round(abs(nhw - lhw), sigdigits = 3), ", ",
                    round(abs(nhm - lhm), sigdigits = 3)
                )
            )
        end
    end
    return
end

"""
    fallback_benchmark()

Inapplicable cases (bitwise legacy by construction): the paired timing of
the specialized dispatch against the explicit legacy expression, which
must show no slowdown. Includes the `CES_DERIVATIVE_MIN_BETA` sub-floor
band of `MDR-0017`, which the applicability floor routes here.
"""
function fallback_benchmark()
    println()
    println("inapplicable cases (must be bitwise identical and not slower)")
    println()
    println(rpad("case", 26) * rpad("legacy", 10) * rpad("new", 10) * rpad("speedup", 9) * "bitwise")
    cases = (
        ("ces_beta_0.0", GN.UtilityConfig(func = GN.CES(beta = 0.0))),
        ("ces_beta_-1.0", GN.UtilityConfig(func = GN.CES(beta = -1.0))),
        ("ces_beta_1.5", GN.UtilityConfig(func = GN.CES(beta = 1.5))),
        ("ces_beta_NaN", GN.UtilityConfig(func = GN.CES(beta = NaN))),
        ("ces_beta_1e-12", GN.UtilityConfig(func = GN.CES(beta = 1.0e-12))),
        ("ces_beta_1e-6", GN.UtilityConfig(func = GN.CES(beta = 1.0e-6))),
        ("ces_beta_2e-5", GN.UtilityConfig(func = GN.CES(beta = 2.0e-5))),
    )
    for (case_name, config) in cases
        p = GN.AgentPayoffParams{GN.Female}(
            wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 2.0,
            N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
        )
        obj = GN.BestResponseObjective(0.1, 0.5, p, config)
        t_legacy = time_per_call(h -> legacy_solve(obj, h), 0.3)
        t_new = time_per_call(h -> GN.best_response_1d(obj, h), 0.3)
        same = isequal(GN.best_response_1d(obj, 0.3), legacy_solve(obj, 0.3))
        println(
            rpad(case_name, 26) * rpad(round(t_legacy, digits = 1), 10) *
                rpad(round(t_new, digits = 1), 10) * rpad(round(t_legacy / t_new, digits = 2), 9) *
                string(same)
        )
    end
    return
end

# Allocation probes measured through top-level helpers so the call site
# cannot box the objective argument (the `test/test_utility_solver.jl`
# probe convention).
new_solve_allocs(obj, h::Float64)::Int = @allocated GN.best_response_1d(obj, h)

legacy_solve_allocs(obj, h::Float64)::Int = @allocated legacy_solve(obj, h)

mbr_allocs(args)::Int = @allocated GN.mutual_best_response(args...)

mbr_legacy_allocs(args)::Int = @allocated mbr_legacy(args...)

"""
    allocation_benchmark()

Zero-allocation results of both solver paths (the `ADR-0022`
discipline): the maximum allocated bytes per call of the specialized
solve and the legacy expression over every spec's solve-level matrix
cells (both roles, all four starts), plus one `mutual_best_response`
call per path. Expected zero everywhere.
"""
function allocation_benchmark()
    println()
    println("allocations (max bytes per call over each spec's matrix cells; 0 expected)")
    println(rpad("spec", 16) * rpad("new", 10) * "legacy")
    for (spec_name, spec) in SPECS
        max_new = 0
        max_legacy = 0
        for gender in (GN.Female(), GN.Male()),
                (wage_self, wage_spouse, alpha, conformism) in (
                    (0.9, 1.0, 0.48, 10.0), (1.2, 0.8, 0.5, 0.0),
                )
            config = GN.UtilityConfig(func = spec)
            p0 = GN.AgentPayoffParams{typeof(gender)}(
                wage_self = wage_self, wage_spouse = wage_spouse, alpha = alpha,
                conformism = conformism, N_h = 0.36, N_theta = 0.0, N_h_spouse = 0.77,
            )
            partner = GN.AgentPayoffParams{gender isa GN.Female ? GN.Male : GN.Female}(
                wage_self = wage_spouse, wage_spouse = wage_self, alpha = alpha,
                conformism = conformism, N_h = 0.77, N_theta = 0.0, N_h_spouse = 0.36,
            )
            hw_eq, hm_eq = settle_mbr(0.36, 0.77, 0.05, p0, partner, config)
            obj = GN.BestResponseObjective(0.05, hm_eq, p0, config)
            for h_start in (hw_eq, min(hw_eq + 0.002, 1.0), 0.05, 0.95)
                max_new = max(max_new, new_solve_allocs(obj, h_start))
                max_legacy = max(max_legacy, legacy_solve_allocs(obj, h_start))
            end
        end
        println(rpad(spec_name, 16) * rpad(max_new, 10) * string(max_legacy))
    end
    pw = GN.AgentPayoffParams{GN.Female}(
        wage_self = 0.9, wage_spouse = 1.0, alpha = 0.48, conformism = 10.0,
        N_h = 0.36, N_theta = 0.0, N_h_spouse = 0.77,
    )
    pm = GN.AgentPayoffParams{GN.Male}(
        wage_self = 1.0, wage_spouse = 0.9, alpha = 0.45, conformism = 10.0,
        N_h = 0.77, N_theta = 0.0, N_h_spouse = 0.36,
    )
    args = (0.36, 0.77, 0.05, pw, pm, GN.UtilityConfig(func = GN.CES(beta = 0.5)))
    return println(
        "mutual_best_response pair: new ", mbr_allocs(args),
        ", legacy ", mbr_legacy_allocs(args)
    )
end

main()
mbr_benchmark()
fallback_benchmark()
allocation_benchmark()
