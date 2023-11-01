export extremevaltheory_dims_persistences, extremevaltheory_dims, extremevaltheory_dim
export extremevaltheory_local_dim_persistence
export extremal_index_sueveges
using Distances: euclidean
using Statistics: mean, quantile, var
import ProgressMeter

# These files define the core types for block maxima or exceedances
# as well as extend the central low-level computational method
# `extremevaltheory_local_dim_persistence(logdist::Vector, p::ExtremesExtractionType)`
include("gpd.jl")
include("gev.jl")

# Central function
"""
    extremevaltheory_dims_persistences(x::AbstractStateSpaceSet, p; kwargs...)

Return the local dimensions `Δloc` and the persistences `θloc` for each point in the
given set. The type of `p` tells the function which approach to use when computing the
dimension, see [`BlockMaxima`](@ref) and [`Exceedances`](@ref). Providing `p::Real`
defaults to using the exceedances approach. The exceedances approach follows the
estimation done via extreme value theory [Lucarini2016](@cite).
The computation is parallelized to available threads (`Threads.nthreads()`).

See also [`extremevaltheory_gpdfit_pvalues`](@ref) for obtaining confidence on the results.

## Keyword arguments

- `show_progress = true`: displays a progress bar.
- `compute_persistence = true:` whether to aso compute local persistences
  `θloc` (also called extremal index). If `false`, `θloc` are `NaN`s.

## Description

For each state space point ``\\mathbf{x}_i`` in `X` we compute
``g_i = -\\log(||\\mathbf{x}_i - \\mathbf{x}_j|| ) \\; \\forall j = 1, \\ldots, N`` with
``||\\cdot||`` the Euclidean distance. Next, we choose an extreme quantile probability
``p`` (e.g., 0.99) for the distribution of ``g_i``. We compute ``g_p`` as the ``p``-th
quantile of ``g_i``. Then, we collect the exceedances of ``g_i``, defined as
``E_i = \\{ g_i - g_p: g_i \\ge g_p \\}``, i.e., all values of ``g_i`` larger or equal to
``g_p``, also shifted by ``g_p``. There are in total ``n = N(1-q)`` values in ``E_i``.
According to extreme value theory, in the limit ``N \\to \\infty`` the values ``E_i``
follow a two-parameter Generalized Pareto Distribution (GPD) with parameters
``\\sigma,\\xi`` (the third parameter ``\\mu`` of the GPD is zero due to the
positive-definite construction of ``E``). Within this extreme value theory approach,
the local dimension ``\\Delta^{(E)}_i`` assigned to state space point ``\\textbf{x}_i``
is given by the inverse of the ``\\sigma`` parameter of the
GPD fit to the data[^Lucarini2012], ``\\Delta^{(E)}_i = 1/\\sigma``.
``\\sigma`` is estimated according to the `estimator` keyword.

A more precise description of this process is given in the review paper [Datseris2023](@cite).
"""
function extremevaltheory_dims_persistences(X::AbstractStateSpaceSet, type;
        show_progress = envprog(), kw...
    )
    # The algorithm in the end of the day loops over points in `X`
    # and applies the local algorithm.
    N = length(X)
    Δloc = zeros(eltype(X), N)
    θloc = copy(Δloc)
    progress = ProgressMeter.Progress(
        N; desc = "Extreme value theory dim: ", enabled = show_progress
    )
    logdists = [copy(Δloc) for _ in 1:Threads.nthreads()]
    Threads.@threads for j in eachindex(X)
        logdist = logdists[Threads.threadid()]
        logdist = map(x -> -log(euclidean(x, X[j])), vec(X))
        deleteat!(logdist, j)
        D, θ = extremevaltheory_local_dim_persistence(logdist, type; kw...)
        Δloc[j] = D
        θloc[j] = θ
        ProgressMeter.next!(progress)
    end
    return Δloc, θloc
end


"""
    extremevaltheory_dim(X::StateSpaceSet, p; kwargs...) → Δ

Convenience syntax that returns the mean of the local dimensions of
[`extremevaltheory_dims_persistences`](@ref) with `X, p`.
"""
function extremevaltheory_dim(X, p; kw...)
    Δloc, θloc = extremevaltheory_dims_persistences(X, p; compute_persistence = false, kw...)
    return mean(Δloc)
end

"""
    extremevaltheory_dims(X::StateSpaceSet, p; kwargs...) → Δloc

Convenience syntax that returns the local dimensions of
[`extremevaltheory_dims_persistences`](@ref) with `X, p`.
"""
function extremevaltheory_dims(X, p; kw...)
    Δloc, θloc = extremevaltheory_dims_persistences(X, p; compute_persistence = false, kw...)
    return Δloc
end

# convenience function
"""
    extremevaltheory_local_dim_persistence(X::StateSpaceSet, ζ, p; kw...)

Return the local values `Δ, θ` of the fractal dimension and persistence of `X` around a
state space point `ζ`. `p` and `kw` are as in [`extremevaltheory_dims_persistences`](@ref).
"""
function extremevaltheory_local_dim_persistence(
        X::AbstractStateSpaceSet, ζ::AbstractVector, p; kw...
    )
    logdist = map(x -> -log(euclidean(x, ζ)), X)
    Δ, θ = extremevaltheory_local_dim_persistence(logdist, p; kw...)
    return Δ, θ
end

# This is the core function that estimators need to extend
# The current function is just the deprecation for `p::Real`
function extremevaltheory_local_dim_persistence(X::AbstractStateSpaceSet, p::Real;
        estimator = :exp, kw...
    )
    @warn "Using `p::Real` is deprecated. Explicitly create `Exceedances(p, estimator)`."
    type = Exceedances(p, estimator)
    extremevaltheory_local_dim_persistence(X, type; kw...)
end


# Generic function for extremal index; it doesn't depend on estimator
"""
    extremal_index_sueveges(y::AbstractVector, p)

Compute the extremal index θ of `y` through the Süveges formula for quantile probability `p`,
using the algorithm of [Sveges2007](@cite).
"""
function extremal_index_sueveges(y::AbstractVector, p::Real,
        # These arguments are given for performance optim; not part of public API
        thresh::Real = quantile(y, p)
    )
    p = 1 - p
    Li = findall(x -> x > thresh, y)
    Ti = diff(Li)
    Si = Ti .- 1
    Nc = length(findall(x->x>0, Si))
    N = length(Ti)
    θ = (sum(p.*Si)+N+Nc - sqrt( (sum(p.*Si) +N+Nc).^2 - 8*Nc*sum(p.*Si)) )./(2*sum(p.*Si))
    return θ
end