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
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 119.89; atol=1)
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
            @test isapprox(sum(Float64[_r["objective"] for _r in values(r)]), 119.89; atol=1)
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
            @test isapprox(r["1"]["objective"], 80.65; atol=1)
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
