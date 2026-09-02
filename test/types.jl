@testset "diagnose transform_data_model Dict -> MathematicalModel" begin
    network_file = "../test/data/ieee13_feeder.dss"

    println("\n--- 1. parse_network ---")
    eng = parse_network(network_file)[1]

    @show typeof(eng)
    @show eng isa Dict{String,Any}

    println("\n--- 2. construct PMD EngineeringModel directly ---")
    eng_model = PMD.EngineeringModel(deepcopy(eng))

    @show typeof(eng_model)
    @show eng_model isa PMD.EngineeringModel

    println("\n--- 3. call PMD.transform_data_model directly ---")
    math_model = PMD.transform_data_model(
        eng_model;
        kron_reduce=true,
        phase_project=false,
        multinetwork=false,
        global_keys=Set{String}(),
        eng2math_passthrough=Dict{String,Vector{String}}(),
        eng2math_extensions=Function[],
        make_pu=true,
        make_pu_extensions=Function[],
        correct_network_data=true,
    )

    @show typeof(math_model)
    @show math_model isa PMD.MathematicalModel

    println("\n--- 4. inspect raw mathematical data ---")
    @show typeof(math_model.data)
    @show math_model.data isa Dict{String,Any}

    println("\n--- 5. test PMD model -> Dict conversion ---")
    math_dict = PMD._convert_model_to_dict(math_model)

    @show typeof(math_dict)
    @show math_dict isa Dict{String,Any}

    println("\n--- 6. call ONM transform_data_model wrapper ---")
    try
        math = PowerModelsONM.transform_data_model(eng)

        @show typeof(math)
        @show math isa Dict
        @show math isa PMD.MathematicalModel
    catch err
        println("\nONM wrapper failed:")
        showerror(stdout, err, catch_backtrace())
        println()
        rethrow()
    end
end

# @testset "diagnose code_lowered" begin
#     eng = parse_network("../test/data/ieee13_feeder.dss")[1]

#     println("\n--- selected ONM method ---")
#     m = @which PowerModelsONM.transform_data_model(eng)
#     println(m)

#     println("\n--- lowered code ---")
#     for ci in code_lowered(PowerModelsONM.transform_data_model, Tuple{typeof(eng)})
#         println(ci)
#     end
# end

# @testset "very targeted experiment" begin
#     eng = parse_network("../test/data/ieee13_feeder.dss")[1]

#     eng_model = PMD.EngineeringModel(deepcopy(eng))

#     function test_onm_like_wrapper(
#         eng::Dict{String,Any};
#         global_keys=Set{String}(),
#         eng2math_passthrough=Dict{String,Vector{String}}(),
#         kwargs...
#     )
#         model = PMD.EngineeringModel(deepcopy(eng))

#         result = PMD.transform_data_model(
#             model;
#             global_keys=global_keys,
#             eng2math_passthrough=eng2math_passthrough,
#             kwargs...
#         )

#         @show typeof(result)

#         return result
#     end

#     x = test_onm_like_wrapper(eng)

#     @show typeof(x)
#     @show x isa PMD.MathematicalModel
# end