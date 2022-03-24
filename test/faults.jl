@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [3747.46, 2675.6, 1505.02]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [9781.77, 9781.77]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [10370.8]; atol=1e2))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["3p"]["1"]["switch"]["671700"]["|I| (A)"], [4948.48, 5062.14, 4690.72]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["ll"]["1"]["switch"]["671700"]["|I| (A)"], [2649.87, 3388.17, 1086.72]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["lg"]["1"]["switch"]["671700"]["|I| (A)"], [7925.37, 1602.05, 6577.87]; atol=1e1))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["lg"]["1"]["switch"]["671700"]["|V| (V)"], [2.25208, 4.19198, 2.11782]; atol=1e-2))
end
