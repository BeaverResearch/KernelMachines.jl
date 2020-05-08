struct KernelRegression{S, T, N}
    X::S
    C::T
    rgs::NTuple{N, UnitRange{Int}}
    in::Int
    out::Int
end

function KernelMachine(kr::KernelRegression)
    rgs = kr.rgs
    Xs = map(front(rgs)) do rg
        X = kr.X
        isnothing(X) ? nothing : X[rg, :]
    end
    dim = last(first(rgs))
    Cs = map(rg -> kr.C[rg .- dim, :], tail(rgs))
    layers = map(KernelLayer, Xs, Cs)
    return KernelMachine(layers)
end

function (kr::KernelRegression)(input)
    km = KernelMachine(kr)
    inputs = map(rg -> input[rg, :], kr.rgs)
    return vcat(km(inputs)...)
end
    
function KernelRegression(kr::KernelRegression, R)
    KernelRegression(R, kr.C, kr.rgs, kr.in, kr.out)
end

function ranges(dims)
    foldl(dims, init=()) do tup, dim
        l = isempty(tup) ? 0 : last(last(tup))
        (tup..., l+1:l+dim)
    end
end

function fit(X, Y, args...; dims, cost, kwargs...)
    s1, s2 = size(X)
    out = size(Y, 1)
    M = fill!(similar(X, sum(dims), s2), 0)
    M[1:s1, :] .= X
    rgs = ranges(dims)
    Ms = map(rg -> M[rg, :], rgs)
    C = similar(M, size(M, 1) - first(dims), size(M, 2))
    C .= glorot_uniform(size(C)...)
    func = function (c)
        kr = KernelRegression(nothing, c, rgs, s1, out)
        km = KernelMachine(kr)
        res = km(Ms)
        fkm = KernelMachine(km, res)
        R = vcat(res...)
        err = mean(abs2, R[end+1-size(Y, 1):end, :] - Y)
        return err + cost * dot(fkm, fkm)
    end
    func! = function (G, x)
        g, = gradient(func, x)
        copyto!(G, g)
    end
    res = optimize(func, func!, C, args...; kwargs...)
    kr_opt = KernelRegression(nothing, minimizer(res), rgs, s1, out)
    return KernelRegression(kr_opt, kr_opt(M))
end

function predict(kr::KernelRegression, X)
    t1 = last(last(kr.rgs))
    s1, s2 = size(X)
    zs = zero(similar(X, t1-s1, s2))
    R = kr(vcat(X, zs))
    return R[end+1-kr.out:end, :]
end