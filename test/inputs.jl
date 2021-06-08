@testset "onm inputs checks" begin
    args = Dict{String,Any}(
        "network-file" => "../test/data/IEEE13Nodeckt_mod.dss",
        "output-file" => "../test/tmp_output.json",
        "debug-export-file" => "",
        "formulation" => "lindistflow",
        "problem" => "opf",
        "solver-tolerance" => 1e-4,
        "use-gurobi" => true,
        "verbose" => true,
        "max-switch-actions" => 1,
        "timestep-hours" => 1/60,
        "events" => "../test/data/events.json",
        "inverters" => "../test/data/inverters.json",
        "protection-settings" => "../test/data/protection_settings.xlsx",
    )

    @testset "depreciated inputs sanitize" begin
    end

end
