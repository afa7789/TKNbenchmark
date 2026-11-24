# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm of an SPD matrix.
module LinalgApp

using LinearAlgebra
using Printf

"""
    read_input(io) -> (A, b)

Parse `n`, the `n×n` matrix `A` (row-major) and the vector `b` from whitespace-separated tokens.
"""
function read_input(io::IO)
    tokens = split(read(io, String))
    isempty(tokens) && error("empty input")
    n = parse(Int, tokens[1])
    n >= 1 || error("n must be positive, got $n")
    length(tokens) >= 1 + n * n + n || error("expected $(n * n + n) numbers after n")
    A = Matrix{Float64}(undef, n, n)
    k = 1
    for i in 1:n, j in 1:n
        k += 1
        A[i, j] = parse(Float64, tokens[k])
    end
    b = Vector{Float64}(undef, n)
    for i in 1:n
        k += 1
        b[i] = parse(Float64, tokens[k])
    end
    return A, b
end

"""
    analyze(A, b) -> (logdet, x, eigenvalues, frobenius)

Uses a Cholesky factorization when `A` is numerically positive definite, falling back to LU otherwise.
"""
function analyze(A::Matrix{Float64}, b::Vector{Float64})
    S = Symmetric(A, :U)
    F = cholesky(S; check = false)
    if issuccess(F)
        ld = logdet(F)
        x = F \ b
    else
        L = lu(A)
        ld = first(logabsdet(L))
        x = L \ b
    end
    λ = eigvals(S)
    sort!(λ)
    return ld, x, λ, norm(A)
end

fmt(v::Real) = @sprintf("%.15g", v)

function write_output(io::IO, ld, x, λ, fro)
    println(io, fmt(ld))
    join(io, (fmt(v) for v in x), ' ')
    println(io)
    join(io, (fmt(v) for v in λ), ' ')
    println(io)
    println(io, fmt(fro))
    return nothing
end

function main(input::IO = stdin, output::IO = stdout)
    A, b = read_input(input)
    write_output(output, analyze(A, b)...)
    return 0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(LinalgApp.main())
end
