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
            help = "mathematical formulation to solve (acr, acp, lindistflow, nfa)"
            default = "lindistflow"
        "--problem", "-p"
            help = "optimization problem type (opf, mld)"
            default = "opf"
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
        Memento.setlevel!(Memento.getlogger(PowerModelsONM.PMD._PM), "error")
    end

    events = haskey(args, "events-file") ? parse_events(args["events-file"]) : Dict{String,Any}()

    data_eng, data_math = prepare_network_case(args["network-file"]; events=events)

    form = get_formulation(args["formulation"])
    problem = get_problem(args["problem"], haskey(data_math, "nw"))

    solver = build_solver_instance(args["solver-tolerance"], get(args, "verbose", false))

    result = solve_problem(problem, data_math, form, solver)

    sol_pu, sol_si = transform_solutions(result["solution"], data_math)

    output_data = build_blank_output(data_eng)

    get_timestep_voltage_stats!(output_data, sol_pu, data_eng)
    get_timestep_load_served!(output_data, sol_si, data_eng)
    get_timestep_generator_profiles!(output_data, sol_si)
    get_timestep_powerflow_output!(output_data, sol_si, data_eng)

    output_data["events"] = events

    if !isempty(args["export"])
        open(args["export"], "w") do f
            JSON.print(f, result, 2)
        end
    end

    open(args["output-file"], "w") do f
        JSON.print(f, output_data, 2)
    end
end
