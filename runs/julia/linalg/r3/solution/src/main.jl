include(joinpath(@__DIR__, "LinAlgApp.jl"))
using .LinAlgApp

try
    exit(LinAlgApp.main())
catch err
    showerror(stderr, err)
    println(stderr)
    exit(1)
end
