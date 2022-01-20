@testset "data handling checks" begin
    @test PowerModelsONM._get_dispatch_formulation(PMD.ACPUPowerModel) == PMD.ACPUPowerModel
    @test PowerModelsONM._get_switch_formulation(LPUBFSwitchPowerModel) == LPUBFSwitchPowerModel
end
