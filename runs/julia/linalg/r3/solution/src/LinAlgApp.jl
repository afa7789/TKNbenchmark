"""
    LinAlgApp

Dense linear algebra on a symmetric positive-definite matrix read from standard input.
See SPEC.md for the input and output formats.
"""
module LinAlgApp

using LinearAlgebra

export Problem, Report, parse_problem, analyze, write_report, main

"""A symmetric matrix `A` and right-hand side `b`."""
struct Problem
    A::Matrix{Float64}
    b::Vector{Float64}
end

"""Results of the analysis of a [`Problem`](@ref)."""
struct Report
    logdet::Float64
    x::Vector{Float64}
    eigenvalues::Vector{Float64}
    frobenius::Float64
end

"""
    parse_problem(text) -> Problem

Parse `n`, followed by `n×n` matrix entries in row-major order and `n` vector entries.
Tokens may be separated by any whitespace.
"""
function parse_problem(text::AbstractString)
    tokens = split(text)
    isempty(tokens) && throw(ArgumentError("empty input"))
    n = parse(Int, tokens[1])
    n >= 1 || throw(ArgumentError("matrix dimension must be positive, got $n"))
    expected = 1 + n * n + n
    length(tokens) >= expected ||
        throw(ArgumentError("expected $(expected - 1) numbers after n, got $(length(tokens) - 1)"))

    A = Matrix{Float64}(undef, n, n)
    k = 2
    for i in 1:n, j in 1:n
        A[i, j] = parse(Float64, tokens[k])
        k += 1
    end
    b = [parse(Float64, tokens[k + i - 1]) for i in 1:n]
    return Problem(A, b)
end

"""
    analyze(p::Problem) -> Report

Compute `ln(det A)`, the solution of `A x = b`, the ascending eigenvalues and the Frobenius norm.
A Cholesky factorization is used; if it fails (the matrix is not numerically positive
definite) an LU factorization is used instead.
"""
function analyze(p::Problem)
    S = Symmetric(p.A)
    F = cholesky(S; check = false)
    if issuccess(F)
        ld = logdet(F)
        x = F \ p.b
    else
        L = lu(p.A)
        ld = first(logabsdet(L))
        x = L \ p.b
    end
    λ = eigvals(S)           # returned in ascending order
    return Report(ld, x, λ, norm(p.A))
end

function write_numbers(io::IO, v::AbstractVector{<:Real})
    join(io, v, ' ')
    println(io)
end

"""Write the four result lines of `r` to `io`."""
function write_report(io::IO, r::Report)
    println(io, r.logdet)
    write_numbers(io, r.x)
    write_numbers(io, r.eigenvalues)
    println(io, r.frobenius)
    return nothing
end

function main(input::IO = stdin, output::IO = stdout)
    report = analyze(parse_problem(read(input, String)))
    buf = IOBuffer()
    write_report(buf, report)
    write(output, take!(buf))
    flush(output)
    return 0
end

end # module
