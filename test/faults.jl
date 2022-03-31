@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "quiet" => true,
        "opt-dispatch-formulation" => "acp",
        "skip" => ["stability"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["8"]["702"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [11783.8, 11723.8, 10337.1]; atol=1e3))
    @test all(isapprox.(args["fault_studies_results"]["8"]["702"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [7492.97, 7492.97]; atol=5e3))
    @test all(isapprox.(args["fault_studies_results"]["8"]["702"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [6395.87]; atol=1e3))

    @test all(isapprox.(args["output_data"]["Fault currents"][8]["702"]["3p"]["1"]["switch"]["671700"]["|I| (A)"], [3377.51, 3407.76, 3111.84]; atol=1e3))
    @test all(isapprox.(args["output_data"]["Fault currents"][8]["702"]["ll"]["1"]["switch"]["671700"]["|I| (A)"], [2380.69, 4488.38, 2481.67]; atol=1e3))
    @test all(isapprox.(args["output_data"]["Fault currents"][8]["702"]["lg"]["1"]["switch"]["671700"]["|I| (A)"], [2077.65, 1220.18, 1418.96]; atol=1e3))

    @test all(isapprox.(args["output_data"]["Fault currents"][8]["702"]["lg"]["1"]["switch"]["671700"]["|V| (V)"], [1.22373, 3.17669, 2.82304]; atol=1e-1))
end
