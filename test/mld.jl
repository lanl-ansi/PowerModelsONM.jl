@testset "test optimal switching" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "events" => "../test/data/ieee13_events.json",
        "quiet" => true,
        "skip" => ["faults", "stability", "dispatch"],
        "opt-switch-solver" => "mip_solver",
    )

    @testset "test iterative optimal switching" begin
        @testset "test iterative optimal switching - lindistflow - block" begin
            args = deepcopy(orig_args)
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-algorithm"] = "iterative"
            args["opt-switch-problem"] = "block"

            entrypoint(args)

            @test get_timestep_device_actions!(args) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))] || get_timestep_device_actions!(args) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test iterative optimal switching - lindistflow - traditional" begin
            args = deepcopy(orig_args)
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-algorithm"] = "iterative"
            args["opt-switch-problem"] = "traditional"

            entrypoint(args)

            @test get_timestep_device_actions!(args) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => ["801"], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "open", "671692" => "closed", "671700" => "closed", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test iterative optimal switching - nfa - block" begin
            args = deepcopy(orig_args)
            args["opt-switch-formulation"] = "nfa"
            args["opt-switch-algorithm"] = "iterative"
            args["opt-switch-problem"] = "block"

            entrypoint(args)

            @test get_timestep_device_actions!(args) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "closed", "703800" => "open", "800801" => "closed", "701702" => "closed"))]
        end

        @testset "test iterative optimal switching - nfa - traditional" begin
            args = deepcopy(orig_args)
            args["opt-switch-formulation"] = "nfa"
            args["opt-switch-algorithm"] = "iterative"
            args["opt-switch-problem"] = "traditional"

            entrypoint(args)

            @test get_timestep_device_actions!(args) == Dict{String, Any}[Dict("Shedded loads" => ["692_3", "675b", "675a", "692_1", "702", "703", "675c"], "Switch configurations" => Dict("801675" => "open", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["701", "702", "700", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "open")), Dict("Shedded loads" => ["702", "703"], "Switch configurations" => Dict("801675" => "closed", "671692" => "open", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "open", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "open", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "closed", "800801" => "closed", "701702" => "closed")), Dict("Shedded loads" => String[], "Switch configurations" => Dict("801675" => "closed", "671692" => "closed", "671700" => "open", "703800" => "closed", "800801" => "closed", "701702" => "closed"))]
        end
    end

    @testset "test global optimal switching" begin
        @testset "test global optimal switching - lindistflow - block" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-problem"] = "block"

            entrypoint(args)

            @test args["optimal_switching_results"]["5"]["solution"]["load"]["801"]["status"] == PMD.DISABLED
            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 81.07; atol=1)
        end

        @testset "test global optimal switching - lindistflow - traditional" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-problem"] = "traditional"

            entrypoint(args)

            @test args["optimal_switching_results"]["5"]["solution"]["load"]["801"]["status"] == PMD.DISABLED
            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 81.07; atol=1)
        end

        @testset "test global optimal switching - lindistflow - block - radial-disabled - inverter-disabled" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-problem"] = "block"
            args["disable-radial-constraint"] = true
            args["disable-inverter-constraint"] = true

            entrypoint(args)

            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 79.54; atol=1)
        end

        @testset "test global optimal switching - lindistflow - traditional - radial-disabled - inverter-disabled" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "lindistflow"
            args["opt-switch-problem"] = "traditional"
            args["disable-radial-constraint"] = true
            args["disable-inverter-constraint"] = true

            entrypoint(args)

            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 78.90; atol=1)
        end

        @testset "test global optimal switching - nfa - block" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "nfa"
            args["opt-switch-problem"] = "block"

            entrypoint(args)

            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 69.66; atol=1)
        end

        @testset "test global optimal switching - nfa - traditional" begin
            args = deepcopy(orig_args)
            args["opt-switch-algorithm"] = "global"
            args["opt-switch-formulation"] = "nfa"
            args["opt-switch-problem"] = "traditional"

            entrypoint(args)

            @test isapprox(args["optimal_switching_results"]["1"]["objective"], 69.66; atol=1)
        end

        @testset "test robust switching - lindistflow - block" begin

            eng = PMD.parse_file("../test/data/ieee13_feeder.dss")
            solver = JuMP.optimizer_with_attributes(
                HiGHS.Optimizer,
                "presolve"=>"on",
                "primal_feasibility_tolerance"=>1e-6,
                "dual_feasibility_tolerance"=>1e-6,
                "mip_feasibility_tolerance"=>1e-4,
                "mip_rel_gap"=>1e-4,
                "small_matrix_value"=>1e-8,
                "allow_unbounded_or_infeasible"=>true,
                "log_to_console"=>false,
                "output_flag"=>false
            )
            PMD.apply_voltage_bounds!(eng)
            math = transform_data_model(eng)

            result = solve_robust_block_mld(math,PMD.LPUBFDiagPowerModel,solver,5,0.05)

            @test result["termination_status"] == LOCALLY_SOLVED
            @test isapprox(result["objective"], 9.928; atol = 1e-3)

        end
    end
end
