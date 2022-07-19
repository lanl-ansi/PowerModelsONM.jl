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

    @testset "test fault events parsing" begin
        events = parse_events("../test/data/ieee13_fault_events.json", network)

        @test events["1"]["switch"]["701702"]["state"] == PMD.OPEN
        @test events["1"]["switch"]["701702"]["dispatchable"] == PMD.NO
        @test events["1"]["switch"]["703800"]["state"] == PMD.OPEN
        @test events["1"]["switch"]["703800"]["dispatchable"] == PMD.NO
        @test length(events) == 1
        @test length(events["1"]["switch"]) == 2

        _network = apply_events(network, events)

        for (n,nw) in _network["nw"]
            @test nw["switch"]["701702"]["dispatchable"] == PMD.NO
            @test nw["switch"]["703800"]["dispatchable"] == PMD.NO
        end
    end

    @testset "test parse events from args structure with no network" begin
        args = Dict{String,Any}("events" => "../test/data/ieee13_fault_events.json")

        events = parse_events!(args)

        @test isa(events, Vector{Dict{String,Any}})
    end

    @testset "test build events from helper function" begin
        events = build_events(
            base_network;
            default_switch_state=PMD.OPEN,
            default_switch_dispatchable=PMD.NO,
            default_switch_status=PMD.DISABLED
        )

        @test length(events) == 6
        @test all(event["event_data"]["state"] == "OPEN" for event in events)
        @test all(event["event_data"]["status"] == "DISABLED" for event in events)
        @test all(event["event_data"]["dispatchable"] == "NO" for event in events)

        custom_events = Dict{String,Any}[
            Dict{String,Any}(
                "timestep" => 2,
                "event_type" => "switch",
                "affected_asset" => "line.801675",
                "event_data" => Dict{String,Any}(
                    "status" => 0,
                    "state" => "open",
                    "dispatchable" => false
                )
            )
        ]

        events = build_events(
            base_network;
            custom_events=custom_events,
            default_switch_state=PMD.OPEN,
            default_switch_dispatchable=PMD.NO,
            default_switch_status=PMD.DISABLED
        )

        @test events[end] == Dict{String,Any}(
            "timestep" => 2,
            "event_type" => "switch",
            "affected_asset" => "line.801675",
            "event_data" => Dict{String,Any}(
                "status" => "DISABLED",
                "state" => "OPEN",
                "dispatchable" => "NO"
            )
        )
    end

    @testset "test parse raw events from args structure" begin
        args = Dict{String,Any}(
            "events" => parse_events("../test/data/ieee13_fault_events.json"),
            "network" => network,
        )

        events = parse_events!(args)

        @test isa(events, Dict)
        @test isa(args["events"], Dict)
        @test length(events) == 1
        @test length(events["1"]["switch"]) == 2
    end

    @testset "test settings parsing" begin
        settings = parse_settings("../test/data/ieee13_settings.json")

        _network = make_multinetwork(apply_settings(base_network, settings))
        @test all(all(l["clpu_factor"] == 2.0 for l in values(nw["load"])) for nw in values(_network["nw"]))
        @test all(nw["switch_close_actions_ub"] == 1 for nw in values(_network["nw"]))
        @test all(nw["time_elapsed"] == 1.0 for nw in values(_network["nw"]))

        @test all(nw["generator"]["675"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
        @test all(nw["solar"]["pv_mg1a"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
        @test all(nw["solar"]["pv_mg1b"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
        @test all(nw["storage"]["battery_mg1a"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
        @test all(nw["storage"]["battery_mg1b"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
        @test all(nw["storage"]["battery_mg1c"]["inverter"] == GRID_FORMING for nw in values(_network["nw"]))
    end

    @testset "test parse empty settings string" begin
        args = Dict{String,Any}("settings" => "")
        settings = parse_settings!(args)

        ds = build_default_settings()

        @test settings == build_default_settings()
    end

    @testset "test getter and setter functions" begin
        args = Dict{String,Any}(
            "settings" => "../test/data/ieee13_settings.json",
            "network" => "../test/data/ieee13_feeder.dss",
            "events" => "../test/data/ieee13_events.json",
        )
        prepare_data!(args)

        orig_args = deepcopy(args)

        set_setting!(args, ("options", "variables", "unbound-voltage"), true)

        @test get_setting(args, ("options", "variables", "unbound-voltage"))
        @test orig_args["network"]["nw"]["1"]["switch"] == orig_args["network"]["nw"]["1"]["switch"]

        set_settings!(args, Dict(
            ("options", "variables", "unbound-line-power") => true,
            ("options", "variables", "unbound-transformer-power") => true
        ))

        @test get_setting(args, ("options", "variables", "unbound-line-power"))
        @test get_setting(args, ("options", "variables", "unbound-transformer-power"))

        set_option!(args["network"], ("options", "variables", "unbound-line-current"), true)
        @test get_option(args["network"], ("options", "variables", "unbound-line-current"))
        @test all(get_option(nw, ("options", "variables", "unbound-line-current")) for (n,nw) in args["network"]["nw"])

        set_options!(args["network"], Dict(
            ("options", "variables", "unbound-generation-power") => true,
            ("options", "variables", "unbound-storage-power") => true,
        ))
        @test get_option(args["network"], ("options", "variables", "unbound-generation-power"))
        @test all(get_option(nw, ("options", "variables", "unbound-generation-power")) for (n,nw) in args["network"]["nw"])
        @test get_option(args["network"], ("options", "variables", "unbound-storage-power"))
        @test all(get_option(nw, ("options", "variables", "unbound-storage-power")) for (n,nw) in args["network"]["nw"])
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
                "801675" => Dict{String,Any}(
                    "cm_ub" => [25.0, 25.0, 25.0],
                    "state"=>"OPEN",
                    "dispatchable"=>"YES",
                    "status"=>"ENABLED"
                ),
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
            "dss" => Dict{String,Any}(
                "Generator.675" => Dict{String,Any}("inverter" => "GRID_FORMING"),
                "PVSystem.PV_mg1a" => Dict{String,Any}("inverter" => "gfm"),
                "PVSystem.PV_mg1b" => Dict{String,Any}("inverter" => "gfm"),
                "Storage.Battery_mg1a" => Dict{String,Any}("inverter" => "GRID_FORMING"),
                "Storage.Battery_mg1b" => Dict{String,Any}("inverter" => "gfm"),
                "Storage.Battery_mg1c" => Dict{String,Any}("inverter" => "grid_forming")
            ),
        )

        settings = build_settings(
            "../test/data/ieee13_feeder.dss";
            time_elapsed=1.0,
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
            custom_settings=custom_settings,
            disable_isolation_constraint=false,
            disable_radial_constraint=false,
            disable_inverter_constraint=false,
        )

        local_settings = parse_settings("../test/data/ieee13_settings.json")

        @test settings == local_settings

        # for debugging this test
        # for (k,v) in settings
        #     if v != local_settings[k]
        #         @warn k v local_settings[k]
        #     end
        # end
    end

    @testset "test build_settings_new" begin
        custom_settings = Dict{String,Any}(
            "settings" => Dict{String,Any}(
                "sbase_default" => 1000.0,
            ),
            "switch" => Dict{String,Any}(
                "801675" => Dict{String,Any}(
                    "cm_ub" => [25.0, 25.0, 25.0],
                    "state"=>OPEN,
                    "dispatchable"=>YES,
                    "status"=>ENABLED
                ),
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
            "dss" => Dict{String,Any}(
                "Generator.675" => Dict{String,Any}("inverter" => GRID_FORMING),
                "PVSystem.PV_mg1a" => Dict{String,Any}("inverter" => "gfm"),
                "PVSystem.PV_mg1b" => Dict{String,Any}("inverter" => "gfm"),
                "Storage.Battery_mg1a" => Dict{String,Any}("inverter" => GRID_FORMING),
                "Storage.Battery_mg1b" => Dict{String,Any}("inverter" => "gfm"),
                "Storage.Battery_mg1c" => Dict{String,Any}("inverter" => "grid_forming")
            ),
            "options" => Dict{String,Any}(
                "objective" => Dict{String,Any}(
                    "enable-switch-state-open-cost" => true,
                )
            ),
            "solvers" => Dict{String,Any}(
                "Ipopt" => Dict{String,Any}(
                    "tol" => 1e-5
                ),
                "HiGHS" => Dict{String,Any}(
                    "primal_feasibility_tolerance" => 1e-5,
                    "dual_feasibility_tolerance" => 1e-5,
                    "mip_rel_gap" => 0.0001,
                ),
                "Gurobi" => Dict{String,Any}(
                    "FeasibilityTol" => 1e-5,
                    "MIPGap" => 1e-4
                ),
                "Juniper" => Dict{String,Any}(
                    "atol" => 1e-5,
                    "mip_gap" => 1e-4,
                ),
                "KNITRO" => Dict{String,Any}(
                    "feastol" => 1e-5,
                    "opttol" => 1e-4
                )
            )
        )

        settings = build_settings_new(
            "../test/data/ieee13_feeder.dss";
            raw_settings = custom_settings,
            switch_close_actions_ub=1,
            timestep_hours=1.0,
            vm_lb_pu=0.9,
            vm_ub_pu=1.1,
            vad_deg=5.0,
            line_limit_multiplier=Inf,
            transformer_limit_multiplier=Inf,
            generate_microgrid_ids=true,
            cold_load_pickup_factor=2.0,
            storage_phase_unbalance_factor=0.0,
        )

        local_settings = parse_settings("../test/data/ieee13_settings.json")

        @test settings == filter(x->!isempty(x.second), local_settings)
    end

    @testset "test faults io" begin
        faults = parse_faults("../test/data/ieee13_faults.json")

        @test count_faults(faults) == 3
    end

    @testset "test settings invalid eng object" begin
        settings = parse_settings("../test/data/ieee13_settings.json")
        settings["transformer"]["test_missing"] = Dict{String,Any}("status"=>DISABLED)

        eng = apply_settings(base_network, settings)

        @test haskey(settings["transformer"], "test_missing") && !haskey(eng["transformer"], "test_missing")
    end
end
