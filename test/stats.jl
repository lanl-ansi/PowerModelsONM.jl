@testset "test statistical analysis functions" begin
    raw_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "events" => "../test/data/ieee13_events.json",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "faults" => "../test/data/ieee13_faults.json",
    )

    orig_args = prepare_data!(deepcopy(raw_args))

    set_settings!(orig_args, Dict(
        ("options", "constraints", "disable-microgrid-networking") => true,
        ("options", "objective", "enable-switch-state-open-cost") => true,
        ("options", "outputs", "log-level") => "error",
        ("solvers", "HiGHS", "mip_feasibility_tolerance") => 1e-6,
        ("solvers", "HiGHS", "presolve") => "off"
    ))

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

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["real power setpoint (kW)"], [754.631, 772.791, 773.189]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["voltage_source"]["source"]["reactive power setpoint (kVar)"], [434.111, 423.166, 444.365]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["real power setpoint (kW)"], [4.66588, 4.66588, 4.66588]; atol=1e-1))
        @test args["output_data"]["Powerflow output"][3]["solar"]["pv_mg1b"]["inverter"] == "GRID_FOLLOWING"

        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["real power flow (kW)"], [0.0, 0.0, 0.0]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Powerflow output"][1]["switch"]["671692"]["reactive power flow (kVar)"], [0.0, 0.0, 0.0]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Powerflow output"][7]["switch"]["703800"]["voltage (V)"], args["output_data"]["Powerflow output"][7]["bus"]["703"]["voltage (V)"]; atol=1e-4))

        @test args["output_data"]["Optimal dispatch metadata"]["termination_status"] == "LOCALLY_SOLVED"

        @test args["output_data"]["Powerflow output"][1]["bus"]["702"]["voltage (V)"] == [0.0, 0.0, 0.0]
    end


    @testset "test microgrid stats" begin
        @test all(isapprox.(args["output_data"]["Storage SOC (%)"], [36.4, 34.8, 44.7, 46.5, 48.0, 48.0, 31.2, 16.8]; atol=1e0))

        @test all(isapprox.(args["output_data"]["Load served"]["Bonus load via microgrid (%)"], [0.0, 0.0, 9.57997, 8.35485, 8.35485, 8.70728, 8.70728, 9.11343]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Feeder load (%)"], [93.7930, 93.7860, 84.2933, 85.3878, 85.3878, 85.0814, 85.0814, 84.7187]; atol=1e-1))
        @test all(isapprox.(args["output_data"]["Load served"]["Microgrid load (%)"], [14.2464, 17.9733, 51.9408, 64.7277, 61.1884, 53.4061, 82.2705, 81.8947]; atol=1e-1))

        @test all(isapprox.(args["output_data"]["Generator profiles"]["Diesel DG (kW)"], [0.0, 0.0, 271.752, 285.112, 285.112, 280.420, 280.420, 276.006]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Energy storage (kW)"], [75.0, 20.0016, 6.00045, -22.4995, -17.9993, -0.499176, 210.0, 180.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Solar DG (kW)"], [0.0, 0.0, 14.0, 35.0, 28.0, 10.5, 0.0, 0.0]; atol=1e0))
        @test all(isapprox.(args["output_data"]["Generator profiles"]["Grid mix (kW)"], [2300.74, 2385.57, 2391.12, 2913.88, 2913.88, 2740.06, 2740.06, 2565.76]; atol=1e1))
    end

    @testset "test stability stats" begin
        @test all(.!args["output_data"]["Small signal stable"])
    end

    @testset "test missing events arg" begin
        _args = deepcopy(raw_args)
        delete!(_args, "events")
        _args["skip"] = ["switching", "dispatch", "stability", "faults"]

        _args = entrypoint(_args)

        @test isa(_args["events"], Dict{String,Any}) && isempty(_args["events"])
    end

    @testset "test missing output_data" begin
        _args = deepcopy(orig_args)
        delete!(_args, "output_data")

        analyze_results!(_args)

        @test haskey(_args, "output_data") && !isempty(_args["output_data"])
    end
end
