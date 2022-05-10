@testset "deprecated arguments" begin
    raw_args = Dict{String,Any}(
        "quiet" => true,
        "verbose" => true,
        "debug" => true,
        "opt-disp-algorithm" => true,
        "opt-disp-formulation" => true,
        "opt-disp-solver" => true,
        "opt-switch-algorithm" => true,
        "opt-switch-problem" => true,
        "opt-switch-solver" => true,
        "opt-switch-formulation" => true,
        "disable-isolation-constraint" => true,
        "disable-radial-constraint" => true,
        "disable-inverter-constraint" => true,
        "disable-presolver" => true,
        "disable-networking" => true,
        "fix-small-numbers" => true,
        "disable-switch-penalty" => true,
        "apply-switch-scores" => true,
        "nprocs" => 2,
    )

    args = sanitize_args!(deepcopy(raw_args))

    @test args["log-level"] == "debug" && !haskey(args, "quiet") && !haskey(args, "verbose") && !haskey(args, "debug")

    @test all(haskey(args, k) && args[k] == raw_args[k] for k in [
        "opt-disp-algorithm",
        "opt-disp-formulation",
        "opt-disp-solver",
        "opt-switch-algorithm",
        "opt-switch-problem",
        "opt-switch-solver",
        "opt-switch-formulation",
        "disable-switch-penalty",
        "apply-switch-scores",
        "disable-isolation-constraint",
        "disable-radial-constraint",
        "disable-inverter-constraint",
        "disable-presolver",
        "disable-networking",
        "fix-small-numbers",
        "nprocs"
    ])

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
        "--skip", "faults, stability",
        "--pretty-print",
        "--disable-presolver",
        "--disable-isolation-constraint",
        "--disable-radial-constraint",
        "--disable-inverter-constraint",
        ]
    )

    args = sanitize_args!(parse_commandline())
    delete!(args, "raw_args")

    @test args == Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "output" => "../test/data/test_output.json",
        "faults" => "../test/data/ieee13_faults.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
        "log-level" => "debug",
        "gurobi" => true,
        "knitro" => false,
        "opt-disp-formulation" => "acr",
        "opt-disp-solver" => "misocp_solver",
        "skip" => String["faults", "stability"],
        "pretty-print" => true,
        # flags are always stored, even if not set
        "opt-switch-formulation" => "lindistflow",
        "opt-switch-algorithm" => "global",
        "opt-switch-problem" => "block",
        "opt-switch-solver" => "mip_solver",
        "opt-disp-algorithm" => "opf",
        "disable-presolver" => true,
        "disable-isolation-constraint" => true,
        "disable-radial-constraint" => true,
        "disable-inverter-constraint" => true,
        "disable-networking" => false,
        "fix-small-numbers" => false,
        "apply-switch-scores" => false,
        "disable-switch-penalty" => false,
        "nprocs" => 1,
    )
end
