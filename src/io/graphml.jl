"""
    InfrastructureGraph

Abstract type for Infrastructure graph structures
"""
abstract type InfrastructureGraph end

"""
    UnnestedGraph <: InfrastructureGraph

Unnested graph structure, where the attributes are

```julia
node::Vector{Pair{String,Dict{String,String}}}
edge::Vector{Dict{String,String}}
```
"""
mutable struct UnnestedGraph <: InfrastructureGraph
    node::Vector{Pair{String,Dict{String,String}}}
    edge::Vector{Dict{String,String}}
end


"""
    NestedGraph <: InfrastructureGraph

Nested Graph structure, where the attributes are

```julia
node::Dict{String,UnnestedGraph}
edge::Vector{Dict{String,String}}
```
"""
mutable struct NestedGraph <: InfrastructureGraph
    node::Dict{String,UnnestedGraph}
    edge::Vector{Dict{String,String}}
end


"""
    add_root_graphml_node!(doc::EzXML.Document)::EzXML.Node

Helper function to build 'graphml' root XML Node for GraphML XML documents
"""
function add_root_graphml_node!(doc::EzXML.Document)::EzXML.Node
    graphml = EzXML.ElementNode("graphml")
    EzXML.setroot!(doc, graphml)

    return graphml
end


"""
    build_graphml_node(id::String)::EzXML.Node

Helper function to build graph 'node' XML Node for GraphML XML documents
"""
function build_graphml_node(id::String)::EzXML.Node
    node = EzXML.ElementNode("node")
    EzXML.link!(node, EzXML.AttributeNode("id", id))

    return node
end


"""
    build_graphml_edge(id::String, source::String, target::String)::EzXML.Node

Helper function to build an 'edge' XML Node object for GraphML XML documents
"""
function build_graphml_edge(id::String, source::String, target::String)::EzXML.Node
    edge = EzXML.ElementNode("edge")
    EzXML.link!(edge, EzXML.AttributeNode("id", id))
    EzXML.link!(edge, EzXML.AttributeNode("source", source))
    EzXML.link!(edge, EzXML.AttributeNode("target", target))

    return edge
end


"""
    build_graphml_key(id::String, is_for::String, attr_name::String, attr_type::String, default::Any=missing)::EzXML.Node

Helper function to build an XML AttributeNode for attribute data for GraphML XML documents
"""
function build_graphml_key(id::String, is_for::String, attr_name::String, attr_type::String, default::Any=missing)::EzXML.Node
    key = EzXML.ElementNode("key")
    EzXML.link!(key, EzXML.AttributeNode("id", id))
    EzXML.link!(key, EzXML.AttributeNode("attr.name", attr_name))
    EzXML.link!(key, EzXML.AttributeNode("attr.type", attr_type))
    EzXML.link!(key, EzXML.AttributeNode("for", is_for))
    if !ismissing(default)
        default_element = EzXML.ElementNode("default")
        EzXML.setnodecontent!(default_element, default)
        EzXML.link!(key, default_element)
    end

    return key
end


"""
    build_graphml_graph(id::String, directed::Bool=false)::EzXML.Node

Helper function to build a 'graph' XML Node for GraphML XML documents
"""
function build_graphml_graph(id::String, directed::Bool=false)::EzXML.Node
    graph = EzXML.ElementNode("graph")
    EzXML.link!(graph, EzXML.AttributeNode("id", id))
    EzXML.link!(graph, EzXML.AttributeNode("edgedefault", directed ? "directed" : "undirected"))

    return graph
end


"""
    add_graphml_data!(node::EzXML.Node, key::String, value::Any)::EzXML.Node

Helper function to add an AttributeNode with `key` and `value` to a `node`
"""
function add_graphml_data!(node::EzXML.Node, key::String, value::Any)::EzXML.Node
    data = EzXML.ElementNode("data")
    EzXML.link!(data, EzXML.AttributeNode("key", key))
    EzXML.setnodecontent!(data, value)

    EzXML.link!(node, data)

    return node
end


