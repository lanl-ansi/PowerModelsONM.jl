function ravens_run_pmp(data)
    data_math = PMP.transform_data_model_mc_ravens(data)

    # @warn "" filter(x->x.second["status"]==1, data_math["load"])
    model = PMP.instantiate_mc_admittance_model(data_math; loading=true)

    PMP.get_pre_solve!(model)

    faults = PMP.update_build_mc_fault_study(model.data)
    results = PMP.perform_mc_fault_study(model, faults)

    # @warn "" faults

    return Dict("faults" => faults, "results" => results)
end

_get_name(source_id::String)::String = string(split(source_id, "."; limit=2)[end])
_get_type(source_id::String)::String = string(split(source_id, "."; limit=2)[1])

function convert_faults2ravens(faults_results_nw::Vector{Dict}, math_nw::Dict{String,<:Any}, ravens_data::Dict{String,<:Any}; resistance::Real=0.01, phase_resistance::Real=0.01)
    return Dict{String,Any}(
        "Fault" => _build_ravens_faults(faults_results_nw, math_nw; resistance=resistance, phase_resistance=phase_resistance),
        "AnalysisResult" => _build_ravens_mn_fault_results(faults_results_nw, ravens_data),
    )
end

function merge_fault_results!(ravens_data, faults_results::Dict{String,Any})
    ravens_data["Fault"] = deepcopy(faults_results["Fault"])

    for (k,v) in get(faults_results, "AnalysisResult", Dict())
        ravens_data["AnalysisResult"][k] = deepcopy(v)
    end
end


function _build_ravens_faults(faults_results_nw::Vector{Dict}, math_nw::Dict{String,Any}; resistance::Real=0.01, phase_resistance::Real=0.01)
    faults = Dict{String,Any}()

    fault_kinds = Dict{String,String}(
        "lg" => "PhaseConnectedFaultKind.lineToGround",
        "3p" => "PhaseConnectedFaultKind.threePhase",
        "ll" => "PhaseConnectedFaultKind.lineToLine",
        "3pg" => "PhaseConnectedFaultKind.threePhaseToGround",
        "llg" => "PhaseConnectedFaultKind.lineToLineToGround",
    )

    for (n, nw) in enumerate(faults_results_nw)
        for (bus, fts) in get(nw, "faults", Dict())
            cn = string(split(math_nw["nw"]["$n"]["bus"][bus]["source_id"], "."; limit=2)[end])
            for (ft, fs) in fts
                for (i, f) in fs
                    name = "$(cn)_$(ft)_$(i)"
                    phases = join([Dict(1 => "A", 2 => "B", 3 => "C")[c] for c in sort(filter(x -> x != 4, f["connections"]))])

                    faults[name] = Dict{String,Any}(
                        "Ravens.cimObjectType" => "Fault",
                        "IdentifiedObject.mRID" => "$(UUIDs.uuid4())",
                        "IdentifiedObject.name" => name,
                        "Fault.phases" => "PhaseCode.$(phases)",
                        "Fault.kind" => fault_kinds[ft],
                        "Fault.impedance" => Dict{String,Any}(
                            "Ravens.cimObjectType" => "FaultImpedance",
                            "IdentifiedObject.mRID" => "$(UUIDs.uuid4())",
                        ),
                        "Fault.FaultyEquipment" => "ConnectivityNode::'$(cn)'"
                    )

                    if ft == "ll" || ft == "3p"
                        faults[name]["Fault.impedance"]["FaultImpedance.rLineToLine"] = phase_resistance
                    elseif ft == "lg"
                        faults[name]["Fault.impedance"]["FaultImpedance.rGround"] = resistance
                    elseif ft == "3pg" || ft == "llg"
                        faults[name]["Fault.impedance"]["FaultImpedance.rLineToLine"] = phase_resistance
                        faults[name]["Fault.impedance"]["FaultImpedance.rGround"] = resistance
                    end
                end
            end
        end
    end

    return faults
