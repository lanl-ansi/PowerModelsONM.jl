@testset "data handling checks" begin
    @test PowerModelsONM._get_formulation(PMD.ACPUPowerModel) == PMD.ACPUPowerModel
end
