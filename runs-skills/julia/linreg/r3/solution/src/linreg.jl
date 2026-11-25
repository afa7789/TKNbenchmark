# Ordinary least-squares regression: reads `n k` and n rows of `x1 … xk y` from stdin,
# prints b0, b1, …, bk and R².
#
# Numerics: the data are centred on their (approximate) column means and the augmented
# matrix [1 x̃ ỹ] is reduced to its triangular factor R by blocked Householder QR, so the
# normal equations are never formed. With R = [R₁₁ r; 0 ρ], the centred coefficients solve
# R₁₁ c = r and SS_res = ρ². An explicit intercept column keeps the fit exact even though
# the centring constants carry rounding error.
module LinReg

using LinearAlgebra
using Printf

const BLOCK_ROWS = 2048
const POW10 = ntuple(i -> 10.0^(i - 1), 23)   # exact powers 1e0 … 1e22

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\t') || b == UInt8('\r')
@inline isdigit_byte(b::UInt8) = UInt8('0') <= b <= UInt8('9')

"""Index of the first non-whitespace byte at or after `i`."""
@inline function skip_space(buf::Vector{UInt8}, i::Int)
    n = length(buf)
    while i <= n && isspace_byte(@inbounds buf[i])
        i += 1
    end
    return i
end

"""Index one past the end of the token starting at `i`."""
@inline function token_end(buf::Vector{UInt8}, i::Int)
    n = length(buf)
    while i <= n && !isspace_byte(@inbounds buf[i])
        i += 1
    end
    return i
end

"""
    parse_float(buf, i) -> (value, next)

Parse the whitespace-delimited number starting at or after `i`. Plain decimal notation is
handled by a fast path; anything else is delegated to `Base.parse`.
"""
function parse_float(buf::Vector{UInt8}, i::Int)
    start = skip_space(buf, i)
    stop = token_end(buf, start)
    start < stop || throw(ArgumentError("unexpected end of input"))
    v = fast_decimal(buf, start, stop)
    if v === nothing
        v = parse(Float64, String(buf[start:stop-1]))
    end
    return v, stop
end

function fast_decimal(buf::Vector{UInt8}, i::Int, stop::Int)::Union{Float64,Nothing}
    neg = false
    @inbounds b = buf[i]
    if b == UInt8('-') || b == UInt8('+')
        neg = b == UInt8('-')
        i += 1
    end
    mant = UInt64(0)
    ndig = 0          # significant digits accumulated into `mant`
    exp10 = 0
    seen = false
    @inbounds while i < stop && isdigit_byte(buf[i])
        d = buf[i] - UInt8('0')
        if ndig < 19
            mant = 10mant + d
            ndig += mant != 0
        else
            exp10 += 1
        end
        seen = true
        i += 1
    end
    if i < stop && @inbounds(buf[i]) == UInt8('.')
        i += 1
        @inbounds while i < stop && isdigit_byte(buf[i])
            if ndig < 19
                mant = 10mant + (buf[i] - UInt8('0'))
                ndig += mant != 0
                exp10 -= 1
            end
            seen = true
            i += 1
        end
    end
    seen || return nothing
    if i < stop && (@inbounds(buf[i]) == UInt8('e') || @inbounds(buf[i]) == UInt8('E'))
        i += 1
        eneg = false
        if i < stop && (@inbounds(buf[i]) == UInt8('-') || @inbounds(buf[i]) == UInt8('+'))
            eneg = @inbounds(buf[i]) == UInt8('-')
            i += 1
        end
        i < stop || return nothing
        e = 0
        @inbounds while i < stop && isdigit_byte(buf[i])
            e < 100_000 && (e = 10e + Int(buf[i] - UInt8('0')))
            i += 1
        end
        exp10 += eneg ? -e : e
    end
    i == stop || return nothing
    abs(exp10) <= 22 || return nothing
    x = Float64(mant)
    x = exp10 >= 0 ? x * POW10[exp10+1] : x / POW10[-exp10+1]
    return neg ? -x : x
end

function parse_int(buf::Vector{UInt8}, i::Int)
    start = skip_space(buf, i)
    stop = token_end(buf, start)
    start < stop || throw(ArgumentError("unexpected end of input"))
    return parse(Int, String(buf[start:stop-1])), stop
end

"""
    read_data(buf) -> (n, k, data)

`data` is a `(k + 1) × n` matrix; column `i` holds observation `i` as `x1 … xk y`.
"""
function read_data(buf::Vector{UInt8})
    n, pos = parse_int(buf, 1)
    k, pos = parse_int(buf, pos)
    (k >= 1 && n >= k + 1) || throw(ArgumentError("invalid dimensions n=$n k=$k"))
    data = Matrix{Float64}(undef, k + 1, n)
    @inbounds for j in 1:n, c in 1:k+1
        data[c, j], pos = parse_float(buf, pos)
    end
    return n, k, data
end

"""
    fit(data) -> (coefficients, r2)

Least-squares fit of the last row of `data` on the other rows plus an intercept.
"""
function fit(data::AbstractMatrix{Float64})
    q, n = size(data)            # q = k + 1
    k = q - 1
    p = k + 2                    # columns: 1, x̃1 … x̃k, ỹ
    shift = vec(sum(data; dims = 2)) ./ n

    sstot = 0.0
    @inbounds for j in 1:n
        sstot += (data[q, j] - shift[q])^2
    end

    work = zeros(p + BLOCK_ROWS, p)
    R = zeros(p, p)
    for first in 1:BLOCK_ROWS:n
        last = min(first + BLOCK_ROWS - 1, n)
        copyto!(view(work, 1:p, :), R)
        @inbounds for (r, j) in enumerate(first:last)
            row = p + r
            work[row, 1] = 1.0
            for c in 1:q
                work[row, c+1] = data[c, j] - shift[c]
            end
        end
        rows = p + (last - first + 1)
        LAPACK.geqrf!(view(work, 1:rows, :))
        @inbounds for c in 1:p, r in 1:p
            R[r, c] = r <= c ? work[r, c] : 0.0
        end
    end

    m = k + 1
    c = UpperTriangular(R[1:m, 1:m]) \ R[1:m, p]
    ssres = R[p, p]^2

    coefs = Vector{Float64}(undef, m)
    coefs[2:end] .= @view c[2:end]
    coefs[1] = c[1] + shift[q] - sum(c[j+1] * shift[j] for j in 1:k)
    return coefs, 1.0 - ssres / sstot
end

function main()
    # The QR blocks are thin (p ≤ 22 columns); BLAS threading only adds overhead here.
    BLAS.set_num_threads(1)
    _, _, data = read_data(read(stdin))
    coefs, r2 = fit(data)
    out = IOBuffer()
    for b in coefs
        @printf(out, "%.15g\n", b)
    end
    @printf(out, "%.15g\n", r2)
    write(stdout, take!(out))
    return 0
end

end # module

exit(LinReg.main())
