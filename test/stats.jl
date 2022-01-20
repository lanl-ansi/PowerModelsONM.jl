@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "events" => "../test/data/ieee13_events.json",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "output" => "test_output.json",
        "pretty-print" => true,
        "faults" => "../test/data/ieee13_faults.json",
        "skip" => ["stability"],  # TODO bug in upstream PowerModelsStability: if an object in inverters is DISABLED, error in calc_connected_components
        "apply-switch-scores" => true,
        "opt-switch-algorithm" => "global",
        "opt-switch-solver" => "mip_solver",
        "opt-disp-formulation" => "lindistflow",
        "quiet" => true
    )

    args = entrypoint(deepcopy(orig_args))

    @testset "test output schema" begin
        @test validate_output(args["output_data"])
    end

    @testset "test action stats" begin
        @test args["output_data"]["Device action timeline"] == Any[Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict{String, Any}("Shedded loads" => ["801"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]

        @test args["output_data"]["Switch changes"] == [String[], ["671700"], ["671692"], ["701702"], ["800801"], ["703800"], String[], String[]]

        @test all(isapprox.(metadata["mip_gap"], 0.0; atol=1e-4) for metadata in args["output_data"]["Optimal switching metadata"])
    end

    @testset "test dispatch stats" begin
        @test length(args["output_data"]["Powerflow output"]) == 8
        @test all(all(haskey(ts, k) for k in ["voltage_source", "generator", "solar", "storage", "bus", "switch"]) for ts in args["output_data"]["Powerflow output"])

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], [756.4, 775.4, 780.2]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], [437.1, 420.6, 445.4]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["real power setpoint (kW)"], [2.33, 2.33, 2.33]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["reactive power setpoint (kVar)"], [-2.35, -2.35, -2.35]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"], [0.0, 0.0, 0.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"], [0.0, 0.0, 0.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], args["output_data"]["Powerflow output"][7]["bus"]["800"]["voltage (V)"]; atol=1e-4))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["702"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end

    @testset "test fault stats" begin
        @test all(isempty(args["output_data"]["Fault studies metadata"][i]) for i in 1:3)
        @test all(!isempty(args["output_data"]["Fault studies metadata"][i]) for i in 4:8)
    end

    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [36.4, 34.8, 26.8, 15.6, 59.6, 80.0, 100.0, 100.0]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [0.0, 0.0, 6.83669, 9.16209, 8.48947, 1.61033, 0.596868, 7.76111]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [94.2578, 94.2376, 87.4482, 84.8377, 85.5033, 92.4015, 93.4218, 86.3617]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [14.2464, 17.9733, 73.7795, 92.0362, 73.6313, 93.4418, 92.0706, 92.3986]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], [0.0, 0.0, 248.33, 267.026, 267.681, 279.225, 271.254, 257.449]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [75.0, 20.0, 100.0, 140.0, -59.9999, -255.0, -250.0, -5.70086e-5]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [0.0, 0.0, 6.99746, 124.757, 99.5236, 37.179, 0.0, 0.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [2312.14, 2396.65, 2498.43, 3072.2, 3094.07, 3523.36, 3326.71, 2864.77]; atol=1e1))
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