end

function _build_ravens_voltage_curve_base(bus::String, single_phase_kind::String)
    return Dict{String,Any}(
        "Ravens.cimObjectType" => "ArVoltage",
        "ArVoltage.ConnectivityNode" => "ConnectivityNode::'$(bus)'",
        "AnalysisResultData.phase" => "SinglePhaseKind.$(single_phase_kind)",
        "AnalysisResultData.Curve" => Dict{String,Any}(
            "Ravens.cimObjectType" => "AnalysisResultCurve",
            "AnalysisResultCurve.xUnit":"UnitSymbol.h",
            "AnalysisResultCurve.CurveDatas" => [],
        )
    )
end

function _build_ravens_voltage_curvedata(h::Real, v::Real, angle::Real)
    return Dict{String,Any}(
        "Ravens.cimObjectType" => "ArCurveData",
        "ArCurveData.xvalue" => h,
        "ArCurveData.DataValues" => Dict{String,Any}(
            "Ravens.cimObjectType" => "AvVoltage",
            "AvVoltage.v" => v,
            "AvVoltage.angle" => angle,)
    )
end

function _build_ravens_currentflow_curve_base(cond_equip_type::String, cond_equip_name::String, single_phase_kind::String)
    return Dict{String,Any}(
        "Ravens.cimObjectType" => "ArCurrentFlow",
        "ArCurrentFlow.ConductingEquipment" => "$(cond_equip_type)::'$(cond_equip_name)'",
        "AnalysisResultData.phase" => "SinglePhaseKind.$(single_phase_kind)",
        "AnalysisResultData.Curve" => Dict{String,Any}(
            "Ravens.cimObjectType" => "AnalysisResultCurve",
            "AnalysisResultCurve.xUnit" => "UnitSymbol.h",
            "AnalysisResultCurve.CurveDatas" => [],
        )
    )
end

function _build_ravens_currentflow_curvedata(h::Real, ir::Real, ii::Real, end_num::Int)
    return Dict{String,Any}(
        "Ravens.cimObjectType" => "ArCurveData",
        "ArCurveData.xvalue" => h,
        "ArCurveData.DataValues" => Dict{String,Any}(
            "Ravens.cimObjectType" => "AvCurrentFlow",
            "AvCurrentFlow.currentReal" => ir,
            "AvCurrentFlow.currentImaginary" => ii,
            "AvCurrentFlow.endNumber" => end_num
        )
    )
end

function _build_ravens_mn_fault_results(faults_results_nw::Vector{Dict}, ravens_data::Dict{String,Any})
    results = Dict{String,Any}()

    touched = Dict()

    for (n, nw) in enumerate(faults_results_nw)
        for (fault_bus, fault_types) in nw["results"]
            cn = _get_name(fault_bus)
            for (fault_type, faults) in fault_types
                for (fault_id, fault) in faults
                    fault_name = "$(cn)_$(fault_type)_$(fault_id)"
                    fault_results_name = "$(fault_name)_Results"

                    if !haskey(results, fault_results_name)
                        results[fault_results_name] = Dict{String,Any}(
                            "Ravens.cimObjectType" => "FaultStudyResult",
                            "IdentifiedObject.name" => fault_results_name,
                            "IdentifiedObject.mRID" => "$(UUIDs.uuid4())",
                            "FaultStudyResult.Fault" => "Fault::'$fault_name'",
                            "OperationsResult.Voltages" => Dict{String,Any}[],
                            "OperationsResult.CurrentFlows" => Dict{String,Any}[],
                        )
                    end

                    for r_type in ["branch", "switch"]
                        for (name, branch) in fault[r_type]
                            for (i, side) in enumerate(["fr", "to"])
                                if r_type == "branch"
                                    rdata = get(ravens_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Conductor"]["ACLineSegment"][_get_name(name)]["ConductingEquipment.Terminals"][i], "Terminal.phases", "PhaseCode.ABC")
                                else
                                    rdata = get(ravens_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][_get_name(name)]["ConductingEquipment.Terminals"][i], "Terminal.phases", "PhaseCode.ABC")
                                end
                                for (k, c) in enumerate(replace(rdata, "PhaseCode." => ""))
                                    key = (fault_name, "ArCurrentFlow", "$(_get_type(name))::'$(_get_name(name))'", "SinglePhaseKind.$(c)")
                                    if !haskey(touched, key)
                                        push!(results[fault_results_name]["OperationsResult.CurrentFlows"], _build_ravens_currentflow_curve_base(_get_type(name), _get_name(name), "$c"))
                                        touched[key] = length(results[fault_results_name]["OperationsResult.CurrentFlows"])
                                    end

                                    z = branch["$(side)_mag"][k] * cis(branch["$(side)_ang"][k])
                                    ir = real(z)
                                    ii = imag(z)
                                    push!(results[fault_results_name]["OperationsResult.CurrentFlows"][touched[key]]["AnalysisResultData.Curve"]["AnalysisResultCurve.CurveDatas"], _build_ravens_currentflow_curvedata(n, ir, ii, i))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end


