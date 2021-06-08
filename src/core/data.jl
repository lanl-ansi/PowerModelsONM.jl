""
function get_timestep(timestep::Union{Int,String}, network::Dict{String,<:Any})
    if isa(timestep, Int)
        return timestep
    else
        # TODO: Support timesteps in eng multinetwork data structure (PMD)
        Int(round(parse(Float64, timestep)))
    end
end


""
function build_device_map(map::Vector{<:Dict{String,<:Any}}, device_type::String)::Dict{String,String}
    Dict{String,String}(
        string(split(item["to"], ".")[end]) => item["from"] for item in map if endswith(item["unmap_function"], "$(device_type)!")
    )
end


""
function build_switch_map(map::Vector)::Dict{String,String}
    switch_map = Dict{String,String}()
    for item in map
        if endswith(item["unmap_function"], "switch!")
            if isa(item["to"], Array)
                for _to in item["to"]
                    if startswith(_to, "switch")
                        math_id = split(_to, ".")[end]
                        break
                    end
                end
            else
                math_id = split(item["to"], ".")[end]
            end
            switch_map[math_id] = item["from"]
        end
    end
    return switch_map
end


"builds a lookup list of what generators are connected to a given bus"
function bus_gen_lookup(gen_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_gen = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,gen) in gen_data
        push!(bus_gen[gen["gen_bus"]], gen)
    end
    return bus_gen
end


"builds a lookup list of what loads are connected to a given bus"
function bus_load_lookup(load_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_load = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,load) in load_data
        push!(bus_load[load["load_bus"]], load)
    end
    return bus_load
end


"builds a lookup list of what shunts are connected to a given bus"
function bus_shunt_lookup(shunt_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_shunt = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,shunt) in shunt_data
        push!(bus_shunt[shunt["shunt_bus"]], shunt)
    end
    return bus_shunt
end


"builds a lookup list of what storage is connected to a given bus"
function bus_storage_lookup(storage_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_storage = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,storage) in storage_data
        push!(bus_storage[storage["storage_bus"]], storage)
    end
    return bus_storage
end


""
function identify_cold_loads(data)
    blocks = PMD.identify_load_blocks(data)
    is_warm = are_blocks_warm(data, blocks)

    load2block_map = Dict()
    for (l,load) in get(data, "load", Dict())
        for block in blocks
            if load["load_bus"] in block
                load2block_map[parse(Int,l)] = block
                break
            end
        end
    end

    return Dict(l => !is_warm[block] for (l,block) in load2block_map)
end


""
function are_blocks_warm(data, blocks)
    active_gen_buses = Set([gen["gen_bus"] for (_,gen) in get(data, "gen", Dict()) if gen[PMD.pmd_math_component_status["gen"]] != PMD.pmd_math_component_status_inactive["gen"]])
    active_storage_buses = Set([strg["storage_bus"] for (_,strg) in get(data, "storage", Dict()) if strg[PMD.pmd_math_component_status["storage"]] != PMD.pmd_math_component_status_inactive["storage"]])

    is_warm = Dict(block => false for block in blocks)
    for block in blocks
        for bus in block
            if bus in active_gen_buses || bus in active_storage_buses
                is_warm[block] = true
                break
            end
        end
    end
    return is_warm
end


""
function is_block_warm(data, block)
    active_gen_buses = Set([gen["gen_bus"] for (_,gen) in get(data, "gen", Dict()) if gen[PMD.pmd_math_component_status["gen"]] != PMD.pmd_math_component_status_inactive["gen"]])
    active_storage_buses = Set([strg["storage_bus"] for (_,strg) in get(data, "storage", Dict()) if strg[PMD.pmd_math_component_status["storage"]] != PMD.pmd_math_component_status_inactive["storage"]])

    for bus in block
        if bus in active_gen_buses || bus in active_storage_buses
            return true
            break
        end
    end
    return false
end


""
function build_fault_stuides(data::Dict{String,<:Any})::Dict{String,Any}
    return PowerModelsProtection.build_mc_fault_studies(data)
end
