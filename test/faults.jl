@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "faults" => "../test/data/faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [22500.0, 24400.0, 21500.0]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [18200.0, 18200.0]; atol=1e2))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [14200.0]; atol=1e2))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["3p"]["1"]["switch"]["701702"]["|I| (A)"], [5670.0, 6880.0, 5910.0]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["ll"]["1"]["switch"]["701702"]["|I| (A)"], [6690.0, 5500.0, 193.0]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|I| (A)"], [4510.0, 2200.0, 1490.0]; atol=1e1))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|V| (V)"], [0.15, 2.51, 2.36]; atol=1e-2))
end
