@testset "test optimal switching" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
    )
    prepare_data!(orig_args)
    set_setting!(orig_args, ("options", "outputs", "log-level"), "error")
    set_setting!(orig_args, ("solvers", "HiGHS", "mip_feasibility_tolerance"), 1e-6)
    set_setting!(orig_args, ("solvers", "HiGHS", "primal_feasibility_tolerance"), 1e-8)
    set_setting!(orig_args, ("solvers", "HiGHS", "dual_feasibility_tolerance"), 1e-8)
    set_setting!(orig_args, ("solvers", "HiGHS", "presolve"), "on")
    set_setting!(orig_args, ("options", "objective", "enable-switch-state-open-cost"), true)

    # DEBUGGING
    # set_settings!(orig_args, Dict(("options", "outputs", "log-level")=>"info", ("solvers", "HiGHS", "output_flag")=>true))
    # set_settings!(orig_args, Dict(("solvers", "useGurobi")=>true))
    # set_setting!(orig_args, ("options", "outputs", "log-level"), "info")

    build_solver_instances!(orig_args)

    @testset "test rolling-horizon optimal switching" begin
        @testset "test rolling-horizon optimal switching - lindistflow - block" begin
            @info "    test rolling-horizon optimal switching - lindistflow - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "lindistflow",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "block",
                ("options", "objective", "enable-switch-state-open-cost") => true,
            ))
            delete!(args, "solvers")
            build_solver_instances!(args)

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 176.86; atol=1)
        end

        @testset "test rolling-horizon optimal switching - lindistflow - traditional" begin
            @info "    test rolling-horizon optimal switching - lindistflow - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "lindistflow",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "traditional",
                ("options", "objective", "enable-switch-state-open-cost") => true,
            ))
            delete!(args, "solvers")
            build_solver_instances!(args)

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 176.86; atol=1)
        end

        @testset "test rolling-horizon optimal switching - nfa - block" begin
            @info "    test rolling-horizon optimal switching - nfa - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "nfa",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "block",
                ("options", "objective", "enable-switch-state-open-cost") => true,
            ))

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 109.94; atol=1)
        end

        @testset "test rolling-horizon optimal switching - nfa - traditional" begin
            @info "    test rolling-horizon optimal switching - nfa - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "nfa",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "traditional",
                ("options", "objective", "enable-switch-state-open-cost") => true,
            ))

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 109.94; atol=1)
        end
    end

    @testset "test full-lookahead optimal switching" begin
        @testset "test full-lookahead optimal switching - lindistflow - block" begin
            @info "    test full-lookahead optimal switching - lindistflow - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "block",
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            @test isapprox(r["1"]["objective"], 82.06; atol=1)
        end

        @testset "test full-lookahead optimal switching - lindistflow - traditional" begin
            @info "    test full-lookahead optimal switching - lindistflow - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "traditional",
                ("options", "constraint", "disable-block-isolation-constraint") => true,
                ("solvers", "HiGHS", "presolve") => "off",
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            # TODO There is a difference between MacOS and Linux objective result for this problem using HiGHS, why?
            # @test isapprox(r["1"]["objective"], 82.06; atol=1)
            # @test isapprox(r["1"]["objective"], 378.47; atol=1)
        end

        @testset "test full-lookahead optimal switching - lindistflow - block - radial-disabled - inverter-disabled" begin
            @info "    test full-lookahead optimal switching - lindistflow - block - radial-disabled - inverter-disabled"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "block",
                ("options", "constraints", "disable-radiality-constraint") => true,
                ("options", "constraints", "disable-grid-forming-inverter-constraint") => true,
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            @test isapprox(r["1"]["objective"], 80.64; atol=1)
        end

        @testset "test full-lookahead optimal switching - lindistflow - traditional - radial-disabled - inverter-disabled" begin
            @info "    test full-lookahead optimal switching - lindistflow - traditional - radial-disabled - inverter-disabled"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "traditional",
                ("options", "constraints", "disable-radiality-constraint") => true,
                ("options", "constraints", "disable-grid-forming-inverter-constraint") => true,
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            @test isapprox(r["1"]["objective"], 80.65; atol=1)
        end

        @testset "test full-lookahead optimal switching - nfa - block" begin
            @info "    test full-lookahead optimal switching - nfa - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "NFAUPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "block",
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            @test isapprox(r["1"]["objective"], 72.52; atol=1)
        end

        @testset "test full-lookahead optimal switching - nfa - traditional" begin
            @info "    test full-lookahead optimal switching - nfa - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "NFAUPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "traditional",
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL
            @test isapprox(r["1"]["objective"], 72.52; atol=1)
        end

        @testset "test robust switching - lindistflow - block" begin
            @info "    test robust switching - lindistflow - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "robust",
                ("options", "problem", "operations-problem-type") => "block",
            ))

            r = optimize_switches!(args)

            @test isapprox(r["1"]["objective"], 25.5; atol=1)
        end
    end
