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

        actions = get_timestep_device_actions!(args)
        @test actions[1]["Shedded loads"] == ["701", "702", "700", "703"]
        @test actions[2]["Shedded loads"] == ["702", "703"]
        @test all(isempty(actions[i]["Shedded loads"]) for i in 3:7)
        @test actions[1]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[2]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[3]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")
        @test actions[4]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")
        @test actions[5]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
        @test actions[6]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
        @test actions[7]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
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
        @test actions[1]["Shedded loads"] == ["701", "702", "700", "703"]
        @test actions[2]["Shedded loads"] == ["702", "703"]
        @test all(isempty(actions[i]["Shedded loads"]) for i in 3:7)
        @test actions[1]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[2]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")
        @test actions[3]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")
        @test actions[4]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "open", "701702" => "closed") || actions[4]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")
        @test actions[5]["Switch configurations"] == Dict{String,Any}("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
        @test actions[6]["Switch configurations"] == Dict{String,Any}("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
        @test actions[7]["Switch configurations"] == Dict{String,Any}("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")
    end
end
