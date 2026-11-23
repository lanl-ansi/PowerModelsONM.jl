@testset "test validate test data against schemas" begin
    events = JSON.parsefile("../test/data/ieee13_events.json"; dicttype=Dict{String,Any})
    @test validate_events(events)

    settings = JSON.parsefile("../test/data/ieee13_settings.json"; dicttype=Dict{String,Any})
    @test validate_settings(settings)

    faults = JSON.parsefile("../test/data/ieee13_faults.json"; dicttype=Dict{String,Any})
    @test validate_faults(faults)

    args = JSON.parsefile("../test/data/runtime_args_example.json"; dicttype=Dict{String,Any})
    @test validate_runtime_arguments(args)
end