function ravens_run_pmp_old(data, devices)
    data["m"] = true
    data_math = PMP.transform_data_model_mc_ravens(data)
    gens = deepcopy(data_math["gen"])

    # to remove solar
    for (i, gen) in gens
        if gen["admit_model"] == PMP.VoltageSource || gen["admit_model"] == PMP.PVSystem
            delete!(data_math["gen"], i)
        end
    end

    model = PMP.instantiate_mc_admittance_model(data_math; loading=true)

    solution_analysis = Dict("AnalysisResult" => Dict{String,Any}())

    for (name, fault) in data["Fault"]
        solution_fault = Dict(
            "Ravens.cimObjectType" => "FaultStudyResult",
            "IdentifiedObject.name" => name,
            "IdentifiedObject.mRID" => fault["IdentifiedObject.mRID"],
            "FaultStudyResult.Fault" => "Fault::'$(name)'",
            "OperationsResult.Voltages" => [],
            "OperationsResult.CurrentFlows" => [],
        )

        phases = PMD._phasecode_map[fault["Fault.phases"]]
        rg = fault["Fault.impedance"]["FaultImpedance.rGround"]
        rll = fault["Fault.impedance"]["FaultImpedance.rLineToLine"]
        fault_bus = PMD._extract_name(fault["Fault.FaultyEquipment"])
        fault_type = fault["Fault.kind"]
        if fault_type == "PhaseConnectedFaultKind.threePhase"
            gf = PMP.build_mc_3p_gf(model, phases; phase_resistance=rll)
        elseif fault_type == "PhaseConnectedFaultKind.lineToGround"
            gf = PMP.build_mc_lg_gf(model, phases; ground_resistance=rg)
        elseif fault_type == "PhaseConnectedFaultKind.lineToLine"
            gf = PMP.build_mc_ll_gf(model, phases; phase_resistance=rll)
        end
        y = deepcopy(model.y)
        indx = 0
        for (i, bus) in model.data["bus"]
            if bus["name"] == fault_bus
                indx = i
            end
        end
        bus = data_math["bus"][indx]

        for i_indx in 1:length(bus["terminals"])
            for j_indx in 1:length(bus["terminals"])
                i = model.data["admittance_map"][(bus["bus_i"], bus["terminals"][i_indx])]
                j = model.data["admittance_map"][(bus["bus_i"], bus["terminals"][j_indx])]
                y[i, j] += gf[i_indx, j_indx]
            end
        end
        sol, v = PMP.compute_mc_pf(deepcopy(model), y)

        indx = 0
        for (t, transformer) in data_math["transformer"]
            if transformer["name"] == "transformer.$(devices["Storage"]["device"]["name"])"
                indx = t
            end
        end
        transformer = data_math["transformer"][indx]
        f_bus = data_math["bus"]["$(transformer["f_bus"])"]
        t_bus = data_math["bus"]["$(transformer["t_bus"])"]
        y = transformer["p_matrix"][5:8, 1:8]
        _v = zeros(Complex{Float64}, 8, 1)
        indx = 1
        for (_j, j) in enumerate(f_bus["terminals"])
            if haskey(data_math["admittance_map"], (f_bus["bus_i"], j))
                _v[indx, 1] = v[data_math["admittance_map"][(f_bus["bus_i"], j)], 1]
            else
                _v[indx, 1] = 0.0
            end
            indx += 1
        end
        indx += 1
        for (_j, j) in enumerate(t_bus["terminals"])
            if haskey(data_math["admittance_map"], (t_bus["bus_i"], j))
                _v[indx, 1] = v[data_math["admittance_map"][(t_bus["bus_i"], j)], 1]
            else
                _v[indx, 1] = 0.0
            end
            indx += 1
        end
        iabc = y * _v
        i012 = inv(PMP._A) * iabc[1:3]
        i012 = i012 ./ (sum(abs.(i012)) / 2199)
        if abs(i012[3]) > 2199 * 0.4
            i012[2] = (abs(i012[2]) + abs(i012[3]) - 2199 * 0.4) * exp(1im * angle(i012[2]))
            i012[3] = 2199 * 0.4 * exp(1im * angle(i012[3]))
        end
        iabc = PMP._A * i012
        d = deepcopy(data)
        d["m"] = false
        dm = PMP.transform_data_model_mc_ravens(deepcopy(d))
        dm["storage"]["1"]["set"] = iabc
        mmm = PMP.instantiate_mc_admittance_model(dm; loading=true)
        y = deepcopy(mmm.y)
        for i_indx in 1:length(bus["terminals"])
            for j_indx in 1:length(bus["terminals"])
                i = model.data["admittance_map"][(bus["bus_i"], bus["terminals"][i_indx])]
                j = model.data["admittance_map"][(bus["bus_i"], bus["terminals"][j_indx])]
                y[i, j] += gf[i_indx, j_indx]
            end
        end
        sol, v = PMP.compute_mc_pf(deepcopy(mmm), y)
        for (i, bus) in sol["bus"]
            if bus["name"] == "ConnectivityNode.$(devices["Storage"]["node"])"
                # v_012 = inv(PMP._A) * v_abc
                f_bus = data_math["bus"]["$(transformer["f_bus"])"]
                t_bus = data_math["bus"]["$(transformer["t_bus"])"]
                _y = transformer["p_matrix"][5:8, 1:8]
                _v = zeros(Complex{Float64}, 8, 1)
                indx = 1
                for (_j, j) in enumerate(f_bus["terminals"])
                    if haskey(data_math["admittance_map"], (f_bus["bus_i"], j))
                        _v[indx, 1] = v[data_math["admittance_map"][(f_bus["bus_i"], j)], 1]
                    else
                        _v[indx, 1] = 0.0
                    end
                    indx += 1
                end
                indx += 1
                for (_j, j) in enumerate(t_bus["terminals"])
                    if haskey(data_math["admittance_map"], (t_bus["bus_i"], j))
                        _v[indx, 1] = v[data_math["admittance_map"][(t_bus["bus_i"], j)], 1]
                    else
                        _v[indx, 1] = 0.0
                    end
                    indx += 1
                end
                iabc = _y * _v
                vabc = _v[5:7]
                for i in phases
                    if i == 1
                        p_name = "SinglePhaseKind.A"
                    elseif i == 2
                        p_name = "SinglePhaseKind.B"
                    elseif i == 3
                        p_name = "SinglePhaseKind.C"
                    end
                    voltage = Dict(
                        "Ravens.cimObjectType" => "ArVoltage",
                        "ArVoltage.ConnectivityNode" => "BatteryUnit::'$(devices["Storage"]["name"])'",
                        "AnalysisResultData.phase" => p_name,
                        "AnalysisResultData.DataValues" => Dict(
                            "AvVoltage.v" => abs(vabc[i]),
                            "AvVoltage.angle" => angle(vabc[i]) * 180 / pi,
                            "Ravens.cimObjectType" => "AvVoltage",
                        )
                    )
                    push!(solution_fault["OperationsResult.Voltages"], voltage)

                    current = Dict(
                        "Ravens.cimObjectType" => "ArCurrentFlow",
                        "ArCurrent.ConnectivityNode" => "BatteryUnit::'$(devices["Storage"]["name"])'",
                        "AnalysisResultData.phase" => p_name,
                        "AnalysisResultData.DataValues" => Dict(
                            "AvCurrent.i" => abs(iabc[i]),
                            "AvCurrent.angle" => angle(iabc[i]) * 180 / pi,
                            "Ravens.cimObjectType" => "AvCurrent",
                        )
                    )
                    push!(solution_fault["OperationsResult.CurrentFlows"], current)
                end
            elseif bus["name"] == "ConnectivityNode.$(devices["Recloser"]["node"])"
                indx = 0
                for (t, branch) in data_math["branch"]
                    if branch["name"] == devices["Recloser"]["device"]["name"]
                        indx = t
                    end
                end
                branch = data_math["branch"][indx]
                _v = zeros(Complex{Float64}, 6, 1)
                indx = 1
                t_bus = data_math["bus"]["$(branch["t_bus"])"]
                for (_j, j) in enumerate(t_bus["terminals"])
                    if haskey(data_math["admittance_map"], (branch["f_bus"], j))
                        _v[indx, 1] = v[data_math["admittance_map"][(branch["f_bus"], j)], 1]
                    else
                        _v[indx, 1] = 0.0
                    end
                    indx += 1
                end
                for (_j, j) in enumerate(t_bus["terminals"])
                    if haskey(data_math["admittance_map"], (branch["t_bus"], j))
                        _v[indx, 1] = v[data_math["admittance_map"][(branch["t_bus"], j)], 1]
                    else
                        _v[indx, 1] = 0.0
                    end
                    indx += 1
                end

                iabc = -1 * branch["p_matrix"] * _v
                for i in phases
                    if i == 1
                        p_name = "SinglePhaseKind.A"
                    elseif i == 2
                        p_name = "SinglePhaseKind.B"
                    elseif i == 3
                        p_name = "SinglePhaseKind.C"
                    end
                    voltage = Dict(
                        "Ravens.cimObjectType" => "ArVoltage",
                        "ArVoltage.ConnectivityNode" => "Recloser::'$(devices["Recloser"]["name"])'",
                        "AnalysisResultData.phase" => p_name,
                        "AnalysisResultData.DataValues" => Dict(
                            "AvVoltage.v" => abs(_v[i+3]),
                            "AvVoltage.angle" => angle(_v[i+3]) * 180 / pi,
                            "Ravens.cimObjectType" => "AvVoltage",
                        )
                    )
                    push!(solution_fault["OperationsResult.Voltages"], voltage)

                    current = Dict(
                        "Ravens.cimObjectType" => "ArCurrentFlow",
                        "ArCurrent.ConnectivityNode" => "Recloser::'$(devices["Recloser"]["name"])'",
                        "AnalysisResultData.phase" => p_name,
                        "AnalysisResultData.DataValues" => Dict(
                            "AvCurrent.i" => abs(iabc[i+3]),
                            "AvCurrent.angle" => angle(iabc[i+3]) * 180 / pi,
                            "Ravens.cimObjectType" => "AvCurrent",
                        )
                    )
                    push!(solution_fault["OperationsResult.CurrentFlows"], current)

                end
            end
        end

        solution_analysis["AnalysisResult"]["$(name)"] = deepcopy(solution_fault)

    end

    return solution_analysis

