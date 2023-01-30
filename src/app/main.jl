"""
    julia_main()

PackageCompiler entrypoint
"""
function julia_main()::Cint
    try
        entrypoint(parse_commandline())
    catch e
        print(e)
        return 1
    end

    return 0
end


"""
    entrypoint(args::Dict{String,<:Any})::Dict{String,Any}

The main ONM Algorithm, performs the following steps:

- [`initialize_output!`](@ref initialize_output!)
- [`sanitize_args!`](@ref sanitize_args!)
- [`setup_logging!`](@ref setup_logging!)
- [`prepare_data!`](@ref prepare_data!)
- [`build_solver_instances!`](@ref build_solver_instances!)
- [`optimize_switches!`](@ref optimize_switches!)
- [`optimize_dispatch!`](@ref optimize_dispatch!)
- [`run_stability_analysis!`](@ref run_stability_analysis!)
- [`run_fault_studies!`](@ref run_fault_studies!)
- [`analyze_results!`](@ref analyze_results!)

If `args["debug"]` a file containing all data, results, etc. will be written to "debug_onm_yyyy-mm-dd--HH-MM-SS.json"

Returns the full data structure contains all inputs and outputs.
"""
function entrypoint(args::Dict{String,<:Any})::Dict{String,Any}
    initialize_output!(args)

    sanitize_args!(args)

    setup_logging!(args)

    prepare_data!(args)

    build_solver_instances!(args)

    if !("switching" in get_setting(args, ("options","problem","skip"), String[]))
        optimize_switches!(args)
    end

    if !("dispatch" in get_setting(args, ("options","problem","skip"), String[]))
        optimize_dispatch!(args)
    end

    if !("stability" in get_setting(args, ("options","problem","skip"), String[])) && haskey(args, "inverters") && !isempty(args["inverters"])
        run_stability_analysis!(args)
    end

    if !("faults" in get_setting(args, ("options","problem","skip"), String[]))
        run_fault_studies!(args)
    end

    analyze_results!(args)

    !validate_output(args["output_data"]) && @warn "Output data structure failed to validate against its schema:\n$(evaluate_output(args["output_data"]))"

    if !isempty(get(args, "output", ""))
        write_json(args["output"], args["output_data"]; indent=get_setting(args, ("options","outputs","pretty-print"), false) ? 2 : missing)
    end

    if get_setting(args, ("options","outputs","debug-output"),false)
        write_json("debug_onm_$(Dates.format(Dates.now(), "yyyy-mm-dd--HH-MM-SS")).json", args; indent=get_setting(args, ("options","outputs","pretty-print"), false) ? 2 : missing)
    end

    return args
end


"""
    prepare_data!(args::Dict{String,<:Any})::Dict{String,Any}

Performs the data preparation actions

- [`parse_network`](@ref parse_network!)
- [`parse_events!`](@ref parse_events!)
- [`parse_settings!`](@ref parse_settings!)

"""
function prepare_data!(args::Dict{String,<:Any})::Dict{String,Any}
    parse_network!(args)

    parse_settings!(args)

    parse_events!(args)

    return args
end
