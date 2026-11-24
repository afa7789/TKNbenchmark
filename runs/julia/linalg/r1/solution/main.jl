include(joinpath(@__DIR__, "src", "LinalgApp.jl"))
using .LinalgApp

try
    LinalgApp.main()
catch err
    err isa ArgumentError || rethrow()
    println(stderr, "error: ", err.msg)
    exit(1)
end
