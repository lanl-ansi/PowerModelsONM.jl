function run_onm_ravens(ravens_file,
    solver;
    onm_results_file::String="",
    fault_network_file::String="",
    multinetwork::Bool=true,
    algorithm::String="rolling-horizon",
    time_elapsed::Float64=1.0,
    switch_actions_per_ts::Int64=1,
    measured_devices::Dict{String,Any}=Dict{String,Any}(),# TODO: this will be included into ravens_file (RAVENS-JSON)
    optional_fixes::Dict{String,Any}=Dict{String,Any}(),
    prune_mg_section::Bool=false,
    run_protection::Bool=false,
    save_intermediate::Bool=false,
    disable_energysource::Bool=true,
    simulate_islanding::Bool=true,
    zero_gen_costs::Bool=true,
    dispatchable_capacitors::Bool=true,
    )

    # TODO: temporary
    if !multinetwork
        error("Only multinetwork problems are supported.")
    end

    # Extract file name to be used for writing the output file
    filename_with_ext = basename(ravens_file)
    filename, _ = splitext(filename_with_ext)

    # Parse and transform RAVENS file to MATH model
    network_data = parse_file(ravens_file)# Parses the JSON (RAVENS) file
    math = transform_data_model_ravens(network_data; multinetwork=multinetwork)

    # initialize result dictinary in MATH
    result_math = Dict()

    if onm_results_file == ""
        # Correct state of switches and fuses
        for (nw, nw_data) in math["nw"]
            for sw in values(nw_data["switch"])
                # Forcefully keep certain Fuses OPEN
                if (sw["name"] in get(optional_fixes, "fuses_to_open", []))
                    sw["state"] = Int(PMD.OPEN)
                    sw["dispatchable"] = Int(PMD.NO)
                end

                if simulate_islanding
                    if (nw == "1")
                        if sw["dispatchable"] == Int(PMD.YES)
                            sw["state"] = Int(PMD.OPEN)
                            sw["dispatchable"] = Int(PMD.NO)
                        end
                    else
                        if sw["dispatchable"] == Int(PMD.YES)
                            if (sw["name"] in get(optional_fixes, "switches_to_fix", []))
                                sw["dispatchable"] = Int(PMD.NO)
                                sw["state"] = Int(PMD.OPEN)
                            else
                                sw["dispatchable"] = Int(PMD.YES)
                                sw["state"] = Int(PMD.OPEN)
                            end
                        end
                    end
                end
            end
            for (gen, gen_data) in nw_data["gen"]
                if disable_energysource
                    if occursin("_virtual_gen.energy_source", gen_data["name"])
                        @info "Slack Bus Gen. (Substation) #: $(gen) status changed to 0 (DISABLED)."
                        gen_data["gen_status"] = Int(PMD.DISABLED)
                    end
                end
                # fix pmain
                gen_data["pmin"] = gen_data["pmin"] .* 0.0
            end

            nw_data["time_elapsed"] = time_elapsed

            nw_data["switch_close_actions_ub"] = switch_actions_per_ts
            nw_data["options"] = Dict{String,Any}(
                "objective" => Dict{String,Any}(
                    "disable-generation-dispatch-cost" => zero_gen_costs,
                    "disable-storage-discharge-cost" => zero_gen_costs,
                    "disable-switch-state-change-cost" => true,
                ),
                "constraints" => Dict{String,Any}(
                    "disable-grid-forming-inverter-constraint" => true,
                    "disable-storage-unbalance-constraint" => true,
                    "disable-radiality-constraint" => false,
                    # "disable-current-limit-constraints" => true,
                    # "disable-thermal-limit-constraints" => true,
                ),
                "data" => Dict{String,Any}(
                    "switch-close-actions-ub" => switch_actions_per_ts,
                ),
                "variables" => Dict{String,Any}(
                # "unbound-line-power" => true,
                # "unbound-line-current" => true,
                # "unbound-transformer-power" => true,
                # "unbound-switch-power" => true,
                # "unbound-voltage" => true,
                )
            )

            if dispatchable_capacitors
                for (i,shunt) in nw_data["shunt"]
                    shunt["dispatchable"] = Int(PMD.YES)
                end
            end
        end

        math["time_elapsed"] = time_elapsed

        # Solve ONM rolling horizon
        if algorithm == "rolling-horizon"
            # Rolling Horizon
            ns = sort([parse(Int, i) for i in keys(math["nw"])])
            results = Dict{String,Any}()
            result_math = Dict{String,Any}("solution" => Dict{String,Any}("nw" => Dict{String,Any}()))

            for n in ns
                if haskey(results, "$(n-1)") && haskey(results["$(n-1)"], "solution")
                    _update_switch_settings!(math["nw"]["$n"], results["$(n-1)"]["solution"])
                    _update_storage_capacity!(math["nw"]["$n"], results["$(n-1)"]["solution"])
                end

                pmd = instantiate_onm_model(math["nw"]["$n"], LPUBFDiagPowerModel, build_block_mld)
                JuMP.set_optimizer(pmd.model, solver)
                JuMP.optimize!(pmd.model)
                results["$n"] = IM.build_result(pmd, JuMP.solve_time(pmd.model); solution_processors=_default_solution_processors)

                # used for transforming solution
                result_math["solution"]["nw"]["$n"] = deepcopy(results["$n"]["solution"])
            end
        elseif algorithm == "full-lookahead"
            # Full Lookahead Algorithm
            for (nw, nw_data) in math["nw"]
                nw_data["options"]["problem"] = Dict{String,Any}("operations-algorithm" => "full-lookahead")
            end
            pmd_mn = instantiate_onm_model_ravens(math, LPUBFDiagPowerModel, build_mn_block_mld; multinetwork=multinetwork)
            JuMP.set_optimizer(pmd_mn.model, solver)
            JuMP.optimize!(pmd_mn.model)
            result_math = IM.build_result(pmd_mn, JuMP.solve_time(pmd_mn.model); solution_processors=_default_solution_processors)

        else
            error("Algorithm not supported for  Use a supported algorithm: rolling-horizon or full-lookahead")
        end

    else
        _vals_correct_map = ["DISABLED", "ENABLED", "OPEN", "CLOSED", "GRID_FORMING", "GRID_FOLLOWING"]
        _correction_map = Dict(
            "DISABLED" => PMD.DISABLED,
            "ENABLED" => PMD.ENABLED,
            "OPEN" => PMD.OPEN,
            "CLOSED" => PMD.CLOSED,
            "GRID_FORMING" => GRID_FORMING,
            "GRID_FOLLOWING" => GRID_FOLLOWING
        )

        result_math = JSON.parsefile(onm_results_file)

        # Correct MATH result (convert strings to ONM values)
        if multinetwork
            result = result_math["solution"]["nw"]
        else
            result = result_math["solution"]
        end

        elements = ["storage", "transformer", "gen", "bus", "switch", "load", "branch"]
        for (nw, nw_data) in result
            for (elmnt, elmnt_data) in nw_data
                if (elmnt in elements)
                    for (dvc, dvc_data) in elmnt_data
                        for (val, val_data) in dvc_data
                            if (val_data in _vals_correct_map)
                                dvc_data[val] = _correction_map[val_data]
                            end
                        end
                    end
                end
            end
        end
    end

    # Transform MATH solution to RAVENS-JSON solution format
    result_transfr = PMD.transform_solution_ravens(result_math["solution"], math; fix_switch_states=true)

    # Merge network RAVENS dictionary with PF Analytics results RAVENS dictionary
    merged_dictionary = merge(network_data, result_transfr)

    shed_consumers = [keys(filter(x -> x.second["status"] == PMD.DISABLED, result_math["solution"]["nw"]["$n"]["load"])) for n in sort(parse.(Int, collect(keys(result_math["solution"]["nw"]))))]
    @warn [length(x) for x in shed_consumers] shed_consumers

    fault_studies_results = missing
    # Fault studies
    if run_protection
        if multinetwork
            # ------------ Update Process and Fault Studies ----------
            nws = length(result_math["solution"]["nw"])
            nw_upd_sols = Vector{Dict}(undef, nws)  # vector of ravens dictionaries
            fault_studies_results = Vector{Dict}(undef, nws)  # vector of ravens dictionaries
            for nw in 1:1:length(nw_upd_sols)
                nw_upd_sols[nw] = deepcopy(merged_dictionary)

                #  studies
                update_solution_switch_states_ravens!(nw_upd_sols[nw], nw)
                update_solution_equipment_statuses_ravens!(nw_upd_sols[nw], nw)
                update_solution_equipment_powerflows_ravens!(nw_upd_sols[nw], nw)

                if save_intermediate
                    open("./$(filename)-wONM_nw-$(nw).json", "w") do f
                        JSON.print(f, nw_upd_sols[nw], 2)
                    end
                end

                # Run fault studies - TODO: Temporary solution to pass in specific file, since direct ONM output is not working
                if fault_network_file == ""
                    if prune_mg_section
                        group_data = define_microgrid_section(network_data, get(optional_fixes, "switches_MG_limit", []))    # run function to add MG group
                        nw_upd_sols[nw]["Group"] = deepcopy(group_data)     # Update the group data in network
                        prune_network!(nw_upd_sols[nw])     # prune network data based on MG group
                    end

                    fault_results = ravens_run_pmp(nw_upd_sols[nw])
                else
                    data_fault = JSON.parsefile(fault_network_file)
                    fault_results = ravens_run_pmp(data_fault, measured_devices)
                end

                if save_intermediate
                    open("./$(filename)-wONM_nw-$(nw)_fault-results.json", "w") do f
                        JSON.print(f, fault_results, 2)
                    end
                end

                fault_studies_results[nw] = deepcopy(fault_results)
            end

            ravens_faults_results = convert_faults2ravens(fault_studies_results, math, network_data)
            merge_fault_results!(merged_dictionary, ravens_faults_results)
        else
            error("Single step not supported yet!")
        end
    end

    delete!(merged_dictionary, "switch_close_actions_ub")

    open("./$(filename)-wONM$(run_protection ? "-wPMP" : "")-Combined.json", "w") do f
        JSON.print(f, merged_dictionary, 2)
    end

    return Dict("math" => math, "ravens" => merged_dictionary, "raw_fault_results"=>fault_studies_results)
end
