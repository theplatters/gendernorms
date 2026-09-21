# Tests for the in-repo Brent maximizer `maximize_1d` (unseeded and seeded
# variants over the `_brent_maximize` core) and the seeded `best_response_1d`
# in `src/resources/utility_functions.jl` (see `MDR-0002` and `MDR-0005`).
# The suite pins analytic maximizers, the non-finite-sample guards (including
# the parabolic-fit regression guard), the `max_iter` cap, the seeded
# early-return and window-fallback paths, and the zero-allocation contract.

using GenderNorms
using Test

const GN = GenderNorms

@testset "maximize_1d finds analytic maximizers" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    quartic(x) = 1.0 - (x - 0.3)^4
    tol = 1.0e-4

    @test abs(GN.maximize_1d(quad, 0.0, 1.0, tol) - 0.7) <= tol
    @test abs(GN.maximize_1d(quartic, 0.0, 1.0, tol) - 0.3) <= tol
end

@testset "maximize_1d finds a feasible band" begin
    band(x) = (0.2 <= x <= 0.8) ? x : -Inf

    x = GN.maximize_1d(band, 0.0, 1.0, 1.0e-4)

    @test 0.2 <= x <= 0.8
    @test isfinite(band(x))
    @test x ≈ 0.8 atol = 1.0e-3
end

@testset "maximize_1d returns NaN cheaply when nothing is finite" begin
    # Regression guard for the parabolic-fit guard: with no finite sample the
    # unguarded interpolation produces NaN steps and crawls for `max_iter`
    # iterations instead of shrinking the bracket.
    n = Ref(0)
    nothing_finite(x) = (n[] += 1; -Inf)

    @test isnan(GN.maximize_1d(nothing_finite, 0.0, 1.0, 1.0e-4))
    @test n[] <= 30
    @test isnan(GN.maximize_1d(x -> NaN, 0.0, 1.0, 1.0e-4))
end

@testset "maximize_1d respects the max_iter cap" begin
    n = Ref(0)
    hard(x) = (n[] += 1; sin(50.0 * x))

    x = GN.maximize_1d(hard, 0.0, 1.0, 1.0e-4; max_iter = 10)

    # One initial plus at most `max_iter` Brent samples plus the two
    # bracket endpoints, which are evaluated as candidates.
    @test n[] <= 13
    @test isfinite(x)
    @test 0.0 <= x <= 1.0
end

@testset "seeded maximize_1d returns the seed at the optimum" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    n = Ref(0)
    counted(x) = (n[] += 1; quad(x))

    x = GN.maximize_1d(counted, 0.0, 1.0, 0.7, 0.05, 1.0e-4)

    @test x == 0.7
    @test n[] <= 6
end

@testset "seeded maximize_1d finds an optimum inside the window" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2

    x = GN.maximize_1d(quad, 0.0, 1.0, 0.68, 0.05, 1.0e-4)

    @test abs(x - 0.7) <= 1.0e-4
end

@testset "seeded maximize_1d falls back outside the window" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    tol = 1.0e-4

    unseeded = GN.maximize_1d(quad, 0.0, 1.0, tol)

    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 0.1, 0.05, tol) - unseeded) <= tol
    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 0.0, 0.05, tol) - 0.7) <= tol
    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 1.0, 0.05, tol) - 0.7) <= tol
end

@testset "seeded maximize_1d returns NaN when nothing is finite" begin
    @test isnan(GN.maximize_1d(x -> -Inf, 0.0, 1.0, 0.5, 0.05, 1.0e-4))
end

@testset "maximize_1d allocates nothing" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    GN.maximize_1d(quad, 0.0, 1.0, 1.0e-4)
    GN.maximize_1d(quad, 0.0, 1.0, 0.5, 0.05, 1.0e-4)

    @test @allocated(GN.maximize_1d(quad, 0.0, 1.0, 1.0e-4)) == 0
    @test @allocated(GN.maximize_1d(quad, 0.0, 1.0, 0.5, 0.05, 1.0e-4)) == 0
end
