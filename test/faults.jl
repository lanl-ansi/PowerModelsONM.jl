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

    @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
end
