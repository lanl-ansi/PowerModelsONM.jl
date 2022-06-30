@testset "data handling checks" begin
    @test PowerModelsONM._get_formulation(PMD.ACPUPowerModel) == PMD.ACPUPowerModel
end

@testset "test custom onm developer functions" begin
    eng = parse_network("../test/data/ieee13_feeder.dss")[1]
    math = transform_data_model(eng)

    pm = instantiate_onm_model(eng, NFAUPowerModel, build_block_mld)

    @test pm.data == math
end
