"""
    LinReg

Ordinary least-squares regression read from standard input.

Input: a header line `n k`, then `n` rows of `k` feature values followed by the
response. Output: the intercept, the `k` slopes and the coefficient of
determination, one per line.
"""
module LinReg

using LinearAlgebra

export fit_ols, parse_input, main

const POW10 = ntuple(i -> 10.0^(i - 1), 23)   # exactly representable: 1e0 … 1e22
const MAX_EXACT = Int64(2)^53

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r') || b == UInt8('\t')
@inline isdigit_byte(b::UInt8) = UInt8('0') <= b <= UInt8('9')

"""
    skip_space(buf, pos) -> pos

Advance past whitespace; returns the index of the next non-space byte (or `length(buf) + 1`).
"""
@inline function skip_space(buf::Vector{UInt8}, pos::Int)
    n = length(buf)
    @inbounds while pos <= n && isspace_byte(buf[pos])
        pos += 1
    end
    return pos
end

"""
    token_end(buf, pos) -> pos

Index one past the end of the token starting at `pos`.
"""
@inline function token_end(buf::Vector{UInt8}, pos::Int)
    n = length(buf)
    @inbounds while pos <= n && !isspace_byte(buf[pos])
        pos += 1
    end
    return pos
end

function slow_parse(buf::Vector{UInt8}, start::Int, stop::Int)
    s = String(buf[start:(stop - 1)])
    x = tryparse(Float64, s)
    x === nothing && throw(ArgumentError("invalid number: $(repr(s))"))
    return x
end

"""
    parse_float(buf, pos) -> (value, nextpos)

Parse a decimal floating-point token starting at `pos`. The common case (at most
15–16 significant digits and a small exponent) is handled exactly with a single
correctly rounded multiplication or division; anything else falls back to
`Base.parse`.
"""
@inline function parse_float(buf::Vector{UInt8}, pos::Int)
    start = pos
    stop = token_end(buf, pos)
    stop == start && throw(ArgumentError("unexpected end of input"))
    neg = false
    @inbounds b = buf[pos]
    if b == UInt8('-') || b == UInt8('+')
        neg = b == UInt8('-')
        pos += 1
    end
    mant = Int64(0)
    ndigits = 0
    scale = 0
    any_digit = false
    @inbounds while pos < stop && isdigit_byte(buf[pos])
        mant = 10mant + (buf[pos] - UInt8('0'))
        ndigits += mant != 0
        any_digit = true
        pos += 1
    end
    @inbounds if pos < stop && buf[pos] == UInt8('.')
        pos += 1
        while pos < stop && isdigit_byte(buf[pos])
            mant = 10mant + (buf[pos] - UInt8('0'))
            ndigits += mant != 0
            scale -= 1
            any_digit = true
            pos += 1
        end
    end
    @inbounds if pos < stop && (buf[pos] == UInt8('e') || buf[pos] == UInt8('E'))
        pos += 1
        eneg = false
        if pos < stop && (buf[pos] == UInt8('-') || buf[pos] == UInt8('+'))
            eneg = buf[pos] == UInt8('-')
            pos += 1
        end
        e = 0
        edigits = 0
        while pos < stop && isdigit_byte(buf[pos]) && edigits < 6
            e = 10e + (buf[pos] - UInt8('0'))
            edigits += 1
            pos += 1
        end
        edigits == 0 && return slow_parse(buf, start, stop), stop
        scale += eneg ? -e : e
    end
    if pos != stop || !any_digit || ndigits > 18 || mant > MAX_EXACT || abs(scale) > 22
        return slow_parse(buf, start, stop), stop
    end
    x = Float64(mant)
    x = scale >= 0 ? x * POW10[scale + 1] : x / POW10[1 - scale]
    return (neg ? -x : x), stop
end

function parse_int(buf::Vector{UInt8}, pos::Int)
    pos = skip_space(buf, pos)
    stop = token_end(buf, pos)
    v = tryparse(Int, String(buf[pos:(stop - 1)]))
    v === nothing && throw(ArgumentError("expected an integer in the header"))
    return v, stop
end

"""
    parse_input(buf) -> (X, y)

Parse the whole input. `X` is the `n × k` feature matrix and `y` the response.
"""
function parse_input(buf::Vector{UInt8})
    n, pos = parse_int(buf, 1)
    k, pos = parse_int(buf, pos)
    n >= 1 && k >= 1 || throw(ArgumentError("invalid header: n=$n k=$k"))
    X = Matrix{Float64}(undef, n, k)
    y = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        for j in 1:k
            X[i, j], pos = parse_float(buf, skip_space(buf, pos))
        end
        y[i], pos = parse_float(buf, skip_space(buf, pos))
    end
    return X, y
end

"""
    fit_ols(X, y) -> (coef, r2)

Least-squares fit of `y ≈ b0 + X*b`. Returns `coef = [b0; b]` and R².
Columns are centred before a Householder QR solve, which keeps the intercept
out of the conditioning and avoids forming the normal equations. The residual
sum of squares is read off the trailing part of `Qᵀy`. `X` and `y` are
destroyed.
"""
function fit_ols(X::Matrix{Float64}, y::Vector{Float64})
    n, k = size(X)
    xbar = vec(sum(X; dims = 1)) ./ n
    ybar = sum(y) / n
    X .-= xbar'
    y .-= ybar
    sstot = dot(y, y)
    F = qr!(X)
    qty = lmul!(F.Q', y)       # y is overwritten with Qᵀ(y − ȳ)
    b = UpperTriangular(F.R) \ qty[1:k]
    ssres = sum(abs2, @view qty[(k + 1):n])
    b0 = ybar - dot(xbar, b)
    return vcat(b0, b), 1 - ssres / sstot
end

function main(input::IO = stdin, output::IO = stdout)
    X, y = parse_input(read(input))
    coef, r2 = fit_ols(X, y)
    io = IOBuffer()
    for c in coef
        println(io, c)
    end
    println(io, r2)
    write(output, take!(io))
    return 0
end

# Exercise the full pipeline while precompiling so the native code is cached.
if ccall(:jl_generating_output, Cint, ()) == 1
    main(IOBuffer("5 2\n1 2 9.5\n2 1 8.1\n3 4 19.2\n4 3 17.9\n5 5 2.54e1\n"), devnull)
end

end # module
