function optimize_switches!(mn_data_math::Dict{String,Any})
    cbc_solver = PMD.optimizer_with_attributes(Cbc.Optimizer, "logLevel"=>0)
    ipopt_solver = PMD.optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0, "tol"=>1e-6)
    juniper_solver = PMD.optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>ipopt_solver, "mip_solver"=>cbc_solver, "log_levels"=>[])

    results = Dict{String,Any}()
    for (n,nw) in mn_data_math["nw"]
        nw["per_unit"] = mn_data_math["per_unit"]
        results[n] = run_mc_osw_mi(nw, PMD.LPUBFDiagPowerModel, juniper_solver)
    end

    for (n, result) in results
        for (l, switch) in result["solution"]["switch"]
            mn_data_math["nw"][n]["switch"][l]["state"] = switch["state"]
        end
    end
end

