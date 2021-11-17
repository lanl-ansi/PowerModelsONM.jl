@testset "test optimal switching" begin
    @testset "test iterative optimal switching" begin
        args = Dict{String,Any}(
            "network" => "../test/data/IEEE13Nodeckt_mod.dss",
            "settings" => "../test/data/settings.json",
            "events" => "../test/data/events.json",
            "opt-switch-algorithm" => "iterative",
            "skip" => ["faults", "stability", "dispatch"],
            "opt-switch-solver" => "mip_solver"
        )
        entrypoint(args)

        for i in 2:length(args["optimal_switching_results"])
            @test args["optimal_switching_results"]["$(i-1)"]["objective"] > args["optimal_switching_results"]["$(i)"]["objective"]
        end

        actions = get_timestep_device_actions!(args)
        @test all(sl in ["700", "701"] for sl in actions[1]["Shedded loads"])
        @test actions[1]["Switch configurations"] == Dict{String,Any}("671700" => "open", "701702" => "open", "671692" => "closed", "703800"=>"open", "800801"=>"open")
        @test actions[2]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[3]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "open", "701702" => "open")
        @test actions[4]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "open")
        @test actions[5]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
    end

    @testset "test global optimal switching" begin
        args = Dict{String,Any}(
            "network" => "../test/data/IEEE13Nodeckt_mod.dss",
            "settings" => "../test/data/settings.json",
            "events" => "../test/data/events.json",
            "opt-switch-algorithm" => "global",
            "skip" => ["faults", "stability", "dispatch"],
            "opt-switch-solver" => "mip_solver"
        )
        entrypoint(args)

        actions = get_timestep_device_actions!(args)
        @test all(sl in ["700", "701"] for sl in actions[1]["Shedded loads"])
        @test actions[1]["Switch configurations"] == Dict{String,Any}("671700" => "open", "701702" => "open", "671692" => "closed", "703800"=>"open", "800801"=>"open")
        @test actions[2]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[3]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "open")
        @test actions[4]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "open")
        @test actions[5]["Switch configurations"] == Dict{String,Any}("671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
    end
end
