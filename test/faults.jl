@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "events" => "../test/data/ieee13_events.json",
        "opt-switch-solver" => "mip_solver",
        "opt-disp-formulation" => "acp",
        "opt-switch-algorithm" => "iterative",
        "quiet" => true,
        "skip" => ["stability"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["6"]["692"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [9693.17, 9002.85, 9919.24]; atol=1e3))
    @test all(isapprox.(args["fault_studies_results"]["6"]["692"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [5936.81, 5936.81]; atol=5e3))
    @test all(isapprox.(args["fault_studies_results"]["6"]["692"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [3289.67]; atol=1e3))

    @test all(isapprox.(args["output_data"]["Fault currents"][6]["692"]["3p"]["1"]["switch"]["671700"]["|I| (A)"], [11098.3, 11925.6, 10846.1]; atol=1e3))
    @test all(isapprox.(args["output_data"]["Fault currents"][6]["692"]["ll"]["1"]["switch"]["671700"]["|I| (A)"], [3140.43, 3257.82, 118.38]; atol=1e3))
    @test all(isapprox.(args["output_data"]["Fault currents"][6]["692"]["lg"]["1"]["switch"]["671700"]["|I| (A)"], [7033.05, 5192.28, 8459.68]; atol=1e3))

    @test all(isapprox.(args["output_data"]["Fault currents"][6]["692"]["lg"]["1"]["switch"]["671700"]["|V| (V)"], [1.68685, 2.57477, 0.444355]; atol=1e-1))
end
