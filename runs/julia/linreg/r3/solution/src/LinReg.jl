"""
    LinReg

Ordinary least-squares regression reading a dense numeric table from stdin.

Input:  `n k` followed by `n` rows of `k` features and a response.
Output: intercept, `k` slopes, and R², one per line.
"""
module LinReg

using LinearAlgebra

export fit_ols, main

# ---------------------------------------------------------------------------
# Tokenising / parsing
# ---------------------------------------------------------------------------

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || (UInt8('\t') <= b <= UInt8('\r'))

"""
    Scanner(buf)

Cursor over a byte buffer that yields whitespace-separated numeric tokens.
"""
mutable struct Scanner
    buf::Vector{UInt8}
    pos::Int
end
Scanner(buf::Vector{UInt8}) = Scanner(buf, 1)

# Exact powers of ten representable as Float64 (10^0 … 10^22).
const POW10 = ntuple(i -> 10.0^(i - 1), 23)

"""
    next_token(s) -> (start, stop)

Advance past whitespace and return the byte range of the next token.
Throws if the input is exhausted.
"""
@inline function next_token(s::Scanner)
    buf, n = s.buf, length(s.buf)
    i = s.pos
    @inbounds while i <= n && isspace_byte(buf[i])
        i += 1
    end
    i > n && throw(ArgumentError("unexpected end of input"))
    start = i
    @inbounds while i <= n && !isspace_byte(buf[i])
        i += 1
    end
    s.pos = i
    return start, i - 1
end

"""
    next_float(s) -> Float64

Parse the next token as a `Float64`. Plain decimals (`[-+]ddd[.ddd]`) whose
mantissa fits in 2^53 and whose scale is ≤ 10^22 are converted exactly with a
single correctly rounded division; anything else falls back to `Base.parse`.
"""
@inline function next_float(s::Scanner)
    start, stop = next_token(s)
    buf = s.buf
    i = start
    neg = false
    @inbounds c = buf[i]
    if c == UInt8('-') || c == UInt8('+')
        neg = c == UInt8('-')
        i += 1
    end
    mant = UInt64(0)
    ndigits = 0
    frac = 0
    seen_dot = false
    ok = i <= stop
    @inbounds while i <= stop
        c = buf[i]
        if UInt8('0') <= c <= UInt8('9')
            mant = mant * 10 + (c - UInt8('0'))
            ndigits += 1
            frac += seen_dot
        elseif c == UInt8('.') && !seen_dot
            seen_dot = true
        else
            ok = false
            break
        end
        i += 1
    end
    if ok && ndigits > 0 && ndigits <= 15 && frac <= 22
        v = Float64(mant) / @inbounds(POW10[frac + 1])
        return neg ? -v : v
    end
    return slow_float(buf, start, stop)
end

@noinline function slow_float(buf::Vector{UInt8}, start::Int, stop::Int)
    str = String(buf[start:stop])
    v = tryparse(Float64, str)
    v === nothing && throw(ArgumentError("invalid number: $(repr(str))"))
    return v
end

function next_int(s::Scanner)
    start, stop = next_token(s)
    str = String(s.buf[start:stop])
    v = tryparse(Int, str)
    v === nothing && throw(ArgumentError("invalid integer: $(repr(str))"))
    return v
end

"""
    read_problem(buf) -> (X, y)

Parse the header and data rows into an `n × k` feature matrix and response.
"""
function read_problem(buf::Vector{UInt8})
    s = Scanner(buf)
    n = next_int(s)
    k = next_int(s)
    (k >= 1 && n >= k + 1) || throw(ArgumentError("invalid dimensions n=$n, k=$k"))
    X = Matrix{Float64}(undef, n, k)
    y = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        for j in 1:k
            X[i, j] = next_float(s)
        end
        y[i] = next_float(s)
    end
    return X, y
end

# ---------------------------------------------------------------------------
# Fitting
# ---------------------------------------------------------------------------

"""
    fit_ols(X, y) -> (coef, r2)

Least-squares fit of `y ≈ b0 + X*b`. Returns `coef = [b0; b]` and R².

Columns are centred before a Householder QR solve, which removes the
intercept's influence on conditioning and avoids forming `X'X`.
`X` and `y` are overwritten.
"""
function fit_ols(X::Matrix{Float64}, y::Vector{Float64})
    n, k = size(X)
    xbar = vec(sum(X; dims=1)) ./ n
    ybar = sum(y) / n
    # Second pass with a correction term keeps the means accurate.
    @inbounds for j in 1:k
        μ = xbar[j]
        δ = 0.0
        @simd for i in 1:n
            X[i, j] -= μ
            δ += X[i, j]
        end
        δ /= n
        @simd for i in 1:n
            X[i, j] -= δ
        end
        xbar[j] = μ + δ
    end
    δy = 0.0
    @inbounds @simd for i in 1:n
        y[i] -= ybar
        δy += y[i]
    end
    δy /= n
    y .-= δy
    ybar += δy

    ss_tot = sum(abs2, y)
    F = qr!(X)
    # z = Q'y: the leading k entries give R*b = z[1:k]; the remaining n-k
    # entries are the residual expressed in an orthonormal basis.
    z = lmul!(F.Q', y)
    b = UpperTriangular(F.R) \ z[1:k]
    ss_res = sum(abs2, @view z[k+1:end])

    b0 = ybar - dot(xbar, b)
    r2 = 1.0 - ss_res / ss_tot
    return [b0; b], r2
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

function main(io_in::IO=stdin, io_out::IO=stdout)
    X, y = read_problem(read(io_in))
    coef, r2 = fit_ols(X, y)
    out = IOBuffer()
    for c in coef
        println(out, c)
    end
    println(out, r2)
    write(io_out, take!(out))
    flush(io_out)
    return 0
end

end # module
