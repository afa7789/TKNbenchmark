# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm
# of a symmetric positive-definite matrix read from standard input.

module LinalgApp

using LinearAlgebra

"""
    read_problem(io) -> (A, b)

Parse `n`, an `n×n` matrix and a length-`n` vector from whitespace-separated tokens.
"""
function read_problem(io::IO)
    tokens = split(read(io, String))
    isempty(tokens) && throw(ArgumentError("empty input"))
    n = parse(Int, first(tokens))
    n ≥ 1 || throw(ArgumentError("n must be positive, got $n"))
    length(tokens) ≥ 1 + n * n + n ||
        throw(ArgumentError("expected $(n * n + n) numbers after n, got $(length(tokens) - 1)"))
    vals = parse.(Float64, @view tokens[2:(1 + n * n + n)])
    A = permutedims(reshape(vals[1:(n * n)], n, n))   # input is row-major
    b = vals[(n * n + 1):end]
    return A, b
end

"""
    analyze(A, b) -> (logdet, x, eigenvalues, frobenius)

Use a Cholesky factorization when `A` is positive definite, falling back to LU otherwise.
"""
function analyze(A::Matrix{Float64}, b::Vector{Float64})
    S = Symmetric(A)
    F = cholesky(S; check = false)
    if issuccess(F)
        ld = logdet(F)
        x = F \ b
    else
        L = lu(A)
        ld = first(logabsdet(L))
        x = L \ b
    end
    λ = eigvals(S)   # returned in ascending order
    return ld, x, λ, norm(A)
end

function print_vector(io::IO, v::AbstractVector{Float64})
    join(io, v, ' ')
    println(io)
    return nothing
end

function main(io_in::IO = stdin, io_out::IO = stdout)
    A, b = read_problem(io_in)
    ld, x, λ, fro = analyze(A, b)
    buf = IOBuffer()
    println(buf, ld)
    print_vector(buf, x)
    print_vector(buf, λ)
    println(buf, fro)
    write(io_out, take!(buf))
    flush(io_out)
    return 0
end

end # module

exit(LinalgApp.main())
