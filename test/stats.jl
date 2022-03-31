@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "events" => "../test/data/ieee13_events.json",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "output" => "test_output.json",
        "pretty-print" => true,
        "faults" => "../test/data/ieee13_faults.json",
        "opt-switch-algorithm" => "global",
        "opt-switch-problem" => "block",
        "opt-switch-solver" => "mip_solver",
        "opt-switch-formulation" => "lindistflow",
        "opt-disp-formulation" => "lindistflow",
        "quiet" => true,
    )

    args = entrypoint(deepcopy(orig_args))

    @testset "test output schema" begin
        @test validate_output(args["output_data"])
    end

    @testset "test action stats" begin
        @test (
            args["output_data"]["Device action timeline"] == Any[Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "701", "702", "700", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["4"], ["2", "3"], ["1"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["1"], ["4", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict{String, Any}("Shedded loads" => ["801"], "Microgrid networks" => [["1"], ["4", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed"))]
            || args["output_data"]["Device action timeline"] == Any[Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "701", "702", "700", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["4"], ["2", "3"], ["1"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["1"], ["4", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict{String, Any}("Shedded loads" => ["801"], "Microgrid networks" => [["1"], ["4", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "open", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict{String, Any}("Shedded loads" => String[], "Microgrid networks" => [["4", "1", "2", "3"]], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed"))]
        )
        @test (
            args["output_data"]["Switch changes"] == [String[], ["671692"], ["671700"], ["701702"], ["800801"], ["703800"], ["801675", "703800"], String[]]
            || args["output_data"]["Switch changes"] == [String[], ["671692"], ["671700"], ["701702"], ["703800"], ["800801"], ["801675", "703800"], String[]]
        )

        @test all(isnan(metadata["mip_gap"]) for metadata in args["output_data"]["Optimal switching metadata"])
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

        @test all(isapprox.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], args["output_data"]["Powerflow output"][7]["bus"]["703"]["voltage (V)"]; atol=1e-4))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["702"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end

    @testset "test fault stats" begin
        @test all(isempty(args["output_data"]["Fault studies metadata"][i]) for i in 1:3)
        @test all(!isempty(args["output_data"]["Fault studies metadata"][i]) for i in 4:8)
    end

    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [38.4, 30.0, 21.9996, 10.7991, 54.7982, 79.5962, 76.084, 75.5948]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [0.0, 8.77971, 6.89257, 9.19113, 8.51601, 0.240061, 15.2728, 15.242]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [94.2578, 85.4502, 87.3202, 84.7465, 85.4157, 93.6999, 79.0702, 79.2458]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [9.49758, 79.7379, 73.7578, 92.0115, 73.6083, 93.4183, 92.1845, 92.5304]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], [0.0, 248.986, 249.93, 267.962, 268.575, 281.907, 499.584, 499.165]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [50.0, 105.0, 100.005, 140.007, -59.9897, -309.975, 43.9025, 6.11582]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [0.0, 0.0, 6.99837, 124.904, 99.6135, 37.224, 0.0, 0.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [2312.14, 2423.3, 2494.9, 3069.24, 3091.24, 3573.53, 2813.72, 2627.05]; atol=1e1))
    end

    @testset "test stability stats" begin
        @test all(.!args["output_data"]["Small signal stable"])
    end

    @testset "test missing events arg" begin
        _args = deepcopy(orig_args)
        delete!(_args, "events")
        _args["skip"] = ["switching", "dispatch", "stability", "faults"]

        _args = entrypoint(_args)

        @test isa(_args["events"], Dict{String,Any}) && isempty(_args["events"])
    end
end