"""
    build_unnested_graph(eng::Dict{String,<:Any})::UnnestedGraph

Helper function to build an UnnestedGraph from `eng` network data.
"""
function build_unnested_graph(eng::Dict{String,<:Any})::UnnestedGraph

    bus_node_map = Dict{String,Int}(b => i-1 for (i,b) in enumerate(keys(get(eng, "bus", Dict()))))

    gr = UnnestedGraph(
        Pair[
            "n$(i)"=>Dict(
                "type"=>"bus",
                "source_id"=>"bus.$bus",
                Dict(k=>string(v) for (k,v) in get(eng["bus"], bus, Dict()))...
            ) for (bus,i) in bus_node_map
        ],
        Dict{String,String}[]
    )

    edge_count = 0
    for t in PMD._eng_edge_elements
        for (id,obj) in get(eng, t, Dict())
            if t == "transformer" && haskey(obj, "bus")
                for (j,b1) in enumerate(obj["bus"][1:(end-1)])
                    for b2 in obj["bus"][(j+1):end]

                        edge = Dict(
                            "name"=>id,
                            "id"=>"e$edge_count",
                            "source" => "n$(bus_node_map[b1])",
                            "target" => "n$(bus_node_map[b2])",
                            "type"=>t,
                            Dict(k=>string(v) for (k,v) in obj)...
                        )
                        edge_count += 1

                        push!(gr.edge, edge)
                    end
                end
            else
                edge = Dict{String,String}(
                    "name"=>id,
                    "id"=>"e$edge_count",
                    "source"=>"n$(bus_node_map[obj["f_bus"]])",
                    "target"=>"n$(bus_node_map[obj["t_bus"]])",
                    "type"=>t,
                    Dict(k=>string(v) for (k,v) in obj)...
                )
                edge_count += 1

                push!(gr.edge, edge)
            end
        end
    end

    for t in filter(x->x!="bus",PMD._eng_node_elements)
        for (i,obj) in get(eng, t, Dict())

            bus_node_map["$t.$i"] = length(bus_node_map)

            node = Dict{String,String}(
                "type" => t,
                Dict(k => string(v) for (k,v) in obj)...
            )

            push!(gr.node, "n$(bus_node_map["$t.$i"])"=>node)

            edge = Dict{String,String}(
                "name"=>"virtual_edge.$t",
                "id"=>"e$edge_count",
                "source"=>"n$(bus_node_map["$t.$i"])",
                "target"=>"n$(bus_node_map[obj["bus"]])",
                "type"=>"virtual_edge"
            )

            edge_count += 1

            push!(gr.edge, edge)
        end
    end

    return gr
end


