@testset "test graphml io" begin
    eng = parse_file("../test/data/ieee13_feeder.dss")

    @testset "test nested graph" begin
       graph = build_nested_graph(eng)
       @test length(graph.node) == 6
       @test length(graph.edge) == 6

       save_graphml("../test/data/ieee13_nested.graphml", eng; type="nested")
       open("../test/data/ieee13_nested.graphml", "r") do io
            @test length(readlines(io)) == 1588
       end
       rm("../test/data/ieee13_nested.graphml")
    end

    @testset "test unnested graph" begin
        graph = build_unnested_graph(eng)
        @test length(graph.node) == 57
        @test length(graph.edge) == 57

        save_graphml("../test/data/ieee13_unnested.graphml", eng; type="unnested")
        open("../test/data/ieee13_unnested.graphml", "r") do io
             @test length(readlines(io)) == 1558
        end
        rm("../test/data/ieee13_unnested.graphml")
    end
end
