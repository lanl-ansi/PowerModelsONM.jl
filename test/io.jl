@testset "test io functions" begin
    base_network, network  = parse_network("../test/data/ieee13_feeder.dss");

    @testset "test network parsing" begin
        @test PMD.ismultinetwork(network)
        @test !PMD.ismultinetwork(base_network)
        @test PMD.iseng(network) && PMD.iseng(base_network)

        @test length(network["nw"]) == 8

        @test network["nw"]["1"]["switch"]["671700"]["state"] == PMD.CLOSED
        @test network["nw"]["1"]["switch"]["671700"]["dispatchable"] == PMD.YES
        @test network["nw"]["1"]["switch"]["671700"]["status"] == PMD.ENABLED
    end

    @testset "test events parsing" begin
        raw_events = parse_events("../test/data/ieee13_events.json")
        @test length(raw_events) == 12

        events = parse_events(raw_events, network)
        @test isa(events, Dict) && length(events) == 2
        @test events["1"]["switch"]["671700"]["dispatchable"] == PMD.NO
        @test events["1"]["switch"]["671700"]["state"] == PMD.OPEN
        @test events["1"]["switch"]["671700"]["status"] == PMD.ENABLED

        _network = apply_events(network, events)
        @test _network["nw"]["1"]["switch"]["671700"]["state"] == PMD.OPEN
        @test _network["nw"]["1"]["switch"]["671700"]["dispatchable"] == PMD.NO
        @test _network["nw"]["1"]["switch"]["671700"]["status"] == PMD.ENABLED

        @test _network["nw"]["2"]["switch"]["671700"]["dispatchable"] == PMD.YES

        @test _network["nw"]["3"]["switch"]["671700"]["dispatchable"] == PMD.YES
    end

    @testset "test settings parsing" begin
        settings = parse_settings("../test/data/ieee13_settings.json")

        _network = make_multinetwork(apply_settings(base_network, settings))
        @test all(all(l["clpu_factor"] == 2.0 for l in values(nw["load"])) for nw in values(_network["nw"]))
        @test all(nw["switch_close_actions_ub"] == 1 for nw in values(_network["nw"]))
        @test all(nw["time_elapsed"] == 1.0 for nw in values(_network["nw"]))
    end

    @testset "test runtime args to settings conversion" begin
        args = Dict{String,Any}(
            "nlp_solver_tol" => 1e-4,
            "mip_solver_tol" => 1e-4,
            "mip_solver_gap" => 0.01,
            "max_switch_actions" => 1,
            "time_elapsed" => 0.1667,
            "disable_presolver" => true,
            "disable_networking" => true,
            "disable_radial_constraint" => true,
            "disable_isolation_constraint" => true,
            "disable_inverter_constraint" => true,
            "disable_switch_penalty" => true,
            "apply_switch_scores" => true,
        )
        orig_keys = collect(keys(args))

        settings = correct_settings!(args)

        @test all(!haskey(args, k) for k in orig_keys)

        @test settings["solvers"]["Ipopt"]["tol"] == 1e-4
        @test settings["solvers"]["HiGHS"]["primal_feasibility_tolerance"] == 1e-4
        @test settings["solvers"]["HiGHS"]["mip_rel_gap"] == 0.01
        @test settings["options"]["data"]["time-elapsed"] == 0.1667
        @test settings["options"]["data"]["switch-close-actions-ub"] == 1
        @test settings["options"]["constraints"]["disable-microgrid-networking"]
        @test settings["options"]["constraints"]["disable-radiality-constraint"]
        @test settings["options"]["constraints"]["disable-block-isolation-constraint"]
        @test settings["options"]["constraints"]["disable-grid-forming-inverter-constraint"]
        @test settings["options"]["objective"]["disable-switch-state-change-cost"]
        @test settings["options"]["objective"]["enable-switch-state-open-cost"]

        _network = make_multinetwork(apply_settings(base_network, settings))
        @test all(nw["switch_close_actions_ub"] == 1 for nw in values(_network["nw"]))
        @test all(nw["time_elapsed"] == 0.1667 for nw in values(_network["nw"]))
    end

    @testset "test inverters parsing" begin
        inverters = parse_inverters("../test/data/ieee13_inverters.json")
    end

    @testset "test faults parsing" begin
        faults = parse_faults("../test/data/ieee13_faults.json")

        @test all(fault["status"] == PMD.ENABLED for (bus,fts) in faults for (ft,fids) in fts for (fid,fault) in fids)
        @test all(isa(fault["g"], Matrix) && isa(fault["b"], Matrix) for (bus,fts) in faults for (ft,fids) in fts for (fid,fault) in fids)
        @test all(isa(fault["connections"], Vector{Int}) for (bus,fts) in faults for (ft,fids) in fts for (fid,fault) in fids)
    end

    @testset "test build settings" begin
        custom_settings = Dict{String,Any}(
            "switch" => Dict{String,Any}(
                "801675" => Dict{String,Any}("cm_ub" => [25.0, 25.0, 25.0]),
                "800801" => Dict{String,Any}("cm_ub" => [25.0, 25.0, 25.0])
            ),
            "voltage_source" => Dict{String,Any}(
                "source" => Dict{String,Any}(
                    "pg_lb" => [0.0, 0.0, 0.0],
                    "qg_lb" => [0.0, 0.0, 0.0],
                )
            ),
            "transformer" => Dict{String,Any}(
                    "xfm1" => Dict{String,Any}( "sm_ub" => 25000.0 ),
                    "reg1" => Dict{String,Any}( "sm_ub" => 25000.0 ),
                    "sub" => Dict{String,Any}( "sm_ub" => 25000.0 ),
            ),
        )

        settings = build_settings(
            "../test/data/ieee13_feeder.dss";
            clpu_factor=2.0,
            max_switch_actions=1,
            disable_switch_penalty=false,
            apply_switch_scores=true,
            disable_presolver=false,
            mip_solver_gap=0.0001,
            nlp_solver_tol=0.00001,
            mip_solver_tol=0.00001,
            sbase_default=1000.0,
            vm_lb_pu=0.9,
            vm_ub_pu=1.1,
            vad_deg=5.0,
            line_limit_mult=Inf,
            storage_phase_unbalance_factor=0.0,
            custom_settings=custom_settings
        )

        local_settings = parse_settings("../test/data/ieee13_settings.json")

        @test settings == local_settings

        for (k,v) in settings
            if v != local_settings[k]
                @warn k v local_settings[k]
            end
        end
    end
end