end




########## Temporary Functions to 1) deliniate/define an MG section from entire network, and 2) cut/prune the network to contain only that MG section. ########

function define_microgrid_section(network_data, switch_limits)

    # Open switches at the MG limit
    for s in switch_limits
        if haskey(network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][s], "Switch.SwitchPhase")
            network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][s]["Switch.SwitchPhase"][1]["SwitchPhase.closed"] = false
        else
            network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][s]["Switch.open"] = true
        end
        network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][s]["Switch.locked"] = true
    end

    # Transform to MATH model
    math = transform_data_model_ravens(network_data)

    # Make all switches/fuses/etc. non-dispatchable
    for sw in values(math["switch"])
        sw["dispatchable"] = Int(NO)
    end

    # Instantiate ONM model to identify MG blocks
    pm = instantiate_onm_model(math, NFAUPowerModel, build_block_mld)

    # Create and fill the dictionary that contains the MG groups
    microgrid_groups = Dict{String,Any}()

    for (b, bid) in pm.ref[:it][:pmd][:nw][0][:microgrid_blocks]
        microgrid_groups["Microgrid.$bid"] = Dict{String,Any}(
            "Ravens.cimObjectType" => "Microgrid",
            "IdentifiedObject.name" => "Microgrid.$bid",
            "IdentifiedObject.mRID" => "#_$(uppercase(string(UUIDs.uuid4())))",
            "ConnectivityNodeContainer.ConnectivityNodes" => ["ConnectivityNode::'$(pm.ref[:it][:pmd][:nw][0][:bus][bus]["name"])'" for bus in pm.ref[:it][:pmd][:nw][0][:blocks][b] if !startswith(pm.ref[:it][:pmd][:nw][0][:bus][bus]["name"], "_virtual")])
    end

    # Merge with Group
    if !haskey(network_data, "Group")
        network_data["Group"] = Dict()
        network_data["Group"]["ConnectivityNodeContainer"] = Dict()
        push!(network_data["Group"]["ConnectivityNodeContainer"], microgrid_groups)
    else
        merge!(network_data["Group"]["ConnectivityNodeContainer"], microgrid_groups)
    end

    return network_data["Group"]

