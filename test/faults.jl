@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [11872.0, 11626.0, 10331.0]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [8612.0, 8612.0]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["702"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [6348.0]; atol=1e2))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["3p"]["1"]["switch"]["671700"]["|I| (A)"], [3486.9, 3600.17, 3321.74]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["ll"]["1"]["switch"]["671700"]["|I| (A)"], [2475.4, 4143.17, 2300.95]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["lg"]["1"]["switch"]["671700"]["|I| (A)"], [2134.33, 1124.02, 1581.26]; atol=1e1))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["702"]["lg"]["1"]["switch"]["671700"]["|V| (V)"], [1.21938, 3.18223, 2.83371]; atol=1e-2))
end
