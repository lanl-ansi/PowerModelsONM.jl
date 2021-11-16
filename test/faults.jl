@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "faults" => "../test/data/faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], [12969.63,14070.90,12530.36]; atol=1e-1))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], [12447.47, 12447.47]; atol=1e-1))
    @test all(isapprox.(args["fault_studies_results"]["1"]["701"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], [8902.91]; atol=1e-1))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["3p"]["1"]["switch"]["701702"]["|I| (A)"], [6344.89, 7759.84, 6907.49]; atol=1e-1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["ll"]["1"]["switch"]["701702"]["|I| (A)"], [7160.21, 6482.45, 1428.34]; atol=1e-1))
    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|I| (A)"], [4126.85, 1684.03, 1291.03]; atol=1e-1))

    @test all(isapprox.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|V| (V)"], [0.0890292, 2.56719, 2.50076]; atol=1e-1))
end
