"""
    LinAlgApp

Reads a symmetric positive-definite matrix `A` and a vector `b` from standard input and
prints `ln(det A)`, the solution of `A x = b`, the ascending eigenvalues of `A` and the
Frobenius norm of `A`.
"""
module LinAlgApp

using LinearAlgebra

"""
    read_problem(io) -> (A, b)

Parse `n`, then `n×n` matrix entries (row-major), then `n` entries of `b`.
Tokens may be separated by any whitespace.
"""
function read_problem(io::IO)
    tokens = split(read(io, String))
    isempty(tokens) && throw(ArgumentError("empty input"))
    n = parse(Int, tokens[1])
    n >= 1 || throw(ArgumentError("n must be positive, got $n"))
    length(tokens) >= 1 + n * n + n ||
        throw(ArgumentError("expected $(n * n + n) numbers after n, got $(length(tokens) - 1)"))
    A = Matrix{Float64}(undef, n, n)
    k = 2
    for i in 1:n, j in 1:n
        A[i, j] = parse(Float64, tokens[k])
        k += 1
    end
    b = Vector{Float64}(undef, n)
    for i in 1:n
        b[i] = parse(Float64, tokens[k])
        k += 1
    end
    return A, b
end

"""
    analyze(A, b) -> (logdet, x, eigenvalues, frobenius)

Uses a Cholesky factorization when `A` is positive definite, falling back to LU otherwise.
"""
function analyze(A::Matrix{Float64}, b::Vector{Float64})
    S = Symmetric((A .+ A') ./ 2)
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
    return ld, x, sort!(λ), norm(A)
end

function print_vector(io::IO, v::AbstractVector{Float64})
    for (i, x) in enumerate(v)
        i > 1 && print(io, ' ')
        print(io, x)
    end
    println(io)
    return nothing
end

function run(input::IO, output::IO)
    A, b = read_problem(input)
    ld, x, λ, fro = analyze(A, b)
    buf = IOBuffer()
    println(buf, ld)
    print_vector(buf, x)
    print_vector(buf, λ)
    println(buf, fro)
    write(output, take!(buf))
    return nothing
end

function main(args::Vector{String})
    run(stdin, stdout)
    return 0
end

end # module
