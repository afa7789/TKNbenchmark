include(joinpath(@__DIR__, "LinReg.jl"))
using .LinReg

function julia_main()
    try
        return LinReg.main()
    catch err
        err isa InterruptException && rethrow()
        println(stderr, "error: ", sprint(showerror, err))
        return 1
    end
end

exit(julia_main())
