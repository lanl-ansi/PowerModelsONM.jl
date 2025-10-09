function ravens_run_pmp(data, devices)

    data["m"] = true
    data_math = PMP.transform_data_model_mc_ravens(deepcopy(data))
    PMP.get_source_graph!(data_math, "ConnectivityNode.$(devices["Storage"]["node"])")
    gens = deepcopy(data_math["gen"])

    # to remove solar
    for (i, gen) in gens
        if gen["admit_model"] == PMP.VoltageSource ||  gen["admit_model"] == PMP.PVSystem
            delete!(data_math["gen"], i)
        end
    end

    model = PMP.instantiate_mc_admittance_model(data_math; loading=true)

    solution_analysis = Dict("AnalysisResult" => Dict{String, Any}())

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


        if (bus["bus_type"] != 4)

            for i_indx in 1:length(bus["terminals"])
                for j_indx in 1:length(bus["terminals"])
                    i = model.data["admittance_map"][(bus["bus_i"],bus["terminals"][i_indx])]
                    j = model.data["admittance_map"][(bus["bus_i"],bus["terminals"][j_indx])]
                    y[i,j] += gf[i_indx,j_indx]
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
            y = transformer["p_matrix"][5:8,1:8]
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
            iabc = y*_v
            i012 = inv(PMP._A) * iabc[1:3]
            i012 = i012./(sum(abs.(i012))/2199)
            if abs(i012[3]) > 2199*.4
                i012[2] = (abs(i012[2])+abs(i012[3])-2199*.4)*exp(1im * angle(i012[2]))
                i012[3] = 2199*.4*exp(1im * angle(i012[3]))
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
                    i = model.data["admittance_map"][(bus["bus_i"],bus["terminals"][i_indx])]
                    j = model.data["admittance_map"][(bus["bus_i"],bus["terminals"][j_indx])]
                    y[i,j] += gf[i_indx,j_indx]
                end
            end
            sol, v = PMP.compute_mc_pf(deepcopy(mmm), y)
            for (i, bus) in sol["bus"]
                if bus["name"] == "ConnectivityNode.$(devices["Storage"]["node"])"
                    # v_012 = inv(PMP._A) * v_abc
                    f_bus = data_math["bus"]["$(transformer["f_bus"])"]
                    t_bus = data_math["bus"]["$(transformer["t_bus"])"]
                    _y = transformer["p_matrix"][5:8,1:8]
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
                    iabc = _y*_v
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
                                "AvVoltage.angle" => angle(vabc[i])*180/pi,
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
                                "AvCurrent.angle" => angle(iabc[i])*180/pi,
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

                    iabc = -1*branch["p_matrix"] * _v
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
                                "AvVoltage.angle" => angle(_v[i+3])*180/pi,
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
                                "AvCurrent.angle" => angle(iabc[i+3])*180/pi,
                                "Ravens.cimObjectType" => "AvCurrent",
                            )
                        )
                        push!(solution_fault["OperationsResult.CurrentFlows"], current)

                    end
                end
            end

        else
            for (i, bus) in data_math["bus"]
                if bus["name"] == "ConnectivityNode.$(devices["Storage"]["node"])"
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
                                "AvVoltage.v" => 0.0,
                                "AvVoltage.angle" => 0.0,
                                "Ravens.cimObjectType" => "AvVoltage",
                            )
                        )
                        push!(solution_fault["OperationsResult.Voltages"], voltage)

                        current = Dict(
                            "Ravens.cimObjectType" => "ArCurrentFlow",
                            "ArCurrent.ConnectivityNode" => "BatteryUnit::'$(devices["Storage"]["name"])'",
                            "AnalysisResultData.phase" => p_name,
                            "AnalysisResultData.DataValues" => Dict(
                                "AvCurrent.i" => 0.0,
                                "AvCurrent.angle" => 0.0,
                                "Ravens.cimObjectType" => "AvCurrent",
                            )
                        )
                        push!(solution_fault["OperationsResult.CurrentFlows"], current)
                    end
                elseif bus["name"] == "ConnectivityNode.$(devices["Recloser"]["node"])"
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
                                "AvVoltage.v" => 0.0,
                                "AvVoltage.angle" => 0.0,
                                "Ravens.cimObjectType" => "AvVoltage",
                            )
                        )
                        push!(solution_fault["OperationsResult.Voltages"], voltage)

                        current = Dict(
                            "Ravens.cimObjectType" => "ArCurrentFlow",
                            "ArCurrent.ConnectivityNode" => "Recloser::'$(devices["Recloser"]["name"])'",
                            "AnalysisResultData.phase" => p_name,
                            "AnalysisResultData.DataValues" => Dict(
                                "AvCurrent.i" => 0.0,
                                "AvCurrent.angle" => 0.0,
                                "Ravens.cimObjectType" => "AvCurrent",
                            )
                        )
                        push!(solution_fault["OperationsResult.CurrentFlows"], current)

                    end
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
    pm = instantiate_onm_model(math, NFAUPowerModel, build_block_mld);

    # Create and fill the dictionary that contains the MG groups
    microgrid_groups = Dict{String,Any}()

    for (b, bid) in pm.ref[:it][:pmd][:nw][0][:microgrid_blocks]
        microgrid_groups["Microgrid.$bid"] = Dict{String,Any}(
            "Ravens.cimObjectType" => "Microgrid",
            "IdentifiedObject.name" => "Microgrid.$bid",
            "IdentifiedObject.mRID" => "#_$(uppercase(string(UUIDs.uuid4())))",
            "ConnectivityNodeContainer.ConnectivityNodes" => ["ConnectivityNode::'$(pm.ref[:it][:pmd][:nw][0][:bus][bus]["name"])'" for bus in pm.ref[:it][:pmd][:nw][0][:blocks][b] if !startswith(pm.ref[:it][:pmd][:nw][0][:bus][bus]["name"], "_virtual")]

        )
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
        newdict = Dict{String, Dict{String, Any}}()
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
        newdict = Dict{String, Dict{String, Any}}()
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
        newdict = Dict{String, Dict{String, Any}}()
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
        newdict = Dict{String, Dict{String, Any}}()
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
    new_node_dict = Dict{String, Dict{String, Any}}()
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
