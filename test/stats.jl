@testset "test statistical analysis functions" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "settings" => "../test/data/settings.json",
        "inverters" => "../test/data/inverters.json",
        "faults" => "../test/data/faults.json",
        "quiet" => true
    )

    args = entrypoint(args)

    @testset "test action stats" begin

    end

    @testset "test dispatch stats" begin

    end

    @testset "test fault stats" begin

    end

    @testset "test microgrid stats" begin

    end

    @testset "test stability stats" begin

    end
end
