@testset "test statistical analysis functions" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "events" => "../test/data/ieee13_events.json",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "faults" => "../test/data/ieee13_faults.json",
        "disable-networking" => true,
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
        @test args["output_data"]["Device action timeline"] == Any[Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "801", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "801", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "801", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "801", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "open")), Dict{String, Any}("Shedded loads" => ["702", "703"], "Microgrid networks" => [["2"], ["4"], ["1"], ["3"]], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "open"))]

        @test args["output_data"]["Switch changes"] == [String[], ["671700"], ["671692", "671700"], ["800801"], String[], String[], String[], String[]]

        @test all(isapprox(metadata["mip_gap"], 0.0; atol=1e-4) for metadata in args["output_data"]["Optimal switching metadata"])
    end

    @testset "test dispatch stats" begin
        @test length(args["output_data"]["Powerflow output"]) == 8
        @test all(all(haskey(ts, k) for k in ["voltage_source", "generator", "solar", "storage", "bus", "switch"]) for ts in args["output_data"]["Powerflow output"])

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], [756.4, 775.4, 780.2]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], [437.1, 420.6, 445.4]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["real power setpoint (kW)"], [4.66588, 4.66588, 4.66588]; atol=1e-1))
        @test args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["inverter"] == "GRID_FOLLOWING"

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"], [0.0, 0.0, 0.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"], [0.0, 0.0, 0.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], args["output_data"]["Powerflow output"][7]["bus"]["703"]["voltage (V)"]; atol=1e-4))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["702"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end

    @testset "test fault stats" begin
        @test all(isempty(args["output_data"]["Fault studies metadata"][i]) for i in 1:2)
        @test all(!isempty(args["output_data"]["Fault studies metadata"][i]) for i in 3:8)
    end

    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [36.4, 34.7959, 44.7157, 46.5155, 47.9552, 47.9948, 31.1948, 16.7948]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [0.0, 0.0, 8.79442, 7.75789, 7.75789, 8.05933, 8.05933, 8.40477]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [94.2578, 94.2251, 85.4359, 86.2169, 86.2169, 86.0, 86.0, 85.7382]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [14.2464, 17.9733, 51.9408, 64.7277, 61.1885, 53.4061, 82.2705, 81.8947]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], [0.0, 0.0, 249.403, 264.638, 264.638, 259.457, 259.457, 254.46]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [75.0, 20.0513, 6.00235, -22.4972, -17.9965, -0.495222, 210.0, 180.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [0.0, 0.0, 13.9995, 34.9995, 27.9993, 10.4991, 0.0, 0.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [2312.14, 2396.29, 2422.9, 2941.04, 2941.04, 2768.62, 2768.62, 2595.78]; atol=1e1))
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