end


@testset "test radiality " begin
    solver = build_solver_instances(;solver_options=Dict{String,Any}("HiGHS"=>Dict{String,Any}("output_flag"=>false, "presolve"=>"off")))["mip_solver"]
    eng_s = parse_file("../test/data/network.ieee13mod.dss")

    eng_s["time_elapsed"] = 1.0
    eng_s["switch_close_actions_ub"] = Inf

    PMD.apply_voltage_bounds!(eng_s; vm_lb=0.9, vm_ub=1.1)
    PMD.apply_voltage_angle_difference_bounds!(eng_s, 10.0)
    PMD.adjust_line_limits!(eng_s, Inf)
    PMD.adjust_transformer_limits!(eng_s, Inf)

    for switch in values(eng_s["switch"])
        switch["dispatchable"] = YES
        switch["state"] = CLOSED
        switch["status"] = ENABLED
    end

    for t in ["storage", "solar", "generator"]
        for obj in values(eng_s[t])
            obj["inverter"] = GRID_FOLLOWING
        end
    end

    set_option!(eng_s, ("options", "objective", "disable-load-block-weight-cost"), true)
    set_option!(eng_s, ("options", "objective", "disable-storage-discharge-cost"), true)
    set_option!(eng_s, ("options", "objective", "disable-generation-dispatch-cost"), true)

    r = solve_block_mld(eng_s, LPUBFDiagPowerModel, solver)

    @test r["solution"]["switch"]["680675"]["state"] != r["solution"]["switch"]["671692"]["state"]
    @test length(filter(x->x.second["state"]==OPEN, r["solution"]["switch"])) == 2
    @test r["objective"] < 1.0

    eng_s["switch"]["680675"]["state"] = OPEN

    r = solve_block_mld(eng_s, LPUBFDiagPowerModel, solver)

    @test r["solution"]["switch"]["680675"]["state"] == OPEN
    @test r["solution"]["switch"]["671692"]["state"] == OPEN
    @test length(filter(x->x.second["state"]==OPEN, r["solution"]["switch"])) == 2
    @test r["objective"] < 1.0

    eng_s["switch"]["680675"]["state"] = CLOSED
    eng_s["switch"]["671692"]["state"] = OPEN

    r = solve_block_mld(eng_s, LPUBFDiagPowerModel, solver)

    @test r["solution"]["switch"]["680675"]["state"] == OPEN
    @test r["solution"]["switch"]["671692"]["state"] == OPEN
    @test length(filter(x->x.second["state"]==OPEN, r["solution"]["switch"])) == 2
    @test r["objective"] < 1.0

    eng_s["switch"]["680675"]["state"] = OPEN
    eng_s["switch"]["671692"]["state"] = OPEN

    r = solve_block_mld(eng_s, LPUBFDiagPowerModel, solver)

    @test (r["solution"]["switch"]["680675"]["state"] != r["solution"]["switch"]["671692"]["state"]) || (r["solution"]["switch"]["680675"]["state"] == OPEN)
    @test length(filter(x->x.second["state"]==OPEN, r["solution"]["switch"])) == 2
    @test r["objective"] < 1.0

    eng_s["switch"]["680675"]["dispatchable"] = NO
    eng_s["switch"]["671692"]["dispatchable"] = NO

    r = solve_block_mld(eng_s, LPUBFDiagPowerModel, solver)

    @test r["solution"]["switch"]["680675"]["state"] == r["solution"]["switch"]["671692"]["state"]
    @test length(filter(x->x.second["state"]==OPEN, r["solution"]["switch"])) == 2
    @test r["objective"] < 1.0
end
