@testset "test optimal switching" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
    )
    prepare_data!(orig_args)
    set_setting!(orig_args, ("options", "outputs", "log-level"), "error")

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
                ("solvers", "HiGHS", "presolve") => "off",
            ))
            delete!(args, "solvers")
            build_solver_instances!(args)

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)

            @test get_timestep_device_actions(args["network"], r) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test rolling-horizon optimal switching - lindistflow - traditional" begin
            @info "    test rolling-horizon optimal switching - lindistflow - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "lindistflow",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "traditional",
                ("solvers", "HiGHS", "presolve") => "off",
            ))
            delete!(args, "solvers")
            build_solver_instances!(args)

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)

            @test get_timestep_device_actions(args["network"], r) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test rolling-horizon optimal switching - nfa - block" begin
            @info "    test rolling-horizon optimal switching - nfa - block"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "nfa",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "block",
            ))

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)

            @test get_timestep_device_actions(args["network"], r) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test rolling-horizon optimal switching - nfa - traditional" begin
            @info "    test rolling-horizon optimal switching - nfa - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "nfa",
                ("options", "problem", "operations-algorithm") => "rolling-horizon",
                ("options", "problem", "operations-problem-type") => "traditional",
            ))

            r = optimize_switches!(args)

            @test all(_r["termination_status"] == OPTIMAL for (n,_r) in r)

            @test get_timestep_device_actions(args["network"], r) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed"))]
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

            @test isapprox(r["1"]["objective"], 83.04; atol=1)
        end

        @testset "test full-lookahead optimal switching - lindistflow - traditional" begin
            @info "    test full-lookahead optimal switching - lindistflow - traditional"
            args = deepcopy(orig_args)
            set_settings!(args, Dict(
                ("options", "problem", "operations-formulation") => "LPUBFDiagPowerModel",
                ("options", "problem", "operations-algorithm") => "full-lookahead",
                ("options", "problem", "operations-problem-type") => "traditional",
            ))

            r = optimize_switches!(args)

            @test first(r).second["termination_status"] == OPTIMAL

            # @test isapprox(r["1"]["objective"], 81.07; atol=1)  # TODO: test is unstable with HiGHS
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

            @test isapprox(r["1"]["objective"], 81.43; atol=1)
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

            @test isapprox(r["1"]["objective"], 81.43; atol=1)
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

            @test isapprox(r["1"]["objective"], 73.26; atol=1)
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

            @test isapprox(r["1"]["objective"], 73.26; atol=1)
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
