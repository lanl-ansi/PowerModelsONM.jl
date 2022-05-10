"""
    _ref_add_load_blocks!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

Ref extension to add load blocks to ref at a single time step
"""
function _ref_add_load_blocks!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    ref[:blocks] = Dict{Int,Set}(i => block for (i,block) in enumerate(PMD.calc_connected_components(data; type="load_blocks", check_enabled=true)))
    ref[:bus_block_map] = Dict{Int,Int}(bus => b for (b,block) in ref[:blocks] for bus in block)
    ref[:block_branches] = Dict{Int,Set}(b => Set{Int}() for (b,_) in ref[:blocks])
    ref[:block_loads] = Dict{Int,Set}(i => Set{Int}() for (i,_) in ref[:blocks])
    ref[:block_weights] = Dict{Int,Real}(i => 1.0 for (i,_) in ref[:blocks])
    ref[:block_shunts] = Dict{Int,Set{Int}}(i => Set{Int}() for (i,_) in ref[:blocks])
    ref[:block_gens] = Dict{Int,Set{Int}}(i => Set{Int}() for (i,_) in ref[:blocks])
    ref[:block_storages] = Dict{Int,Set{Int}}(i => Set{Int}() for (i,_) in ref[:blocks])
    ref[:microgrid_blocks] = Dict{Int,String}()
    ref[:substation_blocks] = Vector{Int}()
    ref[:bus_inverters] = Dict{Int,Set{Tuple{Symbol,Int}}}(i => Set{Tuple{Symbol,Int}}() for (i,_) in ref[:bus])
    ref[:block_inverters] = Dict{Int,Set{Tuple{Symbol,Int}}}(b => Set{Tuple{Symbol,Int}}() for (b,_) in ref[:blocks])

    for (b,bus) in ref[:bus]
        if !isempty(get(bus, "microgrid_id", ""))
            ref[:block_weights][ref[:bus_block_map][b]] = 10.0
            ref[:microgrid_blocks][ref[:bus_block_map][b]] = bus["microgrid_id"]
        end
    end

    for (br,branch) in ref[:branch]
        push!(ref[:block_branches][ref[:bus_block_map][branch["f_bus"]]], br)
    end

    for (l,load) in ref[:load]
        push!(ref[:block_loads][ref[:bus_block_map][load["load_bus"]]], l)
        ref[:block_weights][ref[:bus_block_map][load["load_bus"]]] += 1e-2 * get(load, "priority", 1)
    end
    ref[:load_block_map] = Dict{Int,Int}(load => b for (b,block_loads) in ref[:block_loads] for load in block_loads)

    for (s,shunt) in ref[:shunt]
        push!(ref[:block_shunts][ref[:bus_block_map][shunt["shunt_bus"]]], s)
    end
    ref[:shunt_block_map] = Dict{Int,Int}(shunt => b for (b,block_shunts) in ref[:block_shunts] for shunt in block_shunts)

    for (g,gen) in ref[:gen]
        push!(ref[:block_gens][ref[:bus_block_map][gen["gen_bus"]]], g)
        startswith(gen["source_id"], "voltage_source") && push!(ref[:substation_blocks], ref[:bus_block_map][gen["gen_bus"]])
        push!(ref[:bus_inverters][gen["gen_bus"]], (:gen, g))
        push!(ref[:block_inverters][ref[:bus_block_map][gen["gen_bus"]]], (:gen, g))
    end
    ref[:gen_block_map] = Dict{Int,Int}(gen => b for (b,block_gens) in ref[:block_gens] for gen in block_gens)

    for (s,strg) in ref[:storage]
        push!(ref[:block_storages][ref[:bus_block_map][strg["storage_bus"]]], s)
        push!(ref[:bus_inverters][strg["storage_bus"]], (:storage, s))
        push!(ref[:block_inverters][ref[:bus_block_map][strg["storage_bus"]]], (:storage, s))
    end
    ref[:storage_block_map] = Dict{Int,Int}(strg => b for (b,block_storages) in ref[:block_storages] for strg in block_storages)

    for (i,_) in ref[:blocks]
        if isempty(ref[:block_loads][i]) && isempty(ref[:block_shunts][i]) && isempty(ref[:block_gens][i]) && isempty(ref[:block_storages][i])
            ref[:block_weights][i] = 0.0
        end
    end

    ref[:block_graph] = Graphs.SimpleGraph(length(ref[:blocks]))
    ref[:block_graph_edge_map] = Dict{Graphs.Edge,Int}()
    ref[:block_switches] = Dict{Int,Set{Int}}(b => Set{Int}() for (b,_) in ref[:blocks])

    for (s,switch) in ref[:switch]
        f_block = ref[:bus_block_map][switch["f_bus"]]
        t_block = ref[:bus_block_map][switch["t_bus"]]
        Graphs.add_edge!(ref[:block_graph], f_block, t_block)
        ref[:block_graph_edge_map][Graphs.Edge(f_block, t_block)] = s
        ref[:block_graph_edge_map][Graphs.Edge(t_block, f_block)] = s

        if switch["dispatchable"] == 1 && switch["status"] == 1
            push!(ref[:block_switches][f_block], s)
            push!(ref[:block_switches][t_block], s)
        end
    end

    # Build block pairs for radiality constraints
    ref[:block_pairs] = filter(((x,y),)->x!=y, Set{Tuple{Int,Int}}(
            Set([(ref[:bus_block_map][sw["f_bus"]],ref[:bus_block_map][sw["t_bus"]]) for (_,sw) in ref[:switch]]),
    ))

    ref[:neighbors] = Dict{Int,Vector{Int}}(i => Graphs.neighbors(ref[:block_graph], i) for i in Graphs.vertices(ref[:block_graph]))

    ref[:switch_scores] = Dict{Int,Real}(s => 0.0 for (s,_) in ref[:switch])
    total_line_losses = sum(Float64[LinearAlgebra.norm(br["br_r"] .+ 1im*br["br_x"]) for (_,br) in ref[:branch]])
    for type in ["storage", "gen"]
        for (id,obj) in ref[Symbol(type)]
            if obj[PMD.pmd_math_component_status[type]] != PMD.pmd_math_component_status_inactive[type]
                start_block = ref[:bus_block_map][obj["$(type)_bus"]]
                paths = Graphs.enumerate_paths(Graphs.dijkstra_shortest_paths(ref[:block_graph], start_block))

                for path in paths
                    cumulative_weight = 0.0
                    for (i,b) in enumerate(reverse(path[2:end]))
                        block_line_losses = 0.0  # to help with degeneracy
                        for line_id in ref[:block_branches][b]
                            block_line_losses += 1e-2 * LinearAlgebra.norm(ref[:branch][line_id]["br_r"] .+ 1im*ref[:branch][line_id]["br_x"])
                        end
                        cumulative_weight += 1e-2 * ref[:block_weights][b]

                        b_prev = path[end-i]
                        adjusted_cumulative_weight = cumulative_weight - (total_line_losses == 0.0 ? 0.0 : block_line_losses / total_line_losses)
                        ref[:switch_scores][ref[:block_graph_edge_map][Graphs.Edge(b_prev,b)]] += adjusted_cumulative_weight < 0 ? 0.0 : adjusted_cumulative_weight
                    end
                end
            end
        end
    end
