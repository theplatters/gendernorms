# Generic 1-D bounded maximization core shared by the household solvers:
# `_brent_maximize` and `maximize_1d`, the maximization variant of the
# standard Brent minimization (Numerical Recipes section 10.2). It
# replaces the `Optim.Brent` call of the first port (see `MDR-0002` and
# `MDR-0012`) and provides the seeded bounded refinement core of the
# production transfer search (`ADR-0021`). No model semantics, domain
# constants, or types live here: the labour best response
# (`src/optim/labour_optimization.jl`) and the transfer search
# (`src/optim/transfer_optimization.jl`) build on this core. Moved
# unchanged from `src/resources/utility_functions.jl` by `ADR-0028`.

"""
    _brent_maximize(f, a, b, tol, max_iter)

Core Brent search behind `maximize_1d`: the maximization variant of the
standard Brent minimization (Numerical Recipes section 10.2), golden section
with parabolic interpolation over the bracket `[a, b]` with the absolute
argument tolerance `tol`. Non-finite samples never enter the parabolic fit;
the best finite sample is tracked across all evaluations. Returns the
`(best_x, best_value)` pair with `best_value == -Inf` when no sample was
finite.
"""
function _brent_maximize(f::F, a::Float64, b::Float64, tol::Float64, max_iter::Int) where {F}
    return _brent_maximize(f, a, b, tol, max_iter, a + 0.3819660112501051 * (b - a))
end

"""
    _brent_maximize(f, a, b, tol, max_iter, x0)

Seeded bounded Brent core of `ADR-0021`, initialized at `x0` in `[a, b]`.
Return the best finite `(point, value)`; non-finite values remain worst.
The original unseeded variant retains its golden-section initialization.
"""
function _brent_maximize(
        f::F, a::Float64, b::Float64, tol::Float64, max_iter::Int, x0::Float64
    ) where {F}
    a <= x0 <= b || throw(ArgumentError("Brent seed must lie in the bracket"))
    cgold::Float64 = 0.3819660112501051
    lo::Float64 = a
    hi::Float64 = b
    x::Float64 = x0
    w::Float64 = x
    v::Float64 = x
    fx_raw::Float64 = f(x)
    fx::Float64 = isfinite(fx_raw) ? -fx_raw : Inf
    fw::Float64 = fx
    fv::Float64 = fx
    best_x::Float64 = x
    best_value::Float64 = fx_raw
    if !isfinite(best_value)
        best_x = NaN
        best_value = -Inf
    end
    e::Float64 = 0.0
    d::Float64 = 0.0
    tol2::Float64 = 2.0 * tol
    iter::Int = 0
    while iter < max_iter
        iter += 1
        xm::Float64 = 0.5 * (lo + hi)
        if abs(x - xm) <= tol2 - 0.5 * (hi - lo)
            break
        end
        take_parabolic::Bool = false
        p::Float64 = 0.0
        q::Float64 = 0.0
        etemp::Float64 = e
        if abs(etemp) > tol && isfinite(fx) && isfinite(fw) && isfinite(fv) && x != w && x != v
            e = d
            r::Float64 = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = 2.0 * (q - r)
            if q != 0.0
                if q > 0.0
                    p = -p
                end
                q = abs(q)
                if abs(p) < abs(0.5 * q * etemp) && p > q * (lo - x) && p < q * (hi - x)
                    take_parabolic = true
                    d = p / q
                    u_try::Float64 = x + d
                    if u_try - lo < tol2 || hi - u_try < tol2
                        d = xm >= x ? tol : -tol
                    end
                end
            end
        end
        if !take_parabolic
            e = x >= xm ? lo - x : hi - x
            d = cgold * e
        end
        u::Float64 = x + (abs(d) >= tol ? d : (d >= 0.0 ? tol : -tol))
        if u < a
            u = a
        elseif u > b
            u = b
        end
        fu_raw::Float64 = f(u)
        fu::Float64 = isfinite(fu_raw) ? -fu_raw : Inf
        if isfinite(fu_raw) && fu_raw > best_value
            best_x = u
            best_value = fu_raw
        end
        if fu <= fx
            if u >= x
                lo = x
            else
                hi = x
            end
            v = w
            fv = fw
            w = x
            fw = fx
            x = u
            fx = fu
        else
            if u < x
                lo = u
            else
                hi = u
            end
            if fu <= fw || w == x
                v = w
                fv = fw
                w = u
                fw = fu
            elseif fu <= fv || v == x || v == w
                v = u
                fv = fu
            end
        end
    end
    return best_x, best_value
end

