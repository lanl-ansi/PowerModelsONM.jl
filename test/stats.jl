@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "settings" => "../test/data/settings.json",
        "inverters" => "../test/data/inverters.json",
        "output" => "test_output.json",
        "pretty-print" => true,
        "faults" => "../test/data/faults.json",
        "skip" => ["stability"],  # TODO bug in upstream PowerModelsStability: if an object in inverters is DISABLED, error in calc_connected_components
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
            Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")),
            Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")),
            Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))
        ]

        @test args["output_data"]["Switch changes"] == [["801675"], ["671700"], ["701702"], ["800801"], ["703800"], ["801675", "671692"], String[]]

        @test all(isapprox.(metadata["mip_gap"], 0.0; atol=1e-4) for metadata in args["output_data"]["Optimal switching metadata"])
    end

    @testset "test dispatch stats" begin
        @test length(args["output_data"]["Powerflow output"]) == 7
        @test all(all(haskey(ts, k) for k in ["voltage_source", "generator", "solar", "storage", "bus", "switch"]) for ts in args["output_data"]["Powerflow output"])

        @test round.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], RoundUp; sigdigits=3) == [350.0, 237.0, 330.0]
        @test round.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], RoundUp; sigdigits=3) == [226.0, 183.0, 106.0]

        @test round.(args["output_data"]["Powerflow output"][3]["solar"]["pv1"]["real power setpoint (kW)"], RoundUp; sigdigits=3) == [15.7, 15.7, 15.7]
        @test round.(args["output_data"]["Powerflow output"][3]["solar"]["pv1"]["reactive power setpoint (kVar)"], RoundUp; sigdigits=3) == [-13.9, -13.9, -13.9]

        @test round.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"]; digits=1) == [0.0, 0.0, 0.0]
        @test round.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"]; digits=1) == [0.0, 0.0, 0.0]

        @test round.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], RoundUp; sigdigits=4) == round.(args["output_data"]["Powerflow output"][7]["bus"]["800"]["voltage (V)"], RoundUp; sigdigits=4)

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["701"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end

    @testset "test fault stats" begin
        @test isempty(args["output_data"]["Fault studies metadata"][1])
    end

    @testset "test microgrid stats" begin
        @test round.(args["output_data"]["Storage SOC (%)"], RoundUp; sigdigits=3) == [84.1, 80.9, 52.3, 48.3, 45.3, 72.3, 100.0]

        @test round.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], RoundUp; sigdigits=3) == [19.9, 0.0267, 2.3, 18.5, 46.0, 71.7, 100.0]
        @test round.(args["output_data"]["Load served"]["Feeder load (%)"], RoundUp; sigdigits=3) == [47.8, 40.9, 35.0, 27.6, 22.3, 19.4, 14.3]
        @test round.(args["output_data"]["Load served"]["Microgrid load (%)"], RoundUp; sigdigits=3) == [51.8, 60.2, 76.3, 88.9, 91.3, 87.4, 89.4]

        @test round.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], RoundUp; sigdigits=3) == [500.0, 499.0, 461.0, 363.0, 252.0, 251.0, 252.0]
        @test round.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], RoundUp; sigdigits=3) == [352.0, 149.0, -16.9, -121.0, -0.0, -0.0, -0.0]
        @test round.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], RoundUp; sigdigits=3) == [0.0, 0.0, 47.1, 105.0, 63.9, 47.1, 0.0]
        @test round.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], RoundUp; sigdigits=3) == [915.0, 931.0, 1020.0, 1010.0, 1440.0, 1560.0, 1780.0]
    end

    @testset "test stability stats" begin
        @test isempty(args["output_data"]["Small signal stable"])
    end

    @testset "test missing events arg" begin
        _args = deepcopy(orig_args)
        delete!(_args, "events")
        _args["skip"] = ["switching", "dispatch", "stability", "faults"]

        _args = entrypoint(_args)

        @test isa(_args["events"], Dict{String,Any}) && isempty(_args["events"])
    end
end
