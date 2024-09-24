@testset "test nlp formulations" begin
    eng = parse_file("../test/data/ieee13_feeder.dss")

    settings = parse_settings("../test/data/ieee13_settings.json")

    eng = apply_settings(eng, settings; multinetwork=false)

    for (s, switch) in eng["switch"]
        switch["state"] = OPEN
    end

    eng["switch_close_actions_ub"] = Inf

    set_options!(
        eng,
        Dict(
            ("options", "constraints", "disable-grid-forming-inverter-constraint") => true,
            ("options", "constraints", "disable-storage-unbalance-constraint") => true,
            ("options", "constraints", "enable-strictly-increasing-restoration-constraint") => true,
            ("options", "objective", "enable-switch-state-open-cost") => true,
        )
    )

    @testset "test block mld - acp" begin
        result = solve_block_mld(eng, ACPUPowerModel, minlp_solver)

        @test result["termination_status"] == LOCALLY_SOLVED
        @test length(filter(x -> x.second["state"] == CLOSED, get(get(result, "solution", Dict()), "switch", Dict()))) == 5
        @test isapprox(result["objective"], 6.76; atol=0.1)
    end

    @testset "test block mld - acr" begin
        result = solve_block_mld(eng, ACRUPowerModel, minlp_solver)

        @test result["termination_status"] == LOCALLY_SOLVED
        @test length(filter(x -> x.second["state"] == CLOSED, get(get(result, "solution", Dict()), "switch", Dict()))) == 5
        @test isapprox(result["objective"], 6.75; atol=0.1)
    end
end
