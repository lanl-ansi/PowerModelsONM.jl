@testset "depreciated arguments" begin
    raw_args = Dict{String,Any}(
        "network-file" => "../test/data/ieee13_feeder.dss",
        "output-file" => "../test/data/test_output.json",
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

    append!(Base.ARGS, String[
        "-n", "../test/data/ieee13_feeder.dss",
        "-o", "../test/data/test_output.json",
        "-f", "../test/data/ieee13_faults.json",
        "-i", "../test/data/ieee13_inverters.json",
        "-s", "../test/data/ieee13_settings.json",
        "-e", "../test/data/ieee13_events.json",
        "-q",
        "-v",
        "-d",
        "-g",
        "--opt-disp-formulation", "acr",
        "--opt-disp-solver", "misocp_solver",
        "-p", "opf",
        "--protection-settings", "../test/data/protection_settings.xlsx",
        "--solver-tolerance", "0.0001",
        "--max-switch-actions", "1",
        "--timestep-hours", "1",
        "--voltage-lower-bound", "0.9",
        "--voltage-upper-bound", "1.1",
        "--voltage-angle-difference", "5",
        "--clpu-factor", "2",
        "--skip", "faults, stability",
        "--pretty-print",
        "--disable-presolver",
        "--disable-isolation-constraint",
        "--disable-radial-constraint",
        "--disable-inverter-constraint",
        ]
    )

    args = parse_commandline()
    delete!(args, "raw_args")

    @test args == Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "output" => "../test/data/test_output.json",
        "faults" => "../test/data/ieee13_faults.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
        "quiet" => true,
        "verbose" => true,
        "debug" => true,
        "gurobi" => true,
        "opt-disp-formulation" => "acr",
        "opt-disp-solver" => "misocp_solver",
        "problem" => "opf",
        "protection-settings" => "../test/data/protection_settings.xlsx",
        "solver-tolerance" => 1e-4,
        "max-switch-actions" => 1,
        "timestep-hours" => 1.0,
        "voltage-lower-bound" => 0.9,
        "voltage-upper-bound" => 1.1,
        "voltage-angle-difference" => 5.0,
        "clpu-factor" => 2.0,
        "skip" => String["faults", "stability"],
        "pretty-print" => true,
        # flags are always stored, even if not set
        "use-gurobi" => false,
        "opt-switch-formulation" => "lindistflow",
        "opt-switch-algorithm" => "global",
        "opt-switch-problem" => "block",
        "opt-switch-solver" => "misocp_solver",
        "opt-disp-algorithm" => "opf",
        "disable-presolver" => true,
        "disable-isolation-constraint" => true,
        "disable-radial-constraint" => true,
        "disable-inverter-constraint" => true,
    )
end