"""
    maximize_1d(f::F, a::Float64, b::Float64, tol::Float64; max_iter::Int = 64) where {F}

Brent maximization of `f` on the bracket `[a, b]` (precondition `a < b`)
with the absolute argument tolerance `tol`: the maximization variant of the
standard Brent minimization (Numerical Recipes section 10.2), golden section
with parabolic interpolation, replacing the `Optim.Brent` call of the first
port (see `MDR-0002` and `MDR-0012`). Every non-finite objective value (`-Inf`
on infeasible regions, `NaN`) is treated as the worst value and never enters
the parabolic fit; the search is specialized on `F` and allocates nothing.
Arguments are the objective `f`, the bracket endpoints `a` and `b`, the
tolerance `tol`, and the iteration guard `max_iter`. Both bracket endpoints
are evaluated as candidates, so a corner optimum is returned exactly.
Returns the best finite sample, or `NaN` when no sample was finite.
"""
function maximize_1d(f::F, a::Float64, b::Float64, tol::Float64; max_iter::Int = 64) where {F}
    best_x, best_value = _brent_maximize(f, a, b, tol, max_iter)
    fa::Float64 = f(a)
    if isfinite(fa) && fa >= best_value
        best_x = a
        best_value = fa
    end
    fb::Float64 = f(b)
    if isfinite(fb) && fb >= best_value
        best_x = b
        best_value = fb
    end
    return best_x
end

"""
    maximize_1d(f::F, a::Float64, b::Float64, x0::Float64, w::Float64, tol::Float64; max_iter::Int = 64) where {F}

Seeded Brent maximization of `f` over the full bracket `[a, b]`, starting
from the seed `x0` with the window half-width `w` (see `MDR-0002` and
`MDR-0012`). The full bracket is needed because of the fallback below.
Arguments are the objective `f`, the bracket endpoints `a` and `b`, the seed
`x0`, the half-width `w`, the tolerance `tol`, and the iteration guard
`max_iter`. Returns the maximizer: the seed `x0` clamped to `[a, b]` when
`f(x0)` is finite and neither neighbour probe at the resolution `tol` beats
it; otherwise the best finite sample among the seed, the probes, the window
`[max(a, x0 - w), min(b, x0 + w)]`, and the full bracket, where the two
window endpoints are evaluated as candidates so that a maximizer
constrained by the window sits exactly on the edge. Falls back to the full
bracket when that point lies on an interior window edge or the window holds
no finite sample. Returns `NaN` only when neither search found a finite
sample.
"""
function maximize_1d(
        f::F, a::Float64, b::Float64, x0::Float64, w::Float64, tol::Float64;
        max_iter::Int = 64
    ) where {F}
    xs::Float64 = clamp(x0, a, b)
    f0::Float64 = f(xs)
    seed_x::Float64 = NaN
    seed_value::Float64 = -Inf
    if isfinite(f0)
        seed_x = xs
        seed_value = f0
        improves::Bool = false
        if xs - tol >= a
            fm::Float64 = f(xs - tol)
            if isfinite(fm) && fm > seed_value
                seed_x = xs - tol
                seed_value = fm
            end
            if fm > f0
                improves = true
            end
        end
        if xs + tol <= b
            fp::Float64 = f(xs + tol)
            if isfinite(fp) && fp > seed_value
                seed_x = xs + tol
                seed_value = fp
            end
            if fp > f0
                improves = true
            end
        end
        if !improves
            return xs
        end
    end
    wa::Float64 = max(a, xs - w)
    wb::Float64 = min(b, xs + w)
    window_x::Float64 = NaN
    window_value::Float64 = -Inf
    if wa < wb
        window_x, window_value = _brent_maximize(f, wa, wb, tol, max_iter)
    end
    fa::Float64 = f(wa)
    if isfinite(fa) && fa >= window_value
        window_x = wa
        window_value = fa
    end
    fb::Float64 = f(wb)
    if isfinite(fb) && fb >= window_value
        window_x = wb
        window_value = fb
    end
    on_edge::Bool = (window_x == wa && wa != a) || (window_x == wb && wb != b)
    if !isfinite(window_value) || on_edge
        full_x, full_value = _brent_maximize(f, a, b, tol, max_iter)
        best_x::Float64 = window_x
        best_value::Float64 = window_value
        if isfinite(full_value) && full_value > best_value
            best_x = full_x
            best_value = full_value
        end
        if isfinite(seed_value) && seed_value > best_value
            best_x = seed_x
            best_value = seed_value
        end
        if isfinite(best_value)
            return best_x
        end
        return isfinite(full_value) ? full_x : NaN
    end
    if isfinite(seed_value) && seed_value > window_value
        return seed_x
    end
    return window_x
end
