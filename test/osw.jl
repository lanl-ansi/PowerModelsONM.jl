@testset "test optimal switching" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
    )

    parse_network!(args)
    parse_events!(args)

    # TODO enable optimize switches test
    # optimize_switches!(args)
end
