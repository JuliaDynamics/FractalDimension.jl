using FractalDimensions
using Test
using Random: Xoshiro
using DynamicalSystemsBase: Systems, trajectory

test_value = (val, vmin, vmax) -> @test vmin <= val <= vmax

# Convenience syntax going back to the old `quickentropy`
function quickentropy(x, e; q = 1)
    return entropy(Renyi(;q), ValueHistogram(e), x)
end

@testset "analytic sets" begin
    A = Dataset(rand(Xoshiro(1234), 100_000, 2))
    θ = rand(Xoshiro(1234), 100_000).*2π
    B = Dataset(cos.(θ), sin.(θ))
    sizesA = estimate_boxsizes(A)
    sizesB = estimate_boxsizes(B)

    @testset "generalized_dim" begin
        for q in [0, 2, 1, 2.56]
            dA = generalized_dim(A, sizesA; q)
            test_value(dA, 1.8, 2.0)
            dB = generalized_dim(B, sizesB; q)
            test_value(dB, 0.9, 1.1)
        end
    end
    @testset "molteno_dim" begin
        for q in [0, 2, 1, 2.56]
            dA = molteno_dim(A; q)
            test_value(dA, 1.8, 2.0)
            dB = molteno_dim(B; q)
            test_value(dB, 0.9, 1.1)
        end
    end
end

@testset "henon map" begin
    # no matter what we do here, and no matter the `k0` parameter,
    # or the parameters for the molteno,
    # the dimension at q = 1 always turns out slightly larger. Don't know why...
    # Also, the values we get from the Molteno are significantly higher
    # than the ones we get from the standard histograms...
    X = trajectory(Systems.henon(), 100_000; Ttr = 1000)
    sizesX = estimate_boxsizes(X)
    @testset "generalized_dim" begin
        dX = generalized_dim(X, sizesX; q = 0)
        dX1 = generalized_dim(X, sizesX; q = 2.0)
        dX3 = generalized_dim(X, sizesX; q = 4.0)
        test_value(dX, 1.22, 1.26)
        @test dX > dX1 > dX3
        test_value(dX1, 1.1, 1.2)
    end

    @testset "molteno_dim" begin
        probs, εs = molteno_boxing(X; k0 = 6)
        # fig = Figure(); display(fig)
        # ax = Xxis(fig[1,1])
        molt_dim = q -> begin
            dd = entropy.(Ref(Renyi(;q, base = 2)), probs)
            x = -log.(2, εs)
            # scatterlines!(ax, x, dd; label = "q = $q")
            linear_region(x, dd)[2]
        end
        dX = molt_dim(0)
        dX1 = molt_dim(2.0)
        dX3 = molt_dim(4.0)
        # axislegend(ax)
        test_value(dX, 1.22, 1.26)
        @test dX > dX1 > dX3
        test_value(dX3, 1.1, 1.2)
    end
end
