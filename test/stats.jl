@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "settings" => "../test/data/settings.json",
        "inverters" => "../test/data/inverters.json",
        "output" => "test_output.json",
        "faults" => "../test/data/faults.json",
        "opt-switch-algorithm" => "global",
        "opt-switch-solver" => "mip_solver",
        "opt-disp-formulation" => "lindistflow",
        "fix-small-numbers" => true,
        "quiet" => true
    )

    args = entrypoint(deepcopy(orig_args))

    @testset "test output schema" begin
        @test validate_output(args["output_data"])
    end

    @testset "test action stats" begin
        @test args["output_data"]["Device action timeline"] == Dict{String, Any}[
            Dict("Shedded loads" => ["701", "700"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")),
            Dict("Shedded loads" => ["701", "700"], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed"))
        ]

        @test args["output_data"]["Switch changes"] == [String[], ["671692"], ["701702"], String[], String[], String[]]

        @test all(isapprox.(metadata["mip_gap"], 0.0; atol=1e-4) for metadata in args["output_data"]["Optimal switching metadata"])
    end

    @testset "test dispatch stats" begin
        @test length(args["output_data"]["Powerflow output"]) == 6
        @test all(haskey(ts, "voltage_source") && haskey(ts, "solar") && haskey(ts, "bus") for ts in args["output_data"]["Powerflow output"])

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], [349.186, 236.049, 329.489]; atol=10))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], [225.224, 182.649, 105.957]; atol=10))

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["solar"]["pv1"]["real power setpoint (kW)"], [61.6666, 61.6666, 61.6666]; atol=5))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["solar"]["pv1"]["reactive power setpoint (kVar)"], [40.0000, 40.0000, 40.0000]; atol=5))

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"], 0.0; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"], 0.0; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["801675"]["voltage (V)"], args["output_data"]["Powerflow output"][1]["bus"]["675"]["voltage (V)"]))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test all(args["output_data"]["Powerflow output"][1]["bus"]["701"]["voltage (V)"] .== 0)
    end

    @testset "test fault stats" begin
        @test isempty(args["output_data"]["Fault studies metadata"][1])
    end

    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [53.17, 61.51, 70.03, 79.02, 88.57, 100.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [45.17, 0.0, 1.41, 1.41, 0.95, 1.41]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [49.02, 101.23, 101.23, 101.23, 101.98, 101.23]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [100.0, 100.0, 100.0, 100.0, 100.0, 100.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], 0.0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [873.0, 0.0, 0.0, 0.0, 0.0, 0.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [185.0, 185.0, 210.0, 210.0, 210.0, 210.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [914.72, 2121.20, 2128.56, 2147.21, 3043.02, 2244.58]; atol=1e-1))
    end

    @testset "test stability stats" begin
        @test all(!i for i in args["output_data"]["Small signal stable"])
    end

    @testset "test missing events arg" begin
        _args = deepcopy(orig_args)
        delete!(_args, "events")
        _args["skip"] = ["switching", "dispatch", "stability", "faults"]

        _args = entrypoint(_args)

        @test isa(_args["events"], Dict{String,Any}) && isempty(_args["events"])
    end
end
