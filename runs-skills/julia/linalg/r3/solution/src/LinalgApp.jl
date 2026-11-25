"""
    LinalgApp

Reads a symmetric positive-definite matrix `A` and a vector `b` from standard input and
prints `ln(det A)`, the solution of `A x = b`, the ascending eigenvalues of `A` and the
Frobenius norm of `A`.
"""
module LinalgApp

using LinearAlgebra

export LinalgResult, analyze, read_problem, write_result

struct LinalgResult
    logdet::Float64
    solution::Vector{Float64}
    eigenvalues::Vector{Float64}
    frobenius::Float64
end

"""
    read_problem(io) -> (A, b)

Parse `n`, the `n×n` matrix and the length-`n` right-hand side. Tokens may be separated by
any whitespace (or commas).
"""
function read_problem(io::IO)
    tokens = split(read(io, String), (' ', '\t', '\n', '\r', ','); keepempty = false)
    isempty(tokens) && throw(ArgumentError("empty input"))
    n = parse(Int, tokens[1])
    n ≥ 1 || throw(ArgumentError("n must be positive, got $n"))
    needed = 1 + n * n + n
    length(tokens) ≥ needed ||
        throw(ArgumentError("expected $(needed - 1) numbers after n, got $(length(tokens) - 1)"))
    A = Matrix{Float64}(undef, n, n)
    k = 2
    for i in 1:n, j in 1:n          # row-major input
        A[i, j] = parse(Float64, tokens[k])
        k += 1
    end
    b = [parse(Float64, tokens[k + i - 1]) for i in 1:n]
    return A, b
end

"""
    analyze(A, b) -> LinalgResult

Compute log-determinant, solution, eigenvalues and Frobenius norm. A Cholesky
factorization is used; if it fails numerically, an LU factorization is used instead.
"""
function analyze(A::AbstractMatrix{Float64}, b::AbstractVector{Float64})
    S = Symmetric((A .+ A') ./ 2)
    F = cholesky(S; check = false)
    if issuccess(F)
        ld = logdet(F)
        x = F \ b
    else
        L = lu(Matrix(S))
        ld = first(logabsdet(L))
        x = L \ b
    end
    λ = eigvals(S)          # LAPACK returns them in ascending order
    return LinalgResult(ld, x, sort!(λ), norm(A))
end

function write_numbers(io::IO, xs::AbstractVector{Float64})
    join(io, xs, ' ')
    println(io)
    return nothing
end

function write_result(io::IO, r::LinalgResult)
    println(io, r.logdet)
    write_numbers(io, r.solution)
    write_numbers(io, r.eigenvalues)
    println(io, r.frobenius)
    return nothing
end

function (@main)(::Vector{String})::Cint
    A, b = read_problem(stdin)
    buf = IOBuffer()
    write_result(buf, analyze(A, b))
    write(stdout, take!(buf))
    flush(stdout)
    return 0
end

end # module
