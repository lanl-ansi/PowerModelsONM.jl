@testset "data handling checks" begin
    base_network, network = parse_network("../test/data/IEEE13Nodeckt_mod.dss")
    events = parse_events("../test/data/events.json", network)
    network = apply_events(network, events)

    math = PMD.transform_data_model(network)

    @test !all(values(identify_cold_loads(math["nw"]["1"])))
end
