function update_solution_switch_states_ravens!(raven_data, nw)

  # Get result dictionaries
  nws_sw_states = raven_data["AnalysisResult"]["OptimalPowerFlow"]["OperationsResult.Switches"]
  # nws_eq_pfs = raven_data["AnalysisResult"]["OptimalPowerFlow"]["OperationsResult.PowerFlows"]

  # Loop through all switches
  for sw_i in 1:1:length(nws_sw_states)

    # Updated information from solution
    sw_name = PMD._extract_name(nws_sw_states[sw_i]["ArSwitch.Switch"])
    sw_upd_open = nws_sw_states[sw_i]["AnalysisResultData.Curve"]["AnalysisResultCurve.CurveDatas"][nw]["ArCurveData.DataValues"]["AvSwitch.open"]

    # Update process on original dictionary
    ravens_sw_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"][sw_name]

    if (haskey(ravens_sw_data, "Switch.SwitchPhase"))
      sw_state = sw_upd_open == true ? false : true
      ravens_sw_data["Switch.SwitchPhase"][1]["SwitchPhase.closed"] = sw_state
    else
      sw_state = sw_upd_open == true ? true : false
      ravens_sw_data["Switch.open"] = sw_state
    end

  end

end


function update_solution_equipment_statuses_ravens!(raven_data, nw)

  # Get result dictionaries
  nws_eq_statuses = raven_data["AnalysisResult"]["OptimalPowerFlow"]["OperationsResult.Statuses"]

  # Loop through all equipment
  for eq_i in 1:1:length(nws_eq_statuses)

    # Updated information from solution
    eq_name = PMD._extract_name(nws_eq_statuses[eq_i]["ArStatus.ConductingEquipment"])
    eq_type = PMD._extract_type(nws_eq_statuses[eq_i]["ArStatus.ConductingEquipment"])

    eq_upd_status = nws_eq_statuses[eq_i]["AnalysisResultData.Curve"]["AnalysisResultCurve.CurveDatas"][nw]["ArCurveData.DataValues"]["AvStatus.inService"]

    # Update process on original dictionary
    if eq_type == "ACLineSegment"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Conductor"][eq_type][eq_name]
    elseif eq_type == "EnergyConsumer"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"][eq_type][eq_name]
    elseif eq_type == "PhotoVoltaicUnit" || eq_type == "BatteryUnit"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"]["PowerElectronicsConnection"][eq_name]
    elseif eq_type == "RotatingMachine"
       ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"][eq_type][eq_name]
    else
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"][eq_type][eq_name]
    end

    ravens_eq_data["Equipment.inService"] = eq_upd_status

  end

end


function update_solution_equipment_powerflows_ravens!(raven_data, nw)

  # Get result dictionaries
  nws_eq_pfs = raven_data["AnalysisResult"]["OptimalPowerFlow"]["OperationsResult.PowerFlows"]

  # Loop through all equipment
  for eq_i in 1:1:length(nws_eq_pfs)

    # Updated information from solution
    eq_type = PMD._extract_type(nws_eq_pfs[eq_i]["ArPowerFlow.ConductingEquipment"])
    # extract name of element
    eq_name = PMD._extract_name(nws_eq_pfs[eq_i]["ArPowerFlow.ConductingEquipment"])

    # P and Q dispatch values to update
    eq_upd_p = nws_eq_pfs[eq_i]["AnalysisResultData.Curve"]["AnalysisResultCurve.CurveDatas"][nw]["ArCurveData.DataValues"]["AvPowerFlow.p"]
    eq_upd_q = nws_eq_pfs[eq_i]["AnalysisResultData.Curve"]["AnalysisResultCurve.CurveDatas"][nw]["ArCurveData.DataValues"]["AvPowerFlow.q"]

    if eq_type == "EnergyConsumer"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"][eq_type][eq_name]
      ravens_eq_data["EnergyConsumer.p"] = eq_upd_p
      ravens_eq_data["EnergyConsumer.q"] = eq_upd_q
    elseif eq_type == "PhotoVoltaicUnit" || eq_type == "BatteryUnit"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"]["PowerElectronicsConnection"][eq_name]
      ravens_eq_data["PowerElectronicsConnection.p"] = eq_upd_p
      ravens_eq_data["PowerElectronicsConnection.q"] = eq_upd_q
    elseif eq_type == "RotatingMachine"
      ravens_eq_data = raven_data["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"][eq_type][eq_name]
      ravens_eq_data["RotatingMachine.p"] = eq_upd_p
      ravens_eq_data["RotatingMachine.p"] = eq_upd_q
    else
      # do nothing
    end

  end

end