"""
    build_nested_graph(eng::Dict{String,Any})::NestedGraph

Helper function to build a NestedGraph of network data `eng`
"""
function build_nested_graph(eng::Dict{String,Any}; check_enabled::Bool=true)::NestedGraph
    @assert !ismultinetwork(eng) "This function does not take multinetwork data"
    @assert PMD.iseng(eng) "This function only takes ENGINEERING data models"

    cc = Dict(i-1 => block for (i,block) in enumerate(PMD.calc_connected_components(eng; type="load_blocks", check_enabled=check_enabled)))
    bus2bl = Dict(bus => i for (i,block) in cc for bus in block)
    bus_bl_node_map = Dict(i => Dict(bus => n-1 for (n,bus) in enumerate(block)) for (i,block) in cc)
    node_2_bus_map = Dict("n$i::n$node" => bus for (i,nodes) in bus_bl_node_map for (bus,node) in nodes)

    gr = NestedGraph(
        Dict{String,UnnestedGraph}(
            "n$i" => UnnestedGraph(
                Pair[
                    "n$(i)::n$(bus_bl_node_map[i][bus])"=>Dict(
                        "type"=>"bus",
                        "source_id"=>"bus.$bus",
                        Dict(k=>string(v) for (k,v) in get(eng["bus"], bus,Dict()))...
                    ) for bus in bl
                ],
                Dict{String,String}[]
            ) for (i,bl) in cc
        ),
        Dict{String,String}[]
    )

    edge_count = 0
    for t in PMD._eng_edge_elements
        for (id,obj) in get(eng, t, Dict())
            if t == "transformer" && haskey(obj, "bus")
                for (j,b1) in enumerate(obj["bus"][1:(end-1)])
                    for b2 in obj["bus"][(j+1):end]
                        bid_fr = bus2bl[b1]
                        bid_to = bus2bl[b2]

                        edge = Dict(
                            "name"=>id,
                            "id"=>"e$edge_count",
                            "source"=>"n$(bid_fr)::n$(bus_bl_node_map[bid_fr][b1])",
                            "target"=>"n$(bid_to)::n$(bus_bl_node_map[bid_to][b2])",
                            "type"=>t,
                            Dict(k=>string(v) for (k,v) in obj)...
                        )
                        edge_count += 1

                        if bid_fr == bid_to
                            push!(gr.node["n$bid_fr"].edge, edge)
                        else
                            push!(gr.edge, edge)
                        end
                    end
                end
            else
                bid_fr = bus2bl[obj["f_bus"]]
                bid_to = bus2bl[obj["t_bus"]]

                edge = Dict{String,String}(
                    "name"=>id,
                    "id"=>"e$edge_count",
                    "source"=>"n$(bid_fr)::n$(bus_bl_node_map[bid_fr][obj["f_bus"]])",
                    "target"=>"n$(bid_to)::n$(bus_bl_node_map[bid_to][obj["t_bus"]])",
                    "type"=>t,
                    Dict(k=>string(v) for (k,v) in obj)...
                )
                edge_count += 1

                if bid_fr == bid_to
                    push!(gr.node["n$bid_fr"].edge, edge)
                else
                    push!(gr.edge, edge)
                end
            end
        end
    end

    for t in filter(x->x!="bus",PMD._eng_node_elements)
        for (i,obj) in get(eng, t, Dict())
            bid_fr = bid_to = bus2bl[obj["bus"]]

            bus_bl_node_map[bid_fr]["$t.$i"] = length(bus_bl_node_map[bid_fr])

            node = Dict{String,String}(
                "type" => t,
                Dict(k => string(v) for (k,v) in obj)...
            )

            push!(gr.node["n$(bid_fr)"].node, "n$(bid_fr)::n$(bus_bl_node_map[bid_fr]["$t.$i"])"=>node)

            node_2_bus_map["n$(bid_fr)::n$(bus_bl_node_map[bid_fr]["$t.$i"])"] = "$t.$i"

            edge = Dict{String,String}(
                "name"=>"virtual_edge.$t",
                "id"=>"e$edge_count",
                "source"=>"n$(bid_fr)::n$(bus_bl_node_map[bid_fr]["$t.$i"])",
                "target"=>"n$(bid_to)::n$(bus_bl_node_map[bid_to][obj["bus"]])",
                "type"=>"virtual_edge"
            )

            edge_count += 1

            push!(gr.node["n$bid_fr"].edge, edge)
        end
    end

    return gr
end


"""
    build_graphml_document(eng::Dict{String,<:Any}; type::Type="nested")

Helper function to build GraphML XML document from a `eng` network data structure.

`type` controls whether the resulting graph is a NestedGraph, i.e., buses are contained within load blocks,
or a UnnestedGraph, where node groups are not utilized.
"""
build_graphml_document(eng::Dict{String,<:Any}; type::String="nested") = type == "nested" ? build_graphml_document(build_nested_graph(eng)) : build_graphml_document(build_unnested_graph(eng))