end


"""
    ref_add_load_blocks!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

Ref extension to add load blocks to ref for all time steps
"""
function ref_add_load_blocks!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    PMD.apply_pmd!(_ref_add_load_blocks!, ref, data; apply_to_subnetworks=true)
end


"""
    _ref_add_max_switch_actions!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

Ref extension to add max_switch_actions to ref, and set to Inf if option is missing, for a single time step
"""
function _ref_add_max_switch_actions!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    ref[:max_switch_actions] = get(data, "max_switch_actions", Inf)
end


"""
    ref_add_max_switch_actions!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})

Ref extension to add max_switch_actions to ref, and set to Inf if option is missing, for all time steps
"""
function ref_add_max_switch_actions!(ref::Dict{Symbol,<:Any}, data::Dict{String,<:Any})
    PMD.apply_pmd!(_ref_add_max_switch_actions!, ref, data; apply_to_subnetworks=true)
end


"""
    _correct_branch_directions!(switches::Dict{String,<:Any}, ref::Dict{Symbol,<:Any})::Dict{String,Any}

Helper function that will attempt to make a directed graph that is strong-connected by adjusting the
switch directions starting from the voltage_sources
"""
function _correct_switch_directions!(switches::Dict{String,<:Any}, blocks::Dict{Int,Set}, bus_block_map::Dict{Int,Int}, substation_blocks::Vector{Int})::Dict{String,Any}
    bl_switches = Dict(i => Set([]) for (i,_) in blocks)
    for (id,sw) in switches
        push!(bl_switches[bus_block_map[sw["f_bus"]]], id)
        push!(bl_switches[bus_block_map[sw["t_bus"]]], id)
    end
    touched_sw = Set()
    touched_bl = Set()
    todo = Set(substation_blocks)
    while !isempty(todo)
        _bl = pop!(todo)
        if !(_bl in touched_bl)
            push!(touched_bl, _bl)
            for sw_id in filter(x->!(x in touched_sw), bl_switches[_bl])
                push!(touched_sw, sw_id)
                if bus_block_map[switches["$sw_id"]["t_bus"]] == _bl
                    _f_bus = deepcopy(switches["$sw_id"]["f_bus"])
                    _t_bus = deepcopy(switches["$sw_id"]["t_bus"])
                    switches["$sw_id"]["f_bus"] = _t_bus
                    switches["$sw_id"]["t_bus"] = _f_bus
                    push!(todo, bus_block_map[_f_bus])
                    @debug "fixed directionality of $(switches["$sw_id"]["name"])"
                else
                    push!(todo, bus_block_map[switches["$sw_id"]["t_bus"]])
                end
            end
        end
    end

    return switches
end
