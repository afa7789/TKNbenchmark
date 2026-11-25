"""
    LinReg

Ordinary least-squares regression from standard input (see SPEC.md).

The intercept is handled by centring: features and response are centred on
their means, the slopes are obtained from a Householder QR factorisation of the
centred design matrix (numerically stable, no normal equations), and the
intercept is recovered as `ȳ - x̄ ⋅ β`.
"""
module LinReg

using LinearAlgebra
using Printf

export fit_ols, main

const POW10 = ntuple(i -> 10.0^(i - 1), 23)   # exact powers 1e0 … 1e22

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r') || b == UInt8('\t')
@inline isdigit_byte(b::UInt8) = UInt8('0') <= b <= UInt8('9')

"""
    TokenReader(buf)

Cursor over a byte buffer yielding whitespace-separated numeric tokens.
"""
mutable struct TokenReader
    buf::Vector{UInt8}
    pos::Int
end
TokenReader(buf::Vector{UInt8}) = TokenReader(buf, 1)

"Advance past whitespace and return the `(start, stop)` byte range of the next token."
@inline function next_token(r::TokenReader)
    buf, n = r.buf, length(r.buf)
    i = r.pos
    @inbounds while i <= n && isspace_byte(buf[i])
        i += 1
    end
    i > n && throw(ArgumentError("unexpected end of input"))
    j = i
    @inbounds while j <= n && !isspace_byte(buf[j])
        j += 1
    end
    r.pos = j
    return i, j - 1
end

slow_parse(::Type{T}, buf, i, j) where {T} = parse(T, String(buf[i:j]))

function read_int(r::TokenReader)
    i, j = next_token(r)
    return slow_parse(Int, r.buf, i, j)
end

"""
    read_float(r) -> Float64

Parse the next token as a decimal floating-point number. Common forms
(at most 19 significant digits, small exponents) are converted exactly with a
single correctly rounded multiply/divide; anything else falls back to `parse`.
"""
function read_float(r::TokenReader)
    i, j = next_token(r)
    buf = r.buf
    k = i
    neg = false
    @inbounds if buf[k] == UInt8('-')
        neg = true
        k += 1
    elseif buf[k] == UInt8('+')
        k += 1
    end
    mant = UInt64(0)
    ndigits = 0
    scale = 0          # decimal exponent adjustment from the fractional part
    seen = false
    @inbounds while k <= j && isdigit_byte(buf[k])
        mant = 10mant + (buf[k] - UInt8('0'))
        ndigits += mant != 0
        seen = true
        k += 1
    end
    @inbounds if k <= j && buf[k] == UInt8('.')
        k += 1
        while k <= j && isdigit_byte(buf[k])
            mant = 10mant + (buf[k] - UInt8('0'))
            ndigits += mant != 0
            scale -= 1
            seen = true
            k += 1
        end
    end
    expo = 0
    @inbounds if seen && k <= j && (buf[k] == UInt8('e') || buf[k] == UInt8('E'))
        k += 1
        eneg = false
        if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
            eneg = buf[k] == UInt8('-')
            k += 1
        end
        edigits = 0
        while k <= j && isdigit_byte(buf[k]) && edigits < 6
            expo = 10expo + (buf[k] - UInt8('0'))
            edigits += 1
            k += 1
        end
        edigits == 0 && (k = -1)          # malformed: force slow path
        eneg && (expo = -expo)
    end
    if !seen || k != j + 1 || ndigits > 15 || mant >= UInt64(1) << 53
        return slow_parse(Float64, buf, i, j)
    end
    e = expo + scale
    x = Float64(mant)
    if 0 <= e <= 22
        x *= POW10[e + 1]
    elseif -22 <= e < 0
        x /= POW10[1 - e]
    else
        return slow_parse(Float64, buf, i, j)
    end
    return neg ? -x : x
end

"""
    fit_ols(X, y) -> (coef, r2)

Least-squares fit of `y ≈ b0 + X * b`. Returns `coef = [b0; b]` and the
coefficient of determination. `X` is overwritten (centred and factorised).
"""
function fit_ols(X::Matrix{Float64}, y::Vector{Float64})
    n, k = size(X)
    length(y) == n || throw(DimensionMismatch("X has $n rows but y has $(length(y))"))

    xmean = vec(sum(X; dims = 1)) ./ n
    ymean = sum(y) / n
    X .-= xmean'
    yc = y .- ymean
    sstot = sum(abs2, yc)

    F = qr!(X)
    β = F \ yc

    # Residual sum of squares: the part of yc orthogonal to the column space.
    qty = lmul!(F.Q', copy(yc))
    ssres = sum(abs2, @view qty[(k + 1):n])

    b0 = ymean - dot(xmean, β)
    return [b0; β], 1 - ssres / sstot
end

function read_problem(io::IO)
    r = TokenReader(read(io))
    n = read_int(r)
    k = read_int(r)
    (k >= 1 && n >= k + 1) || throw(ArgumentError("invalid dimensions n=$n k=$k"))
    X = Matrix{Float64}(undef, n, k)
    y = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        for j in 1:k
            X[i, j] = read_float(r)
        end
        y[i] = read_float(r)
    end
    return X, y
end

function (@main)(::Vector{String})
    X, y = read_problem(stdin)
    coef, r2 = fit_ols(X, y)
    out = IOBuffer()
    for c in coef
        @printf(out, "%.15g\n", c)
    end
    @printf(out, "%.15g\n", r2)
    write(stdout, take!(out))
    return 0
end

end # module LinReg

using .LinReg: main   # make LinReg's `@main` the script entry point
