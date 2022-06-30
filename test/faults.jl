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

@testset "test fault study algorithms - no concurrency" begin
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
    prepare_data!(args)
    set_setting!(args, ("options","problem","concurrent-fault-studies"), false)

    entrypoint(args)

    @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
end

@testset "test fault study algorithms - missing dispatch solution" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "events" => "../test/data/ieee13_events.json",
        "opt-switch-solver" => "mip_solver",
        "opt-switch-algorithm" => "iterative",
        "quiet" => true,
        "skip" => ["stability", "dispatch"],
    )
    entrypoint(args)

    @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
end

@testset "test fault study algorithms - no fault inputs" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
        "opt-switch-solver" => "mip_solver",
        "opt-switch-algorithm" => "iterative",
        "quiet" => true,
        "skip" => ["stability"],
    )
    entrypoint(args)

    @test count_faults(args["faults"]) == 193
end
