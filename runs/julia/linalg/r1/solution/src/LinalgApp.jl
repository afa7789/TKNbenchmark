"""
    LinalgApp

Dense linear algebra on a symmetric positive-definite matrix read from standard input:
log-determinant, linear solve, eigenvalues and Frobenius norm.
"""
module LinalgApp

using LinearAlgebra
using Printf

export LinalgResult, analyze, parse_input, write_result, main

const MAX_N = 300

"""Results of analysing an SPD system `A x = b`."""
struct LinalgResult
    logdet::Float64
    x::Vector{Float64}
    eigenvalues::Vector{Float64}
    frobenius::Float64
end

"""
    parse_input(text) -> (A, b)

Parse `n`, followed by an `n×n` matrix (row-major) and a length-`n` vector.
Tokens may be separated by any whitespace (commas are tolerated as well).
"""
function parse_input(text::AbstractString)
    tokens = split(text, (' ', '\t', '\n', '\r', ','); keepempty=false)
    isempty(tokens) && throw(ArgumentError("empty input"))
    n = parse(Int, tokens[1])
    1 <= n <= MAX_N || throw(ArgumentError("n must be in 1:$MAX_N, got $n"))
    needed = 1 + n * n + n
    length(tokens) >= needed ||
        throw(ArgumentError("expected $(needed - 1) numbers after n, got $(length(tokens) - 1)"))

    A = Matrix{Float64}(undef, n, n)
    k = 2
    @inbounds for i in 1:n, j in 1:n
        A[i, j] = parse(Float64, tokens[k])
        k += 1
    end
    b = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        b[i] = parse(Float64, tokens[k])
        k += 1
    end
    return A, b
end

"""
    analyze(A, b) -> LinalgResult

Compute `ln(det A)`, the solution of `A x = b`, the ascending eigenvalues of `A`
and its Frobenius norm. A Cholesky factorisation is used; should `A` turn out not
to be numerically positive definite, a pivoted LU factorisation is used instead.
"""
function analyze(A::AbstractMatrix{<:Real}, b::AbstractVector{<:Real})
    S = Symmetric(Matrix{Float64}(A), :U)
    F = cholesky(S; check=false)
    fact = issuccess(F) ? F : lu(Matrix(S))
    ld = logdet(fact)
    x = fact \ Vector{Float64}(b)
    λ = sort!(eigvals(S))
    return LinalgResult(ld, x, λ, norm(A))
end

format_number(v::Float64) = @sprintf("%.15g", v)

function write_numbers(io::IO, values)
    join(io, (format_number(v) for v in values), ' ')
    println(io)
end

"""Write the four output lines for `r` to `io`."""
function write_result(io::IO, r::LinalgResult)
    println(io, format_number(r.logdet))
    write_numbers(io, r.x)
    write_numbers(io, r.eigenvalues)
    println(io, format_number(r.frobenius))
end

function main(input::IO=stdin, output::IO=stdout)
    A, b = parse_input(read(input, String))
    buf = IOBuffer()
    write_result(buf, analyze(A, b))
    write(output, take!(buf))
    return 0
end

end # module
