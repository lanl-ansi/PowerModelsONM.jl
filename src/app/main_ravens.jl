function run_onm_ravens(ravens_file,
	solver;
    onm_results_file::String="",
	fault_network_file::String="",
    multinetwork::Bool=true,
    algorithm::String="rolling-horizon",
    time_elapsed::Float64=1.0,
    switch_actions_per_ts::Int64=1,
	measured_devices::Dict{String, Any}=Dict{String, Any}(),	# TODO: this will be included into ravens_file (RAVENS-JSON)
	optional_fixes::Dict{String, Any}=Dict{String, Any}(),
    prune_mg_section::Bool=false     # TODO: this is done to try to make HCE work correctly with PMP code.
)

	# TODO: temporary
	if !multinetwork
		error("Only multinetwork problems are supported.")
	end

    # Extract file name to be used for writing the output file
    filename_with_ext = basename(ravens_file)
    filename, _ = splitext(filename_with_ext)

	# Parse and transform RAVENS file to MATH model
	network_data = parse_file(ravens_file)	# Parses the JSON (RAVENS) file
	math = transform_data_model_ravens(network_data; multinetwork=multinetwork)

	# initialize result dictinary in MATH
	result_math = Dict()

	if onm_results_file == ""

		# Correct state of switches and fuses
		for (nw, nw_data) in math["nw"]
			for sw in values(nw_data["switch"])
				# Forcefully keep Fuses OPEN
				if (sw["name"] in optional_fixes["fuses_to_open"])
					sw["state"] = Int(OPEN)
					sw["dispatchable"] = Int(NO)
				end

				if (nw == "1")
					if sw["dispatchable"] == Int(YES)
						sw["state"] = Int(OPEN)
						sw["dispatchable"] = Int(NO)
					end
				else
					if sw["dispatchable"] == Int(YES)
						if (sw["name"] in optional_fixes["switches_to_fix"])
							sw["dispatchable"] = Int(NO)
							sw["state"] = Int(OPEN)
						else
							sw["dispatchable"] = Int(YES)
							sw["state"] = Int(OPEN)
						end
					end
				end
			end
		end

		for (nw, nw_data) in math["nw"]
			for (gen, gen_data) in nw_data["gen"]
                if occursin("_virtual_gen.energy_source", gen_data["name"])
					@info "Slack Bus Gen. (Substation) #: $(gen) status changed to 0 (DISABLED)."
					gen_data["gen_status"] = Int(DISABLED)
				end
			end
		end


		math["time_elapsed"] = time_elapsed
		for (nw, nw_data) in math["nw"]
			nw_data["time_elapsed"] = time_elapsed
		end

		PMD.apply_voltage_bounds_math!(math; vm_lb=0.9, vm_ub=1.1)

		for (nw, nw_data) in math["nw"]
			for (gen, gen_data) in nw_data["gen"]
				gen_data["cost"] = [0.0, 0.0]
			end
		end

		for (nw, nw_data) in math["nw"]
			nw_data["switch_close_actions_ub"] = switch_actions_per_ts
			nw_data["options"] = Dict{String,Any}(
				"objective" => Dict{String,Any}(
				"disable-generation-dispatch-cost" => true,
				"disable-storage-discharge-cost" => true,
				),
				"constraints" => Dict{String,Any}(
				"disable-grid-forming-inverter-constraint" => false,
				"disable-storage-unbalance-constraint" => true,
				"disable-radiality-constraint" => true,
				),
			"data" => Dict{String,Any}(
				"switch-close-actions-ub"=> switch_actions_per_ts,
				)
			)
		end

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
				nw_data["options"]["problem"] = Dict{String,Any}("operations-algorithm"=> "full-lookahead")
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
			"DISABLED" => DISABLED,
			"ENABLED" => ENABLED,
			"OPEN" => OPEN,
			"CLOSED" => CLOSED,
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


	if multinetwork
		# ------------ Update Process and Fault Studies ----------
		nws = length(result_math["solution"]["nw"])
		nw_upd_sols = Vector{Dict}(undef, nws)  # vector of ravens dictionaries
		fault_studies_results = Vector{Dict}(undef, nws)  # vector of ravens dictionaries

        for nw in 1:1:length(nw_upd_sols)
			nw_upd_sols[nw] = deepcopy(merged_dictionary)

			#  studies
            @info "Running Protection Studies @ Timestep nw: $(nw)"
			update_solution_switch_states_ravens!(nw_upd_sols[nw], nw)
			update_solution_equipment_statuses_ravens!(nw_upd_sols[nw], nw)
			update_solution_equipment_powerflows_ravens!(nw_upd_sols[nw], nw)

			# Fault studies
			if (measured_devices != Dict())

				# Run fault studies - TODO: Temporary solution to pass in specific file, since direct ONM output is not working
                if fault_network_file == ""
                    fault_results = ravens_run_pmp(nw_upd_sols[nw], measured_devices)
                else
                    data_fault = JSON.parsefile(fault_network_file)
                    fault_results = ravens_run_pmp(data_fault, measured_devices)
                end

				fault_studies_results[nw] = deepcopy(fault_results)

				# Add results to main RAVENS-JSON data
				analysis_merged = merge(nw_upd_sols[nw]["AnalysisResult"], fault_studies_results[nw]["AnalysisResult"])
				nw_upd_sols[nw]["AnalysisResult"] = analysis_merged

				open("./$(filename)-wONM_wFaults-nw-$(nw).json","w") do f
					JSON.print(f, nw_upd_sols[nw], 2)
				end

			else	# No Fault Studies - Only ONM
				open("./$(filename)-wONM-sols-nw-$(nw).json","w") do f
					JSON.print(f, nw_upd_sols[nw], 2)
				end
			end

		end
	else
		error("Single step not supported yet!")
	end

end
