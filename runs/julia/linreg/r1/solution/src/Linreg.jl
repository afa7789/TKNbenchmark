"""
    Linreg

Ordinary least-squares regression read from standard input.

Input: a header line `n k`, followed by `n` rows of `k` feature values and a
response. Output: the intercept, the `k` slopes and the coefficient of
determination, one per line.
"""
module Linreg

using LinearAlgebra

export fit_ols, main

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

const POW10 = ntuple(i -> 10.0^(i - 1), 23)   # exactly representable 1e0 … 1e22

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r') ||
                                 b == UInt8('\t') || b == 0x0b || b == 0x0c
@inline isdigit_byte(b::UInt8) = UInt8('0') <= b <= UInt8('9')

"""
    skip_space(buf, i) -> Int

Index of the first non-whitespace byte at or after `i` (or `length(buf) + 1`).
"""
@inline function skip_space(buf::AbstractVector{UInt8}, i::Int)
    n = length(buf)
    @inbounds while i <= n && isspace_byte(buf[i])
        i += 1
    end
    return i
end

"""
    token_end(buf, i) -> Int

Index one past the end of the token starting at `i`.
"""
@inline function token_end(buf::AbstractVector{UInt8}, i::Int)
    n = length(buf)
    @inbounds while i <= n && !isspace_byte(buf[i])
        i += 1
    end
    return i
end

"""
    parse_float(buf, i) -> (value, next_index)

Parse the whitespace-delimited decimal number starting at byte `i`.

Common inputs (at most 15 significant digits, small exponents) take an exact
fast path: the integer mantissa and the power of ten are both exactly
representable, so a single IEEE multiply or divide gives the correctly
rounded result. Anything else is delegated to `Base.parse`.
"""
function parse_float(buf::AbstractVector{UInt8}, start::Int)
    stop = token_end(buf, start)
    stop > start || throw(ArgumentError("unexpected end of input"))
    i = start
    neg = false
    @inbounds b = buf[i]
    if b == UInt8('-') || b == UInt8('+')
        neg = b == UInt8('-')
        i += 1
    end
    mant = UInt64(0)
    ndigits = 0          # significant digits accumulated into `mant`
    scale = 0            # decimal exponent adjustment
    seen_digit = false
    @inbounds while i < stop && isdigit_byte(buf[i])
        d = buf[i] - UInt8('0')
        if ndigits > 0 || d != 0
            ndigits += 1
        end
        ndigits <= 19 ? (mant = 10mant + d) : (scale += 1)
        seen_digit = true
        i += 1
    end
    if i < stop && @inbounds(buf[i]) == UInt8('.')
        i += 1
        @inbounds while i < stop && isdigit_byte(buf[i])
            d = buf[i] - UInt8('0')
            if ndigits > 0 || d != 0
                ndigits += 1
            end
            if ndigits <= 19
                mant = 10mant + d
                scale -= 1
            end
            seen_digit = true
            i += 1
        end
    end
    if seen_digit && i < stop && (@inbounds(buf[i]) | 0x20) == UInt8('e')
        j = i + 1
        eneg = false
        if j < stop && (buf[j] == UInt8('-') || buf[j] == UInt8('+'))
            eneg = buf[j] == UInt8('-')
            j += 1
        end
        e = 0
        edigits = 0
        @inbounds while j < stop && isdigit_byte(buf[j]) && edigits < 6
            e = 10e + (buf[j] - UInt8('0'))
            edigits += 1
            j += 1
        end
        if edigits > 0
            scale += eneg ? -e : e
            i = j
        end
    end
    if seen_digit && i == stop && ndigits <= 15 && -22 <= scale <= 22
        x = Float64(mant)
        x = scale >= 0 ? x * @inbounds(POW10[scale + 1]) : x / @inbounds(POW10[1 - scale])
        return (neg ? -x : x), stop
    end
    return parse(Float64, String(buf[start:stop-1])), stop
end

"""
    parse_int(buf, i) -> (value, next_index)
"""
function parse_int(buf::AbstractVector{UInt8}, start::Int)
    stop = token_end(buf, start)
    stop > start || throw(ArgumentError("unexpected end of input"))
    return parse(Int, String(buf[start:stop-1])), stop
end

"""
    read_problem(buf) -> (X, y)

Parse the input bytes into an `n × k` feature matrix and a response vector.
"""
function read_problem(buf::AbstractVector{UInt8})
    i = skip_space(buf, 1)
    n, i = parse_int(buf, i)
    i = skip_space(buf, i)
    k, i = parse_int(buf, i)
    n >= 1 && k >= 1 || throw(ArgumentError("invalid dimensions n=$n, k=$k"))
    # Read row-major into a (k+1) × n buffer so writes are contiguous.
    data = Matrix{Float64}(undef, k + 1, n)
    @inbounds for r in 1:n, c in 1:k+1
        i = skip_space(buf, i)
        data[c, r], i = parse_float(buf, i)
    end
    X = permutedims(view(data, 1:k, :))
    y = data[k+1, :]
    return X, y
end

# ---------------------------------------------------------------------------
# Fitting
# ---------------------------------------------------------------------------

"""
    fit_ols(X, y) -> (coef, r2)

Least-squares fit of `y ≈ b0 + X * b`. Returns `coef = [b0; b]` and R².

Columns are centred (which removes the intercept from the system and improves
conditioning), then a Householder QR of the augmented matrix `[Xc yc]` yields
both the slopes and the residual sum of squares without forming the normal
equations.
"""
function fit_ols(X::AbstractMatrix{<:Real}, y::AbstractVector{<:Real})
    n, k = size(X)
    length(y) == n || throw(DimensionMismatch("X has $n rows but y has $(length(y))"))
    n > k || throw(ArgumentError("need more rows than features (n=$n, k=$k)"))

    A = Matrix{Float64}(undef, n, k + 1)
    A[:, 1:k] .= X
    A[:, k+1] .= y
    means = vec(sum(A; dims=1)) ./ n
    # Second correction pass makes the centring accurate even for large offsets.
    A .-= means'
    corr = vec(sum(A; dims=1)) ./ n
    A .-= corr'
    means .+= corr

    ss_tot = sum(abs2, view(A, :, k + 1))

    R = qr!(A).R                       # (k+1) × (k+1) upper triangular
    slopes = UpperTriangular(view(R, 1:k, 1:k)) \ R[1:k, k+1]
    ss_res = abs2(R[k+1, k+1])

    intercept = means[k+1] - dot(view(means, 1:k), slopes)
    r2 = 1 - ss_res / ss_tot
    return [intercept; slopes], r2
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

function run(input::IO, output::IO)
    X, y = read_problem(read(input))
    coef, r2 = fit_ols(X, y)
    buf = IOBuffer()
    # `print` emits the shortest representation that round-trips, i.e. full
    # double precision (up to 17 significant digits).
    for x in coef
        println(buf, x)
    end
    println(buf, r2)
    write(output, take!(buf))
    flush(output)
    return nothing
end

function main()::Cint
    try
        run(stdin, stdout)
        return 0
    catch err
        err isa InterruptException && return 130
        showerror(stderr, err)
        println(stderr)
        return 1
    end
end

# Exercise the full pipeline during precompilation so the native code is
# cached in the package image and the launcher starts without JIT latency.
if ccall(:jl_generating_output, Cint, ()) == 1
    let sample = "5 2\n1 2 9.5\n2 1 8.1\n3 4 19.2\n4 3 17.9\n5 5 2.54e1\n"
        run(IOBuffer(sample), IOBuffer())
    end
end

end # module
