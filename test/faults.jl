@testset "test fault study algorithms" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "faults" => "../test/data/faults.json",
        "skip" => ["stability", "dispatch", "switching"],
    )
    entrypoint(args)

    @test round.(args["fault_studies_results"]["1"]["701"]["3p"]["1"]["solution"]["fault"]["1"]["cf"], RoundUp; sigdigits=3) == [13100.0, 14200.0, 13200.0]
    @test round.(args["fault_studies_results"]["1"]["701"]["ll"]["1"]["solution"]["fault"]["1"]["cf"], RoundUp; sigdigits=3) == [12200.0, 12200.0]
    @test round.(args["fault_studies_results"]["1"]["701"]["lg"]["1"]["solution"]["fault"]["1"]["cf"], RoundUp; sigdigits=3) == [9760.0]

    @test round.(args["output_data"]["Fault currents"][1]["701"]["3p"]["1"]["switch"]["701702"]["|I| (A)"], RoundUp; sigdigits=3) == [6600.0, 8280.0, 7280.0]
    @test round.(args["output_data"]["Fault currents"][1]["701"]["ll"]["1"]["switch"]["701702"]["|I| (A)"], RoundUp; sigdigits=3) == [6750.0, 6360.0, 576.0]
    @test round.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|I| (A)"], RoundUp; sigdigits=3) == [4070.0, 1640.0, 1010.0]

    @test round.(args["output_data"]["Fault currents"][1]["701"]["lg"]["1"]["switch"]["701702"]["|V| (V)"], RoundUp; digits=2) == [0.1, 2.61, 2.37]
end
