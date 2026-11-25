include(joinpath(@__DIR__, "LinAlgApp.jl"))
using .LinAlgApp: LinAlgApp

(@main)(args) = LinAlgApp.main(args)
