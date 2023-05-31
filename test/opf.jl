@testset "test optimal dispatch" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "quiet" => true,
    )
    prepare_data!(orig_args)
    build_solver_instances!(orig_args)

    @testset "test nfa opf" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "dispatch-formulation"), "nfa")

        r = optimize_dispatch!(args)

        @test isapprox(args["optimal_dispatch_result"]["objective"], 4.85; atol=1e-2)

        v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
        @test all(all(v .== 0) for v in values(v_stats))

        disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
        @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)
    end

    @testset "test lindistflow opf" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "dispatch-formulation"), "lindistflow")

        r = optimize_dispatch!(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 4.85; atol=1e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.010, 1.016, 1.004]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.998, 1.023, 0.993]; atol=1e-2))
    end

    @testset "test acr opf" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "dispatch-formulation"), "acr")

        r = optimize_dispatch!(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.013, 1.062, 1.025]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.36, -122.49, 117.39]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.979, 1.085, 1.021]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-4.77, -123.13, 116.81]; atol=1e0))
    end

    @testset "test acp opf" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "dispatch-formulation"), "acp")

        r = optimize_dispatch!(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.013, 1.062, 1.025]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.36, -122.49, 117.39]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.979, 1.085, 1.021]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-4.77, -123.13, 116.81]; atol=1e0))
    end

    @testset "test fix-small-numbers nfa opf" begin
        args = deepcopy(orig_args)

        set_settings!(args, Dict(
            ("options","data","fix-small-numbers") => true,
            ("options","problem","dispatch-formulation") => "nfa"
        ))

        result = optimize_dispatch!(args)

        @test isapprox(result["objective"], 4.85; atol=1e-2)
    end
end

@testset "test optimal dispatch with open switch voltage co-optimization" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
    )
    prepare_data!(args)

    set_settings!(args, Dict(
        ("options", "outputs", "log-level") => "error",
        ("solvers", "Ipopt", "print_level") => 0,
        ("solvers", "Ipopt", "tol") => 1e-8,
        ("solvers", "Ipopt", "sb") => "yes",
        ("options", "constraints", "disable-switch-open-voltage-distance-constaint") => false,
        ("options", "objective", "disable-voltage-distance-slack-cost") => false,
        ("switch", "801675", "vm_delta_pu_ub") => 0.05,
        ("switch", "801675", "va_delta_deg_ub") => 1,
        ("switch", "801675", "state") => OPEN,
        ("switch", "801675", "status") => ENABLED,
        ("options", "problem", "dispatch-formulation") => "acp",
    ))

    build_solver_instances!(args)

    @testset "test opf switch co-optimization with ACP" begin
        r = solve_mn_opf(args["network"], PowerModelsONM.PMD.ACPUPowerModel, args["solvers"]["nlp_solver"]; make_si=false)

        delta_va = Dict(n => abs.(nw["bus"]["801"]["va"].-nw["bus"]["675aux"]["va"]) for (n,nw) in r["solution"]["nw"])
        delta_vm = Dict(n => abs.(nw["bus"]["801"]["vm"].-nw["bus"]["675aux"]["vm"]) for (n,nw) in r["solution"]["nw"])

        @test all(all(dva .- 1.0 .<= 1e-3) for (n,dva) in delta_va)
        @test all(all(dvm .- 0.05 .<= 1e-4) for (n,dvm) in delta_vm)
    end

    @testset "test opf switch co-optimization with ACR" begin
        r = solve_mn_opf(args["network"], PowerModelsONM.PMD.ACRUPowerModel, args["solvers"]["nlp_solver"]; make_si=false)

        delta_va = Dict(n => abs.(nw["bus"]["801"]["va"].-nw["bus"]["675aux"]["va"]) for (n,nw) in r["solution"]["nw"])
        delta_vm = Dict(n => abs.(nw["bus"]["801"]["vm"].-nw["bus"]["675aux"]["vm"]) for (n,nw) in r["solution"]["nw"])

        @test all(all(dva .- 1.0 .<= 1e-3) for (n,dva) in delta_va)
        @test all(all(dvm .- 0.05 .<= 1e-4) for (n,dvm) in delta_vm)
    end

    @testset "test opf switch co-optimization with LPUBF" begin
        r = solve_mn_opf(args["network"], PowerModelsONM.PMD.LPUBFDiagPowerModel, args["solvers"]["nlp_solver"]; make_si=false)

        delta_vm = Dict(n => abs.(nw["bus"]["801"]["vm"].-nw["bus"]["675aux"]["vm"]) for (n,nw) in r["solution"]["nw"])

        @test all(all(dvm .- 0.05 .<= 1e-4) for (n,dvm) in delta_vm)
    end

    @testset "test opf switch co-optimization with NFA" begin
        r = solve_mn_opf(args["network"], PowerModelsONM.PMD.NFAUPowerModel, args["solvers"]["nlp_solver"]; make_si=false)

        @test isapprox(r["objective"], 4.85; atol=1e-2)
    end
end
