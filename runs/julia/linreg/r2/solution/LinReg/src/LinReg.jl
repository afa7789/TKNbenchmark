"""
    LinReg

Ordinary least-squares regression read from standard input (see SPEC.md).

The fit centres every column, then reduces the centred augmented matrix
`[X̃ ỹ]` to a triangular factor chunk by chunk with Householder QR, which is
numerically far more robust than forming the normal equations.
"""
module LinReg

using LinearAlgebra

export fit, main

const CHUNK_ROWS = 4096

# ----------------------------------------------------------------------------
# Input parsing
# ----------------------------------------------------------------------------

@inline isspace_byte(b::UInt8) = b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r') ||
                                 b == UInt8('\t') || b == UInt8('\f') || b == UInt8('\v')
@inline isdigit_byte(b::UInt8) = UInt8('0') <= b <= UInt8('9')

const POW10 = ntuple(i -> 10.0^(i - 1), 23)   # exactly representable 1e0 … 1e22

"""
    next_token(buf, pos) -> (start, stop)

Skip whitespace from `pos` and return the byte range of the next token.
`start > length(buf)` signals end of input.
"""
@inline function next_token(buf::Vector{UInt8}, pos::Int)
    n = length(buf)
    @inbounds while pos <= n && isspace_byte(buf[pos])
        pos += 1
    end
    start = pos
    @inbounds while pos <= n && !isspace_byte(buf[pos])
        pos += 1
    end
    return start, pos - 1
end

slow_parse(buf, a, b) = parse(Float64, String(buf[a:b]))

"""
    parse_float(buf, a, b) -> Float64

Parse the decimal number in `buf[a:b]`. Uses Clinger's exact fast path
(mantissa < 2^53, |power of ten| ≤ 22) and falls back to `parse` otherwise.
"""
function parse_float(buf::Vector{UInt8}, a::Int, b::Int)
    i = a
    neg = false
    @inbounds c = buf[i]
    if c == UInt8('-') || c == UInt8('+')
        neg = c == UInt8('-')
        i += 1
    end
    mant = UInt64(0)
    ndig = 0          # significant digits accumulated into `mant`
    exp10 = 0
    seen = false
    @inbounds while i <= b && isdigit_byte(buf[i])
        d = buf[i] - UInt8('0')
        if ndig > 0 || d != 0
            ndig += 1
            ndig > 19 && return slow_parse(buf, a, b)
        end
        mant = mant * 10 + d
        seen = true
        i += 1
    end
    if i <= b && @inbounds(buf[i]) == UInt8('.')
        i += 1
        @inbounds while i <= b && isdigit_byte(buf[i])
            d = buf[i] - UInt8('0')
            if ndig > 0 || d != 0
                ndig += 1
                ndig > 19 && return slow_parse(buf, a, b)
            end
            mant = mant * 10 + d
            exp10 -= 1
            seen = true
            i += 1
        end
    end
    seen || return slow_parse(buf, a, b)
    if i <= b && (@inbounds(buf[i]) == UInt8('e') || @inbounds(buf[i]) == UInt8('E'))
        i += 1
        eneg = false
        if i <= b && (@inbounds(buf[i]) == UInt8('-') || @inbounds(buf[i]) == UInt8('+'))
            eneg = @inbounds(buf[i]) == UInt8('-')
            i += 1
        end
        i <= b || return slow_parse(buf, a, b)
        e = 0
        @inbounds while i <= b && isdigit_byte(buf[i])
            e = e * 10 + Int(buf[i] - UInt8('0'))
            e > 100_000 && return slow_parse(buf, a, b)
            i += 1
        end
        exp10 += eneg ? -e : e
    end
    i == b + 1 || return slow_parse(buf, a, b)
    (mant < (UInt64(1) << 53) && -22 <= exp10 <= 22) || return slow_parse(buf, a, b)
    x = Float64(mant)
    x = exp10 >= 0 ? x * POW10[exp10+1] : x / POW10[-exp10+1]
    return neg ? -x : x
end

function parse_int(buf::Vector{UInt8}, a::Int, b::Int)
    a <= b || throw(ArgumentError("unexpected end of input"))
    return parse(Int, String(buf[a:b]))
end

"""
    read_data(buf) -> Matrix{Float64}

Parse the whole input. Returns a `(k + 1) × n` matrix whose column `i` holds
row `i` of the input (features followed by the response).
"""
function read_data(buf::Vector{UInt8})
    a, b = next_token(buf, 1)
    n = parse_int(buf, a, b)
    a, b = next_token(buf, b + 1)
    k = parse_int(buf, a, b)
    (k >= 1 && n >= k + 1) || throw(ArgumentError("invalid dimensions n=$n k=$k"))
    data = Matrix{Float64}(undef, k + 1, n)
    pos = b + 1
    @inbounds for idx in eachindex(data)
        a, b = next_token(buf, pos)
        a <= length(buf) || throw(ArgumentError("expected $(length(data)) values, input ended early"))
        data[idx] = parse_float(buf, a, b)
        pos = b + 1
    end
    return data
end

# ----------------------------------------------------------------------------
# Fitting
# ----------------------------------------------------------------------------

"""
    fit(data) -> (coefficients, r2)

`data` is `(k + 1) × n`, one observation per column with the response last.
Returns `[b0, b1, …, bk]` and the coefficient of determination.
"""
function fit(data::AbstractMatrix{Float64})
    p, n = size(data)            # p = k + 1
    k = p - 1
    means = vec(sum(data; dims = 2)) ./ n

    # Triangular factor of the centred augmented matrix [X̃ ỹ], built by
    # repeatedly QR-factorising [R; next chunk].
    R = zeros(p, p)
    work = Matrix{Float64}(undef, p + CHUNK_ROWS, p)
    for lo in 1:CHUNK_ROWS:n
        hi = min(lo + CHUNK_ROWS - 1, n)
        m = hi - lo + 1
        @inbounds for j in 1:p
            for i in 1:p
                work[i, j] = R[i, j]
            end
            μ = means[j]
            for r in 1:m
                work[p+r, j] = data[j, lo+r-1] - μ
            end
        end
        F = qr!(view(work, 1:p+m, :))
        R .= F.R
    end

    slopes = UpperTriangular(view(R, 1:k, 1:k)) \ R[1:k, p]
    intercept = means[p] - dot(slopes, view(means, 1:k))

    ss_res = 0.0
    ss_tot = 0.0
    @inbounds for i in 1:n
        ỹ = data[p, i] - means[p]
        r = ỹ
        for j in 1:k
            r -= slopes[j] * (data[j, i] - means[j])
        end
        ss_res += r * r
        ss_tot += ỹ * ỹ
    end
    r2 = 1.0 - ss_res / ss_tot

    return vcat(intercept, slopes), r2
end

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------

function run(in::IO, out::IO)
    coefs, r2 = fit(read_data(read(in)))
    buf = IOBuffer()
    for c in coefs
        println(buf, repr(c))
    end
    println(buf, repr(r2))
    write(out, take!(buf))
    flush(out)
    return nothing
end

function main()
    try
        run(stdin, stdout)
    catch err
        err isa InterruptException && rethrow()
        println(stderr, "error: ", sprint(showerror, err))
        return 1
    end
    return 0
end

# Exercise the hot paths while precompiling so their native code is cached.
if ccall(:jl_generating_output, Cint, ()) == 1
    let sample = Vector{UInt8}("5 2\n1 2 9.5\n2 1 8.1\n3 4 19.2\n4 3 -1.79e1\n5 5 25.4\n")
        run(IOBuffer(sample), IOBuffer())
    end
end

end # module
