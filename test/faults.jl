@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "faults" => "../test/data/faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [30200.91,33883.79,29910.65]; atol=1e1))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [12147.52, 12147.52]; atol=1e1))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [8983.76]; atol=1e0))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["3p"]["1"]["switch"]["701702"]["|I| (A)"], [23577.97, 27587.11, 24381.03]; atol=1e1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["ll"]["1"]["switch"]["701702"]["|I| (A)"], [6835.44, 6171.91, 1296.65]; atol=1e0))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|I| (A)"], [4227.64, 1685.20, 1275.87]; atol=1e0))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|V| (V)"], [0.0890292, 2.56719, 2.50076]; atol=1e-2))
end
