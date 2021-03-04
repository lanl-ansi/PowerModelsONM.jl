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
            arg_type = String
        "--output-file", "-o"
            help = "path to output file"
            default = "./output.json"
            arg_type = String
        "--formulation", "-f"
            help = "mathematical formulation to solve (lindistflow (default), acr, acp, nfa)"
            default = "lindistflow"
            arg_type = String
        "--problem", "-p"
            help = "optimization problem type (opf, mld)"
            default = "opf"
            arg_type = String
        "--protection-settings"
            help = "XLSX (Excel) File with Protection settings"
            default = ""
            arg_type = String
        "--faults"
            help = "json file defining faults over which to perform fault study"
            default = ""
            arg_type = String
        "--events"
            help = "Events (contingencies) file"
            default = ""
            arg_type = String
        "--inverters"
            help = "inverter settings file for stability analysis"
            default = ""
            arg_type = String
        "--verbose", "-v"
            help = "debug messages"
            action = :store_true
        "--solver-tolerance"
            help = "solver tolerance"
            default = 1e-4
        "--debug-export-file"
            help = "DEBUG Option: path to export full PMD results"
            default = ""
            arg_type = String
        "--use-gurobi"
            help = "flag to use commercial gurobi solver"
            action = :store_true
    end

    return ArgParse.parse_args(s)
end


""
function entrypoint(args::Dict{String,<:Any})
    if !get(args, "verbose", false)
        silence!()
    end

    # Load events, if any
    events = !isempty(get(args, "events", "")) ? parse_events(args["events"]) : Vector{Dict{String,Any}}([])

    # build ENGINEERING MODEL, both mutlinetwork and base case with timeseries objects
    (data_eng, mn_data_eng) = prepare_network_case(args["network-file"]; events=events);

    # Initialize output data structure
    output_data = build_blank_output(data_eng, args)

    # MATHEMATICAL MULTINETWORK MODEL
    mn_data_math = PMD._map_eng2math_multinetwork(mn_data_eng)
    PMD.correct_network_data!(mn_data_math; make_pu=true)

    # NLP Solver to use for Load shed and OPF
    juniper_solver, nlp_solver, mip_solver = build_solver_instance(args["solver-tolerance"], get(args, "verbose", false); use_gurobi=get(args, "use-gurobi", false))

    # Optimal Switching and Load Shed
    if any(get(sw, "dispatchable", PMD.NO) == PMD.YES for (_,sw) in get(data_eng, "switch", Dict()))
        osw_result = optimize_switches!(mn_data_math, mip_solver; solution_processors=[getproperty(PowerModelsONM, Symbol("sol_ldf2$(args["formulation"])!"))]);

        # Output switching actions to output data
        get_timestep_device_actions!(output_data, mn_data_math)
        propagate_switch_settings!(mn_data_eng, mn_data_math)
    end

    # Final optimal dispatch
    form = get_formulation(args["formulation"])
    problem = get_problem(args["problem"], haskey(mn_data_math, "nw"))
    @info "Running optimal dispatch $problem : $form"
    result = solve_problem(PMD.solve_mn_mc_opf, mn_data_math, form, juniper_solver; solution_processors=[PMD.sol_data_model!])

    # Check if configurations are stable
    if !isempty(get(args, "inverters", ""))
        inverters = parse_inverters(args["inverters"])
        is_stable = analyze_stability(mn_data_eng, inverters, nlp_solver; verbose=get(args, "verbose", false))

        # Output if timesteps are small signal stable or not
        get_timestep_stability!(output_data, is_stable)
    end

    # perform fault studies
    if !isempty(get(args, "faults", ""))
        faults = parse_faults(args["faults"])
        fault_results = run_fault_study(mn_data_math, faults, nlp_solver);

        # Output bus fault currents to output data
        get_timestep_fault_currents!(output_data, fault_results)
    end

    # Build solutions for statistics outputs
    sol_pu, sol_si = transform_solutions(result["solution"], mn_data_math);

    # Building output statistics
    get_timestep_voltage_stats!(output_data, sol_pu, data_eng)
    get_timestep_load_served!(output_data, sol_si, mn_data_eng)
    get_timestep_generator_profiles!(output_data, sol_si)
    get_timestep_powerflow_output!(output_data, sol_si, data_eng)
    get_timestep_storage_soc!(output_data, sol_si, data_eng)

    # Get Protection Settings for Switch settings
    protection_data = !isempty(get(args, "protection-settings", "")) && !isnothing(args["protection-settings"]) ? parse_protection_tables(args["protection-settings"]) : Dict{NamedTuple,Dict{String,Any}}()
    get_timestep_protection_settings!(output_data, protection_data)

    # Pass-through events to output data
    output_data["Events"] = events

    # Export final result dict (debugging)
    if !isempty(args["debug-export-file"])
        write_outputs(args["debug-export-file"], result)
    end

    # Save output data
    write_outputs(args["output-file"], output_data)
end


""
function silence!()
    Memento.setlevel!(Memento.getlogger(PowerModelsONM.PMD._PM), "error")
end