end



function prune_network!(network_data)

    conn_nodes_refs = network_data["Group"]["ConnectivityNodeContainer"]["Microgrid.1"]["ConnectivityNodeContainer.ConnectivityNodes"]

    if !haskey(network_data["Group"]["ConnectivityNodeContainer"]["Microgrid.1"], "EquipmentContainer.Equipments")
        network_data["Group"]["ConnectivityNodeContainer"]["Microgrid.1"]["EquipmentContainer.Equipments"] = []
    end

    equipments_refs = network_data["Group"]["ConnectivityNodeContainer"]["Microgrid.1"]["EquipmentContainer.Equipments"]

    conn_nodes = String[]
    for cn in conn_nodes_refs
        push!(conn_nodes, _extract_name(cn))
    end


    #---- Set of Equipment to Prune -----
    # 1) EnergyConnections
    energy_connections = network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]
    energyconn_type = ["EnergySource", "EnergyConsumer"]
    for ec in energyconn_type
        newdict = Dict{String,Dict{String,Any}}()
        for (name_obj, ravens_obj) in get(energy_connections, ec, Dict{Any,Dict{String,Any}}())
            conn_node_ref = ravens_obj["ConductingEquipment.Terminals"][1]["Terminal.ConnectivityNode"]
            conn_node = _extract_name(conn_node_ref)
            if conn_node in conn_nodes
                name_to_add = "$(ec)::'$(name_obj)'"
                push!(equipments_refs, name_to_add)
                newdict["$(name_obj)"] = ravens_obj
            end
        end
        # Replace with new dictionary
        energy_connections[ec] = newdict
    end


    # RegulatingCondEquipment
    regulating_cond = network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"]
    # regcondeq_type = ["PowerElectronicsConnection", "RotatingMachine"]
    regcondeq_type = ["PowerElectronicsConnection"]
    for rc in regcondeq_type
        newdict = Dict{String,Dict{String,Any}}()
        for (name_obj, ravens_obj) in get(regulating_cond, rc, Dict{Any,Dict{String,Any}}())
            conn_node_ref = ravens_obj["ConductingEquipment.Terminals"][1]["Terminal.ConnectivityNode"]
            conn_node = _extract_name(conn_node_ref)
            if conn_node in conn_nodes
                if (rc == "PowerElectronicsConnection")
                    pec_type = ravens_obj["PowerElectronicsConnection.PowerElectronicsUnit"]["Ravens.cimObjectType"]
                    if (pec_type == "BatteryUnit")
                        name_to_add = "BatteryUnit::'$(name_obj)'"
                    elseif (pec_type == "PhotoVoltaicUnit")
                        name_to_add = "PhotoVoltaicUnit::'$(name_obj)'"
                    else
                        name_to_add = "NONE::'$(name_obj)'"
                    end
                else
                    name_to_add = "$(rc)::'$(name_obj)'"
                end
                push!(equipments_refs, name_to_add)
                newdict["$(name_obj)"] = ravens_obj

            end
        end
        # Replace with new dictionary
        regulating_cond[rc] = newdict
    end


    # 2) Conductor
    conductors = network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Conductor"]
    conductor_type = ["ACLineSegment"]
    for cond in conductor_type
        newdict = Dict{String,Dict{String,Any}}()
        for (name_obj, ravens_obj) in get(conductors, cond, Dict{Any,Dict{String,Any}}())
            conn_node_ref_fr = ravens_obj["ConductingEquipment.Terminals"][1]["Terminal.ConnectivityNode"]
            conn_node_ref_to = ravens_obj["ConductingEquipment.Terminals"][2]["Terminal.ConnectivityNode"]
            conn_node_fr = _extract_name(conn_node_ref_fr)
            conn_node_to = _extract_name(conn_node_ref_to)
            if ((conn_node_fr in conn_nodes) && (conn_node_to in conn_nodes))
                name_to_add = "$(cond)::'$(name_obj)'"
                push!(equipments_refs, name_to_add)
                newdict["$(name_obj)"] = ravens_obj
            end
        end
        # Replace with new dictionary
        conductors[cond] = newdict
    end

    # 3) PowerTransformers and Switches
    cond_equip = network_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]
    equipment_type = ["PowerTransformer", "Switch"]
    for eq in equipment_type
        newdict = Dict{String,Dict{String,Any}}()
        for (name_obj, ravens_obj) in get(cond_equip, eq, Dict{Any,Dict{String,Any}}())
            conn_node_ref_fr = ravens_obj["ConductingEquipment.Terminals"][1]["Terminal.ConnectivityNode"]
            conn_node_ref_to = ravens_obj["ConductingEquipment.Terminals"][2]["Terminal.ConnectivityNode"]
            conn_node_fr = _extract_name(conn_node_ref_fr)
            conn_node_to = _extract_name(conn_node_ref_to)
            if ((conn_node_fr in conn_nodes) && (conn_node_to in conn_nodes))
                name_to_add = "$(eq)::'$(name_obj)'"
                push!(equipments_refs, name_to_add)
                newdict["$(name_obj)"] = ravens_obj
            end
        end
        # Replace with new dictionary
        cond_equip[eq] = newdict
    end

    # ConnectivityNodes
    new_node_dict = Dict{String,Dict{String,Any}}()
    for (name_obj, ravens_obj) in get(network_data, "ConnectivityNode", Dict{Any,Dict{String,Any}}())
        if (name_obj in conn_nodes)
            new_node_dict["$(name_obj)"] = ravens_obj
        end
    end
    # Replace with new dictionary
    network_data["ConnectivityNode"] = new_node_dict

end


function _extract_name(element)
    name = replace(split(element, "::")[2], "'" => "")
    return name
end
