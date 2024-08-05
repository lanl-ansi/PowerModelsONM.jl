"""
    evaluate_partition_optimality(
        data,
        load_scenarios,
        model_type,
        solver;
        save_partial_results,
        partial_result_folder,
        time_elapsed,
        kwargs...
    )

Function to evaluate the optimality of a specific partition by considering a collection of load scenarios.

`data` has the partition configuration applied.
"""
function evaluate_partition_optimality(
    data::Dict{String,<:Any},
    load_scenarios,
    model_type::Type,
    solver;
    save_partial_results::Bool=false,
    partial_result_folder::String=".",
    time_elapsed::Union{Missing,Real} = missing,
    kwargs...)

    _results = Dict{String,Any}()

    for ls in keys(load_scenarios)
        single_load_scenario = Dict{String,Dict{String,Any}}()
        single_load_scenario["1"] = load_scenarios[ls]

        eng = deepcopy(data)

        if !ismissing(time_elapsed)
            eng["time_elapsed"] = time_elapsed
        end

        @debug "starting load scenario evaluation $(ls)/$(length(load_scenarios))"

        result = solve_robust_block_mld(eng, model_type, solver, single_load_scenario; kwargs...)

        if save_partial_results
            open("$(partial_result_folder)/result_$(ls).json", "w") do io
                JSON.print(io, result)
            end
        end

        _results[ls] = result
    end

    return _results
end


"""
retrieve_load_scenario_optimality(results::Dict)

Returns a Dict of objectives for the different load scenarios considered in the robust partition evaluation.
"""
function retrieve_load_scenario_optimality(results::Dict{String,<:Any})::Dict{String,Real}
    return Dict{String,Real}("$i" => results["$i"]["1"]["objective"] for i in 1:length(results))
end
