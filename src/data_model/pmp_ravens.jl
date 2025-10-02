function ravens_run_pmp(data, devices)

    data["m"] = true
    data_math = PMP.transform_data_model_mc_ravens(data)
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

        solution_analysis["AnalysisResult"]["$(name)"] = deepcopy(solution_fault)

    end

    return solution_analysis

end
