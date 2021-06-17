@testset "depreciated arguments" begin
    raw_args = Dict{String,Any}(
        "network-file" => "../test/data/IEEE13Nodeckt_mod.dss",
        "output-file" => "../test/data/tmp-out.json",
        "problem" => "opf",
        "formulation" => "acr",
        "protection-settings" => "../test/data/protection_settings.xlsx",
        "debug-export-file" => "../test/data/debug.json",
        "use-gurobi" => true,
        "solver-tolerance" => 1e-6,
        "max-switch-actions" => 1,
        "timestep-hours" => 0.1667,
        "voltage-lower-bound" => 0.9,
        "voltage-upper-bound" => 1.1,
        "voltage-angle-difference" => 5.0,
        "clpu-factor" => 2.0,
    )

    args = sanitize_args!(deepcopy(raw_args))

    @test args["network"] == raw_args["network-file"] && !haskey(args, "network-file")
    @test args["output"] == raw_args["output-file"] && !haskey(args, "output-file")
    @test !haskey(args, "problem")
    @test args["opt-disp-formulation"] == raw_args["formulation"] && !haskey(args, "formulation")
    @test !haskey(args, "protection-settings")
    @test args["debug"] && !haskey(args, "debug-export-file")
    @test args["gurobi"] && !haskey(args, "use-gurobi")

    @test all(haskey(args, k) && args[k] == raw_args[k] for k in ["solver-tolerance", "max-switch-actions", "timestep-hours", "voltage-lower-bound", "voltage-upper-bound", "voltage-angle-difference", "clpu-factor"])

    @test haskey(args, "raw_args") && args["raw_args"] == raw_args
end