"""
    build_graphml_document(gr::NestedGraph)::EzXML.Document

Helper function to build GraphML XML document from a NestedGraph
"""
function build_graphml_document(gr::NestedGraph)::EzXML.Document
    node_key_map = Dict()
    edge_key_map = Dict()
    key_int = 0

    doc = EzXML.XMLDocument()
    graphml = add_root_graphml_node!(doc)

    graph = build_graphml_graph("G", false)

    for ((node_id),subgraph) in gr.node
        node = build_graphml_node(node_id)
        if "type" ∉ keys(node_key_map)
            EzXML.link!(graphml, build_graphml_key("d$key_int", "node", "type", "string"))
            node_key_map["type"] = "d$key_int"
            key_int += 1
        end
        add_graphml_data!(node, node_key_map["type"], "block")

        if !isempty(subgraph.edge)
            subgr = build_graphml_graph("$(node_id)::", false)

            for (sub_node_id,sub_node) in subgraph.node
                subn = build_graphml_node(sub_node_id)
                for (k,v) in sub_node
                    if k ∉ keys(node_key_map)
                        EzXML.link!(graphml, build_graphml_key("d$key_int", "node", k, "string"))
                        node_key_map[k] = "d$key_int"
                        key_int += 1
                    end
                    add_graphml_data!(subn, node_key_map[k], v)
                end
                EzXML.link!(subgr, subn)
            end
            for edge in subgraph.edge
                sube = build_graphml_edge(edge["id"], edge["source"], edge["target"])
                for (k,v) in filter(x->x.first∉["id","source","target"], edge)
                    if k ∉ keys(edge_key_map)
                        EzXML.link!(graphml, build_graphml_key("d$key_int", "edge", k, "string"))
                        edge_key_map[k] = "d$key_int"
                        key_int += 1
                    end
                    add_graphml_data!(sube, edge_key_map[k], v)
                end
                EzXML.link!(subgr, sube)
            end

            EzXML.link!(node, subgr)
        end
        EzXML.link!(graph, node)
    end

    for edge in gr.edge
        source_block, source_node = string.(split(edge["source"], "::"))
        target_block, target_node = string.(split(edge["target"], "::"))

        if isempty(gr.node[source_block].edge)
            source = source_block
        else
            source = edge["source"]
        end

        if isempty(gr.node[target_block].edge)
            target = target_block
        else
            target = edge["target"]
        end

        ed = build_graphml_edge(edge["id"], source, target)
        for (k,v) in filter(x->x.first∉["id","source","target"], edge)
            if k ∉ keys(edge_key_map)
                EzXML.link!(graphml, build_graphml_key("d$key_int", "edge", k, "string"))
                edge_key_map[k] = "d$key_int"
                key_int += 1
            end
            add_graphml_data!(ed, edge_key_map[k], v)
        end

        EzXML.link!(graph, ed)
    end

    EzXML.link!(graphml, graph)

    return doc
end


"""
    build_graphml_document(gr::UnnestedGraph)::EzXML.Document

Helper function to build GraphML XML document from an UnnestedGraph
"""
function build_graphml_document(gr::UnnestedGraph)::EzXML.Document
    node_key_map = Dict()
    edge_key_map = Dict()
    key_int = 0

    doc = EzXML.XMLDocument()
    graphml = add_root_graphml_node!(doc)

    graph = build_graphml_graph("G", false)

    for (node_id,node_data) in gr.node
        node = build_graphml_node(node_id)

        for (k,v) in node_data
            if k ∉ keys(node_key_map)
                EzXML.link!(graphml, build_graphml_key("d$key_int", "node", k, "string"))
                node_key_map[k] = "d$key_int"
                key_int += 1
            end
            add_graphml_data!(node, node_key_map[k], v)
        end

        EzXML.link!(graph, node)
    end

    for edge in gr.edge
        ed = build_graphml_edge(edge["id"], edge["source"], edge["target"])
        for (k,v) in filter(x->x.first∉["id","source","target"], edge)
            if k ∉ keys(edge_key_map)
                EzXML.link!(graphml, build_graphml_key("d$key_int", "edge", k, "string"))
                edge_key_map[k] = "d$key_int"
                key_int += 1
            end
            add_graphml_data!(ed, edge_key_map[k], v)
        end

        EzXML.link!(graph, ed)
    end

    EzXML.link!(graphml, graph)

    return doc
end


"""
    save_graphml(io::IO, eng::Dict{String,<:Any}; type::String="nested")

Save a GraphML XML document built from `eng` network data to IO stream.

`type` controls whether the resulting graph is a NestedGraph, i.e., buses are contained within load blocks,
or a UnnestedGraph, where node groups are not utilized.
"""
function save_graphml(io::IO, eng::Dict{String,<:Any}; type::String="nested")
    EzXML.prettyprint(io, build_graphml_document(eng; type=type))
end


"""
    save_graphml(graphml_file::String, eng::Dict{String,<:Any}; type::String="nested")

Save a GraphML XML document built from `eng` network data to `graphml_file`.

`type` controls whether the resulting graph is a NestedGraph, i.e., buses are contained within load blocks,
or a UnnestedGraph, where node groups are not utilized.
"""
function save_graphml(graphml_file::String, eng::Dict{String,<:Any}; type::String="nested")
    open(graphml_file, "w") do io
        save_graphml(io, eng; type=type)
    end
end
