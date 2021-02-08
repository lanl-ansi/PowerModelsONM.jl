"PackageCompiler entrypoint"
function julia_main()::Cint
    try
        entrypoint(parse_commandline())
    catch e
        print(e)
        return 1
    end

    return 0
end


"command line argument parsing"
function parse_commandline()
    s = ArgParse.ArgParseSettings()

    ArgParse.@add_arg_table! s begin
        "--network-file", "-n"
            help = "the power system network data file"
        "--output-file", "-o"
            help = "path to output file"
            default = "./output.json"
        "--formulation", "-f"
            help = "mathematical formulation to solve (lindistflow (default), acr, acp, nfa)"
            default = "lindistflow"
        "--problem", "-p"
            help = "optimization problem type (opf, mld)"
            default = "opf"
        "--protection-settings"
            help = "XLSX (Excel) File with Protection settings"
            default = ""
        "--events"
            help = "Events (contingencies) file"
            default = ""
        "--verbose", "-v"
            help = "debug messages"
            action = :store_true
        "--solver-tolerance"
            help = "solver tolerance"
            default = 1e-6
        "--export", "-e"
            help = "path to export full PMD results"
            default = ""
            arg_type = String
    end

    return ArgParse.parse_args(s)
end


""
function entrypoint(args::Dict{String,<:Any})
    if !get(args, "verbose", false)
        silence!()
    end

    # Load events
    events = haskey(args, "events") && !isempty(args["events"]) && !isnothing(args["events"]) ? parse_events(args["events"]) : Vector{Dict{String,Any}}([])

    # ENGINEERING MODEL, mutlinetwork and base case with timeseries objects
    (data_eng, mn_data_eng) = prepare_network_case(args["network-file"]; events=events);

    # Initialize output data structure
    output_data = build_blank_output(data_eng)

    # MATHEMATICAL MULTINETWORK MODEL
    mn_data_math = PMD._map_eng2math_multinetwork(mn_data_eng)
    PMD.correct_network_data!(mn_data_math; make_pu=true)

    # NLP Solver to use for Load shed and OPF
    solver = build_solver_instance(args["solver-tolerance"], get(args, "verbose", false))

    # Optimal Load Shed
    result = solve_problem(PMD.solve_mn_mc_mld_simple, mn_data_math, PMD.LPUBFDiagPowerModel, solver; solution_processors=[getproperty(PowerModelsONM, Symbol("sol_ldf2$(args["formulation"])!"))])

    # Apply the results of the load-shed to the MATHEMATICAL MODEL
    apply_load_shed!(mn_data_math, result)

    # Optimal Switching
    if haskey(data_eng, "switch") && !isempty(data_eng["switch"]) && any(sw["dispatchable"] == PMD.YES for (_,sw) in data_eng["switch"])
        osw_result = optimize_switches!(mn_data_math; solution_processors=[getproperty(PowerModelsONM, Symbol("sol_ldf2$(args["formulation"])!"))]);
    end

    # Output switching actions to output data
    get_timestep_device_actions!(output_data, mn_data_math)

    # Final optimal dispatch
    form = get_formulation(args["formulation"])
    problem = get_problem(args["problem"], haskey(mn_data_math, "nw"))
    result = solve_problem(problem, mn_data_math, form, solver; solution_processors=[PMD.sol_data_model!])

    # Build solutions for statistics outputs
    sol_pu, sol_si = transform_solutions(result["solution"], mn_data_math);

    # Building output statistics
    get_timestep_voltage_stats!(output_data, sol_pu, data_eng)
    get_timestep_load_served!(output_data, sol_si, data_eng)
    get_timestep_generator_profiles!(output_data, sol_si)
    get_timestep_powerflow_output!(output_data, sol_si, data_eng)
    get_timestep_storage_soc!(output_data, sol_si, data_eng)

    # Get Protection Settings for Switch settings
    protection_data = haskey(args, "protection-settings") && !isempty(args["protection-settings"]) && !isnothing(args["protection-settings"]) ? parse_protection_tables(args["protection-settings"]) : Dict{NamedTuple,Dict{String,Any}}()
    get_timestep_protection_settings!(output_data, protection_data)

    # Pass events to output data
    output_data["Events"] = events

    # Export final result dict (debugging)
    if !isempty(args["export"])
        open(args["export"], "w") do f
            JSON.print(f, result, 2)
        end
    end

    # Save output data
    open(args["output-file"], "w") do f
        JSON.print(f, output_data, 2)
    end
end


""
function silence!()
    Memento.setlevel!(Memento.getlogger(PowerModelsONM.PMD._PM), "error")
end
