### A Pluto.jl notebook ###
# v0.19.22

using Markdown
using InteractiveUtils

# ╔═╡ 26682490-9b7d-11ed-0507-6f82e14e7dee
## Load required packages
begin
	import PowerModelsONM as ONM
	import PowerModelsDistribution as PMD
	import InfrastructureModels as IM
	import JuMP
	import Ipopt
	import HiGHS
	import LinearAlgebra
	import StatsBase as SB
end

# ╔═╡ af37d952-9c0c-4801-a3a5-6ce57e645460
## Initialize model
begin
	PMD.silence!()
	onm_path = joinpath(dirname(pathof(ONM)), "..")
	case_file = joinpath(onm_path, "test/data/ieee13_feeder.dss")
    global eng = PMD.parse_file(case_file)
    eng["switch_close_actions_ub"] = Inf
    PMD.apply_voltage_bounds!(eng)
    global math = ONM.transform_data_model(eng)

    global ref = IM.build_ref(
        math,
        PMD.ref_add_core!,
        union(ONM._default_global_keys, PMD._pmd_math_global_keys),
        PMD.pmd_it_name;
        ref_extensions=ONM._default_ref_extensions
    )[:it][:pmd][:nw][IM.nw_id_default]

    # branch parameters
    global branch_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_branch] for ((l,i,j), connections) in entry)

    # switch parameters
    global switch_arc_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_switch] for ((l,i,j), connections) in entry)
    global switch_close_actions_ub = ref[:switch_close_actions_ub]

    # transformer parameters
    global transformer_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_transformer] for ((l,i,j), connections) in entry)
    global p_oltc_ids = [id for (id,trans) in ref[:transformer] if !all(trans["tm_fix"])]

    # load parameters
    global load_wye_ids = [id for (id, load) in ref[:load] if load["configuration"]==PMD.WYE]
    global load_del_ids = [id for (id, load) in ref[:load] if load["configuration"]==PMD.DELTA]
    global load_cone_ids = [id for (id, load) in ref[:load] if PMD._check_load_needs_cone(load)]
    global load_connections = Dict{Int,Vector{Int}}(id => load["connections"] for (id,load) in ref[:load])

    # grid-forming inverter parameters
    global L = Set(keys(ref[:blocks]))
    global map_id_pairs = Dict(id => (ref[:bus_block_map][sw["f_bus"]],ref[:bus_block_map][sw["t_bus"]]) for (id,sw) in ref[:switch])
    global Φₖ = Dict(k => Set() for k in L)
    global map_virtual_pairs_id = Dict(k=>Dict() for k in L)
    for kk in L # color
        touched = Set()
        ab = 1
        for k in sort(collect(L)) # fr block
            for k′ in sort(collect(filter(x->x!=k,L))) # to block
                if (k,k′) ∉ touched
                    map_virtual_pairs_id[kk][(k,k′)] = map_virtual_pairs_id[kk][(k′,k)] = ab
                    push!(touched, (k,k′), (k′,k))
                    ab += 1
                end
            end
        end
        Φₖ[kk] = Set([map_virtual_pairs_id[kk][(kk,k′)] for k′ in filter(x->x!=kk,L)])
    end

    # storage parameters
    global storage_inj_lb, storage_inj_ub
    storage_inj_lb, storage_inj_ub = PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])

    # topology parameters
    global _N₀ = collect(keys(ref[:blocks]))
    global _L₀ = ref[:block_pairs]
    global virtual_iᵣ = maximum(_N₀)+1
    global _N = [_N₀..., virtual_iᵣ]
    global iᵣ = [virtual_iᵣ]
    global _L = [_L₀..., [(virtual_iᵣ, n) for n in _N₀]...]
    global _L′ = union(_L, Set([(j,i) for (i,j) in _L]))

    # objective parameters
    global total_energy_ub = sum(strg["energy_rating"] for (i,strg) in ref[:storage])
    global total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (i, gen) in ref[:gen]])
    global total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    global total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax
    global n_dispatchable_switches = length(keys(ref[:switch_dispatchable]))
    global n_dispatchable_switches = n_dispatchable_switches < 1 ? 1 : n_dispatchable_switches
    global block_weights = ref[:block_weights]

    # solver instance setup
    global solver = JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "presolve"=>"on",
        "primal_feasibility_tolerance"=>1e-6,
        "dual_feasibility_tolerance"=>1e-6,
        "mip_feasibility_tolerance"=>1e-4,
        "mip_rel_gap"=>1e-4,
        "small_matrix_value"=>1e-8,
        "allow_unbounded_or_infeasible"=>true,
        "log_to_console"=>false,
        "output_flag"=>false
    )
end

# ╔═╡ 5f2ccc29-9cfe-4a4b-9b5b-5a27feb2c1e7
## generate load scenarios
function generate_load_scenarios(data::Dict{String,<:Any}, N::Int, ΔL::Float64)
    if PMD.iseng(data)
        data = ONM.transform_data_model(data)
    end
    n_l = length(data["load"])
    load_factor = Dict(scen => Dict() for scen in 1:N)
    scen = 1
    while scen<=N
        data_scen = deepcopy(data)
        uncertain_scen = SB.sample((1-ΔL):(2*ΔL/n_l):(1+ΔL), n_l, replace=false)
        for (id,load) in data["load"]
            if scen==1
                load_factor[1][id] = 1
            else
                load_factor[scen][id] = uncertain_scen[parse(Int64,id)]
                data_scen["load"][id]["pd"] = load["pd"]*uncertain_scen[parse(Int64,id)]
                data_scen["load"][id]["qd"] = load["qd"]*uncertain_scen[parse(Int64,id)]
            end
        end
        result = PMD.solve_mc_opf(data_scen, PMD.LPUBFDiagPowerModel, JuMP.optimizer_with_attributes(Ipopt.Optimizer,"print_level"=>0))
        if string(result["termination_status"]) == "LOCALLY_SOLVED"
            scen += 1
        end
    end

    return load_factor
end

# ╔═╡ 22bba14f-b8a2-4182-8984-d86d02ece5f3
## add variables for each scenario
function variable_model(model::JuMP.Model, var_scen::Dict{Any,Any}, scen::Int, load_factor_scen::Dict{Any, Any}; feas_chck::Bool=false)

    # variable_block_indicator
    var_scen["z_block"] = JuMP.@variable(
        model,
        [i in keys(ref[:blocks])],
        base_name="0_z_block_$(scen)",
        lower_bound=0,
        upper_bound=1,
        binary=true
    )

    # variable_mc_bus_voltage_on_off -> variable_mc_bus_voltage_magnitude_sqr_on_off
    var_scen["w"] = Dict(
        i => JuMP.@variable(
            model,
            [t in bus["terminals"]],
            base_name="0_w_$(i)_$(scen)",
            lower_bound=0,
        ) for (i,bus) in ref[:bus]
    )

    # variable_mc_branch_power
    var_scen["p"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in branch_connections[(l,i,j)]],
                base_name="0_p_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_branch]
        )
    )
    var_scen["q"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in branch_connections[(l,i,j)]],
                base_name="0_q_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_branch]
        )
    )

    # variable_mc_switch_power
    var_scen["psw"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in switch_arc_connections[(l,i,j)]],
                base_name="0_psw_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_switch]
        )
    )

    var_scen["qsw"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in switch_arc_connections[(l,i,j)]],
                base_name="0_qsw_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_switch]
        )
    )

    # this explicit type erasure is necessary
    psw_expr_from = Dict( (l,i,j) => var_scen["psw"][(l,i,j)] for (l,i,j) in ref[:arcs_switch_from] )
    var_scen["psw_expr"] = merge(psw_expr_from, Dict( (l,j,i) => -1.0.*var_scen["psw"][(l,i,j)] for (l,i,j) in ref[:arcs_switch_from]))
    var_scen["psw_auxes"] = Dict(
        (l,i,j) => JuMP.@variable(
            model, [c in switch_arc_connections[(l,i,j)]],
            base_name="0_psw_aux_$((l,i,j))_$(scen)"
        ) for (l,i,j) in ref[:arcs_switch]
    )

    qsw_expr_from = Dict( (l,i,j) => var_scen["qsw"][(l,i,j)] for (l,i,j) in ref[:arcs_switch_from] )
    var_scen["qsw_expr"] = merge(qsw_expr_from, Dict( (l,j,i) => -1.0.*var_scen["qsw"][(l,i,j)] for (l,i,j) in ref[:arcs_switch_from]))
    var_scen["qsw_auxes"] = Dict(
        (l,i,j) => JuMP.@variable(
            model, [c in switch_arc_connections[(l,i,j)]],
            base_name="0_qsw_aux_$((l,i,j))_$(scen)"
        ) for (l,i,j) in ref[:arcs_switch]
    )

    # variable_mc_transformer_power
    var_scen["pt"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in transformer_connections[(l,i,j)]],
                base_name="0_pt_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_transformer]
        )
    )

    var_scen["qt"] = Dict(
        Dict(
            (l,i,j) => JuMP.@variable(
                model,
                [c in transformer_connections[(l,i,j)]],
                base_name="0_qt_($l,$i,$j)_$(scen)"
            ) for (l,i,j) in ref[:arcs_transformer]
        )
    )

    # variable_mc_oltc_transformer_tap
    var_scen["tap"] = Dict(
        i => JuMP.@variable(
            model,
            [p in 1:length(ref[:transformer][i]["f_connections"])],
            base_name="0_tm_$(i)_$(scen)",
        ) for i in keys(filter(x->!all(x.second["tm_fix"]), ref[:transformer]))
    )

    # variable_mc_generator_power_on_off
    var_scen["pg"] = Dict(
        i => JuMP.@variable(
            model,
            [c in gen["connections"]],
            base_name="0_pg_$(i)_$(scen)",
        ) for (i,gen) in ref[:gen]
    )

    var_scen["qg"] = Dict(
        i => JuMP.@variable(
            model,
            [c in gen["connections"]],
            base_name="0_qg_$(i)_$(scen)",
        ) for (i,gen) in ref[:gen]
    )

    # variable_mc_storage_power_on_off and variable_mc_storage_power_control_imaginary_on_off
    var_scen["ps"] = Dict(
        i => JuMP.@variable(
            model,
            [c in ref[:storage][i]["connections"]],
            base_name="0_ps_$(i)_$(scen)",
        ) for i in keys(ref[:storage])
    )

    var_scen["qs"] = Dict(
        i => JuMP.@variable(
            model,
            [c in ref[:storage][i]["connections"]],
            base_name="0_qs_$(i)_$(scen)",
        ) for i in keys(ref[:storage])
    )

    var_scen["qsc"] = JuMP.@variable(
        model,
        [i in keys(ref[:storage])],
        base_name="0_qsc_$(i)_$(scen)"
    )

    # qsc bounds
    for (i,strg) in ref[:storage]
        if isfinite(sum(storage_inj_lb[i])) || haskey(strg, "qmin")
            lb = max(sum(storage_inj_lb[i]), sum(get(strg, "qmin", -Inf)))
            JuMP.set_lower_bound(var_scen["qsc"][i], min(lb, 0.0))
        end
        if isfinite(sum(storage_inj_ub[i])) || haskey(strg, "qmax")
            ub = min(sum(storage_inj_ub[i]), sum(get(strg, "qmax", Inf)))
            JuMP.set_upper_bound(var_scen["qsc"][i], max(ub, 0.0))
        end
   end

    # variable_storage_energy, variable_storage_charge and variable_storage_discharge
    var_scen["se"] = JuMP.@variable(model,
        [i in keys(ref[:storage])],
        base_name="0_se_$(scen)",
        lower_bound = 0.0,
    )

    var_scen["sc"] = JuMP.@variable(model,
        [i in keys(ref[:storage])],
        base_name="0_sc_$(scen)",
        lower_bound = 0.0,
    )

    var_scen["sd"] = JuMP.@variable(model,
        [i in keys(ref[:storage])],
        base_name="0_sd_$(scen)",
        lower_bound = 0.0,
    )

    # variable_storage_complementary_indicator and variable_storage_complementary_indicator
    var_scen["sc_on"] = JuMP.@variable(model,
        [i in keys(ref[:storage])],
        base_name="0_sc_on_$(scen)",
        binary = true,
        lower_bound=0,
        upper_bound=1
    )

    var_scen["sd_on"] = JuMP.@variable(model,
        [i in keys(ref[:storage])],
        base_name="0_sd_on_$(scen)",
        binary = true,
        lower_bound=0,
        upper_bound=1
    )

    # load variables
    var_scen["pd"] = Dict()
    var_scen["qd"] = Dict()
    var_scen["pd_bus"] = Dict()
    var_scen["qd_bus"] = Dict()

    for i in intersect(load_wye_ids, load_cone_ids)
        var_scen["pd"][i] = JuMP.@variable(
            model,
            [c in load_connections[i]],
            base_name="0_pd_$(i)_$(scen)"
        )
        var_scen["qd"][i] = JuMP.@variable(
            model,
            [c in load_connections[i]],
            base_name="0_qd_$(i)_$(scen)"
        )
    end

    bound = Dict{eltype(load_del_ids), Matrix{Real}}()
    for id in load_del_ids
        load = ref[:load][id]
        bus_id = load["load_bus"]
        bus = ref[:bus][bus_id]
        load_scen = deepcopy(load)
        load_scen["pd"] = load["pd"]*load_factor_scen["$(id)"]
        load_scen["qd"] = load["qd"]*load_factor_scen["$(id)"]
        cmax = PMD._calc_load_current_max(load_scen, bus)
        bound[id] = bus["vmax"][[findfirst(isequal(c), bus["terminals"]) for c in load_connections[id]]]*cmax'
    end

    cmin = Dict{eltype(load_del_ids), Vector{Real}}()
    cmax = Dict{eltype(load_del_ids), Vector{Real}}()
    for id in load_del_ids
        bus_id = load["load_bus"]
        bus = ref[:bus][bus_id]
        load_scen = deepcopy(load)
        load_scen["pd"] = load["pd"]*load_factor_scen[id]
        load_scen["qd"] = load["qd"]*load_factor_scen[id]
        cmin[id], cmax[id] = PMD._calc_load_current_magnitude_bounds(load_scen, bus)
    end
    (var_scen["Xdr"],var_scen["Xdi"]) = PMD.variable_mx_complex(model, load_del_ids, load_connections, load_connections; symm_bound=bound, name="0_Xd_$(scen)")
    (var_scen["CCdr"], var_scen["CCdi"]) = PMD.variable_mx_hermitian(model, load_del_ids, load_connections; sqrt_upper_bound=cmax, sqrt_lower_bound=cmin, name="0_CCd_$(scen)")

    # variable_mc_capacitor_switch_state
    var_scen["z_cap"] = Dict(
        i => JuMP.@variable(
            model,
            [p in cap["connections"]],
            base_name="0_cap_sw_$(i)_$(scen)",
            binary = true,
        ) for (i,cap) in [(id,cap) for (id,cap) in ref[:shunt] if haskey(cap,"controls")]
    )

    # variable_mc_capacitor_reactive_power
    var_scen["qc"] = Dict(
        i => JuMP.@variable(
            model,
            [p in cap["connections"]],
            base_name="0_cap_cur_$(i)_$(scen)",
        ) for (i,cap) in [(id,cap) for (id,cap) in ref[:shunt] if haskey(cap,"controls")]
    )

    # variable representing if switch ab has 'color' k
    if !feas_chck
        var_scen["y"] = Dict()
        for k in L
            for ab in keys(ref[:switch])
                var_scen["y"][(k,ab)] = JuMP.@variable(
                    model,
                    base_name="0_y_gfm[$k,$ab]_$(scen)",
                    binary=true,
                    lower_bound=0,
                    upper_bound=1
                )
            end
        end

        # Eqs. (9)-(10)
        var_scen["f"] = Dict()
        var_scen["ϕ"] = Dict()
        for kk in L # color
            for ab in keys(ref[:switch])
                var_scen["f"][(kk,ab)] = JuMP.@variable(
                    model,
                    base_name="0_f_gfm[$kk,$ab]_$(scen)"
                )
            end
            touched = Set()
            ab = 1
            for k in sort(collect(L)) # fr block
                for k′ in sort(collect(filter(x->x!=k,L))) # to block
                    if (k,k′) ∉ touched
                        push!(touched, (k,k′), (k′,k))
                        var_scen["ϕ"][(kk,ab)] = JuMP.@variable(
                            model,
                            base_name="0_phi_gfm[$kk,$ab]_$(scen)",
                            lower_bound=0,
                            upper_bound=1
                        )
                        ab += 1
                    end
                end
            end
        end
    end

    # power balance constraints
    var_scen["pd_zblock"] = Dict(i => Dict(l => JuMP.@variable(model, [c in conns], base_name="0_pd_zblock_$(l)_$(scen)") for (l,conns) in ref[:bus_conns_load][i]) for (i,bus) in ref[:bus])
    var_scen["qd_zblock"] = Dict(i => Dict(l => JuMP.@variable(model, [c in conns], base_name="0_qd_zblock_$(l)_$(scen)") for (l,conns) in ref[:bus_conns_load][i]) for (i,bus) in ref[:bus])

    # storage constraints
    var_scen["qsc_zblock"] = Dict(i => JuMP.@variable(model, base_name="0_qd_zblock_$(i)_$(scen)") for (i,strg) in ref[:storage] if JuMP.has_lower_bound(var_scen["qsc"][i]) && JuMP.has_upper_bound(var_scen["qsc"][i]))
    var_scen["ps_sqr"] = Dict(i => [JuMP.@variable(model, base_name="0_ps_sqr_$(i)_$(c)_$(scen)") for c in strg["connections"]] for (i,strg) in ref[:storage])
    var_scen["qs_sqr"] = Dict(i => [JuMP.@variable(model, base_name="0_qs_sqr_$(i)_$(c)_$(scen)") for c in strg["connections"]] for (i,strg) in ref[:storage])
    var_scen["sd_on_ps"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_ps_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sc_on_ps"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_ps_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sd_on_qs"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_qs_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sc_on_qs"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_qs_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["ps_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_ps_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["qs_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_qs_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sd_on_ps_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_ps_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sc_on_ps_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_ps_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sd_on_qs_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_qs_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))
    var_scen["sc_on_qs_zinverter"] = Dict(i => JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_qs_zinverter_$(i)_$(scen)") for (i,strg) in ref[:storage] if isfinite(get(strg, "phase_unbalance_factor", Inf)))

    # branch constraints
    var_scen["p_sqr_fr"] = Dict(i => [JuMP.@variable(model, base_name="0_p_sqr_fr_$((i, branch["f_bus"], branch["t_bus"]))[$(c)]_$(scen)") for c in branch["f_connections"]] for (i,branch) in ref[:branch] if haskey(branch, "c_rating_a") && any(branch["c_rating_a"] .< Inf))
    var_scen["q_sqr_fr"] = Dict(i => [JuMP.@variable(model, base_name="0_q_sqr_fr_$((i, branch["f_bus"], branch["t_bus"]))[$(c)]_$(scen)") for c in branch["f_connections"]] for (i,branch) in ref[:branch] if haskey(branch, "c_rating_a") && any(branch["c_rating_a"] .< Inf))
    var_scen["p_sqr_to"] = Dict(i => [JuMP.@variable(model, base_name="0_p_sqr_to_$((i, branch["t_bus"], branch["f_bus"]))[$(c)]_$(scen)") for c in branch["t_connections"]] for (i,branch) in ref[:branch] if haskey(branch, "c_rating_a") && any(branch["c_rating_a"] .< Inf))
    var_scen["q_sqr_to"] = Dict(i => [JuMP.@variable(model, base_name="0_q_sqr_to_$((i, branch["t_bus"], branch["f_bus"]))[$(c)]_$(scen)") for c in branch["t_connections"]] for (i,branch) in ref[:branch] if haskey(branch, "c_rating_a") && any(branch["c_rating_a"] .< Inf))

    if !feas_chck
        # constraint_switch_close_action_limit
        var_scen["Δᵞs"] = Dict(l => JuMP.@variable(model, base_name="0_delta_switch_state_$(l)_$(scen)") for l in keys(ref[:switch_dispatchable]) if switch_close_actions_ub < Inf)

        # constraint_radial_topology
        var_scen["f_rad"] = Dict()
        var_scen["λ"] = Dict()
        var_scen["β"] = Dict()

        for (i,j) in _L′
            for k in filter(kk->kk∉iᵣ,_N)
                var_scen["f_rad"][(k, i, j)] = JuMP.@variable(model, base_name="0_f_$((k,i,j))_$(scen)")
            end
            var_scen["λ"][(i,j)] = JuMP.@variable(model, base_name="0_lambda_$((i,j))_$(scen)", binary=true, lower_bound=0, upper_bound=1)

            if (i,j) ∈ _L₀
                var_scen["β"][(i,j)] = JuMP.@variable(model, base_name="0_beta_$((i,j))_$(scen)", lower_bound=0, upper_bound=1)
            end
        end
    end

    # switch constraints
    var_scen["psw_sqr_fr"] = Dict(i => [JuMP.@variable(model, base_name="0_psw_sqr_fr_$((i, switch["f_bus"], switch["t_bus"]))[$(c)]_$(scen)") for c in switch["f_connections"]] for (i,switch) in ref[:switch] if haskey(switch, "current_rating") && any(switch["current_rating"] .< Inf))
    var_scen["qsw_sqr_fr"] = Dict(i => [JuMP.@variable(model, base_name="0_qsw_sqr_fr_$((i, switch["f_bus"], switch["t_bus"]))[$(c)]_$(scen)") for c in switch["f_connections"]] for (i,switch) in ref[:switch] if haskey(switch, "current_rating") && any(switch["current_rating"] .< Inf))
    Dict(i => [JuMP.@variable(model, base_name="0_psw_sqr_fr_$((i, switch["f_bus"], switch["t_bus"]))[$(c)]_$(scen)") for c in switch["f_connections"]] for (i,switch) in ref[:switch] if haskey(switch, "current_rating") && any(switch["current_rating"] .< Inf))

    # transformer constraints
    var_scen["tm"] = Dict(trans_id =>
        [transformer["tm_fix"][idx] ? transformer["tm_set"][idx] : var_scen["tap"][trans_id][idx]
        for (idx,(fc,tc)) in enumerate(zip(transformer["f_connections"],transformer["t_connections"]))]
        for (trans_id,transformer) in ref[:transformer] if transformer["configuration"] == PMD.WYE
    )
    var_scen["tmsqr"] = Dict(trans_id => [
        transformer["tm_fix"][i] ? var_scen["tm"][trans_id][i]^2 : JuMP.@variable(
            model,
            base_name="0_tmsqr_$(trans_id)_$(transformer["f_connections"][i])_$(scen)",
            start=JuMP.start_value(var_scen["tm"][trans_id][i])^2,
            lower_bound=JuMP.has_lower_bound(var_scen["tm"][trans_id][i]) ? JuMP.lower_bound(var_scen["tm"][trans_id][i])^2 : 0.9^2,
            upper_bound=JuMP.has_upper_bound(var_scen["tm"][trans_id][i]) ? JuMP.upper_bound(var_scen["tm"][trans_id][i])^2 : 1.1^2
        ) for i in 1:length(var_scen["tm"][trans_id])
    ] for (trans_id,transformer) in ref[:transformer] if transformer["configuration"] == PMD.WYE)
    var_scen["tmsqr_w_to"] = Dict(trans_id =>
        JuMP.@variable(model,
        base_name="0_tmsqr_w_to_$(trans_id)_$(transformer["t_bus"])_$(tc)_$(scen)") for (trans_id,transformer) in ref[:transformer]
        if transformer["configuration"] == PMD.WYE
        for (idx, (fc, tc)) in enumerate(zip(transformer["f_connections"], transformer["t_connections"]))
        if !transformer["tm_fix"][idx]
    )

    # objective
    if !feas_chck
        var_scen["delta_sw_state"] = JuMP.@variable(
            model,
            [i in keys(ref[:switch_dispatchable])],
            base_name="$(i)_delta_sw_state_$(scen)",
        )
    end

end

# ╔═╡ 869740d0-ff54-4a6a-b322-e369748c5783
## add variables common to all scenarios
function variable_common_model(model::JuMP.Model, all_var_common::Dict{Any, Any})

    # variable_inverter_indicator
    all_var_common["z_inverter"] = Dict(
        (t,i) => get(ref[t][i], "inverter", 1) == 1 ? JuMP.@variable(
            model,
            base_name="0_$(t)_z_inverter_$(i)",
            binary=true,
            lower_bound=0,
            upper_bound=1,
        ) : 0 for t in [:storage, :gen] for i in keys(ref[t])
    )

    # variable_switch_state
    all_var_common["z_switch"] = Dict(i => JuMP.@variable(
        model,
        base_name="0_switch_state_$(i)",
        binary=true,
        lower_bound=0,
        upper_bound=1,
    ) for i in keys(ref[:switch_dispatchable]))

end

# ╔═╡ 470b32c7-bbc4-4e32-b4f6-3af6eb3b678e
## build bus shunt admittance matrices
function build_bus_shunt_matrices(ref::Dict{Symbol, Any}, terminals::Vector{Int}, bus_shunts::Vector{Tuple{Int64, Vector{Int64}}})
    ncnds = length(terminals)
    Gs = fill(0.0, ncnds, ncnds)
    Bs = fill(0.0, ncnds, ncnds)
    for (i, connections) in bus_shunts
        shunt = ref[:shunt][i]
        for (idx,c) in enumerate(connections)
            for (jdx,d) in enumerate(connections)
                Gs[findfirst(isequal(c), terminals),findfirst(isequal(d), terminals)] += shunt["gs"][idx,jdx]
                Bs[findfirst(isequal(c), terminals),findfirst(isequal(d), terminals)] += shunt["bs"][idx,jdx]
            end
        end
    end

    return (Gs, Bs)
end

# ╔═╡ 8dfe4c01-b8ce-419a-8c1e-79360214eebe
## add constraints
function constraint_model(model::JuMP.Model, var_scen::Dict{Any, Any}, var_common::Dict{Any, Any} ,load_factor_scen::Dict{Any, Any}; feas_chck::Bool=false)

    # variable_block_indicator
    z_block = var_scen["z_block"]

    # variable_inverter_indicator
    z_inverter = var_common["z_inverter"]

    # variable_mc_bus_voltage_on_off -> variable_mc_bus_voltage_magnitude_sqr_on_off
    w = var_scen["w"]

    # w bounds
    for (i,bus) in ref[:bus]
        for (idx,t) in enumerate(bus["terminals"])
            isfinite(bus["vmax"][idx]) && JuMP.set_upper_bound(w[i][t], bus["vmax"][idx]^2)
        end
    end

    # variable_mc_branch_power
    p = var_scen["p"]
    q = var_scen["q"]

    # p and q bounds
    for (l,i,j) in ref[:arcs_branch]
        smax = PMD._calc_branch_power_max(ref[:branch][l], ref[:bus][i])
        for (idx, c) in enumerate(branch_connections[(l,i,j)])
            PMD.set_upper_bound(p[(l,i,j)][c],  smax[idx])
            PMD.set_lower_bound(p[(l,i,j)][c], -smax[idx])

            PMD.set_upper_bound(q[(l,i,j)][c],  smax[idx])
            PMD.set_lower_bound(q[(l,i,j)][c], -smax[idx])
        end
    end

    # variable_mc_switch_power
    psw = var_scen["psw"]
    qsw = var_scen["qsw"]

    # psw and qsw bounds
    for (l,i,j) in ref[:arcs_switch]
        smax = PMD._calc_branch_power_max(ref[:switch][l], ref[:bus][i])
        for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
            PMD.set_upper_bound(psw[(l,i,j)][c],  smax[idx])
            PMD.set_lower_bound(psw[(l,i,j)][c], -smax[idx])

            PMD.set_upper_bound(qsw[(l,i,j)][c],  smax[idx])
            PMD.set_lower_bound(qsw[(l,i,j)][c], -smax[idx])
        end
    end

    # this explicit type erasure is necessary
    psw_expr = var_scen["psw_expr"]
    qsw_expr = var_scen["qsw_expr"]
    psw_auxes = var_scen["psw_auxes"]
    qsw_auxes = var_scen["qsw_auxes"]

    # This is needed to get around error: "unexpected affine expression in nlconstraint" and overwrite psw/qsw
    for ((l,i,j), psw_aux) in psw_auxes
        for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
            JuMP.@constraint(model, psw_expr[(l,i,j)][c] == psw_aux[c])
        end
    end
    for (k,psw_aux) in psw_auxes
        psw[k] = psw_aux
    end

    for ((l,i,j), qsw_aux) in qsw_auxes
        for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
            JuMP.@constraint(model, qsw_expr[(l,i,j)][c] == qsw_aux[c])
        end
    end
    for (k,qsw_aux) in qsw_auxes
        qsw[k] = qsw_aux
    end

    # variable_switch_state
    z_switch = var_common["z_switch"]

    # fixed switches
    for i in [i for i in keys(ref[:switch]) if !(i in keys(ref[:switch_dispatchable]))]
        z_switch[i] = ref[:switch][i]["state"]
    end

    # variable_mc_transformer_power
    pt = var_scen["pt"]
    qt = var_scen["qt"]

    # pt and qt bounds
    for arc in ref[:arcs_transformer_from]
        (l,i,j) = arc
        rate_a_fr, rate_a_to = PMD._calc_transformer_power_ub_frto(ref[:transformer][l], ref[:bus][i], ref[:bus][j])

        for (idx, (fc,tc)) in enumerate(zip(transformer_connections[(l,i,j)], transformer_connections[(l,j,i)]))
            PMD.set_lower_bound(pt[(l,i,j)][fc], -rate_a_fr[idx])
            PMD.set_upper_bound(pt[(l,i,j)][fc],  rate_a_fr[idx])
            PMD.set_lower_bound(pt[(l,j,i)][tc], -rate_a_to[idx])
            PMD.set_upper_bound(pt[(l,j,i)][tc],  rate_a_to[idx])

            PMD.set_lower_bound(qt[(l,i,j)][fc], -rate_a_fr[idx])
            PMD.set_upper_bound(qt[(l,i,j)][fc],  rate_a_fr[idx])
            PMD.set_lower_bound(qt[(l,j,i)][tc], -rate_a_to[idx])
            PMD.set_upper_bound(qt[(l,j,i)][tc],  rate_a_to[idx])
        end
    end

    # variable_mc_oltc_transformer_tap
    tap = var_scen["tap"]

    # tap bounds
    for tr_id in p_oltc_ids, p in 1:length(ref[:transformer][tr_id]["f_connections"])
        PMD.set_lower_bound(tap[tr_id][p], ref[:transformer][tr_id]["tm_lb"][p])
        PMD.set_upper_bound(tap[tr_id][p], ref[:transformer][tr_id]["tm_ub"][p])
    end

    # variable_mc_generator_power_on_off
    pg = var_scen["pg"]
    qg = var_scen["qg"]

    # pg and qg bounds
    for (i,gen) in ref[:gen]
        for (idx,c) in enumerate(gen["connections"])
            isfinite(gen["pmin"][idx]) && JuMP.set_lower_bound(pg[i][c], min(0.0, gen["pmin"][idx]))
            isfinite(gen["pmax"][idx]) && JuMP.set_upper_bound(pg[i][c], gen["pmax"][idx])

            isfinite(gen["qmin"][idx]) && JuMP.set_lower_bound(qg[i][c], min(0.0, gen["qmin"][idx]))
            isfinite(gen["qmax"][idx]) && JuMP.set_upper_bound(qg[i][c], gen["qmax"][idx])
        end
    end

    # variable_mc_storage_power_on_off and variable_mc_storage_power_control_imaginary_on_off
    ps = var_scen["ps"]
    qs = var_scen["qs"]
    qsc = var_scen["qsc"]

    # ps, qs bounds
    for (i,strg) in ref[:storage]
            for (idx, c) in enumerate(strg["connections"])
            if !isinf(storage_inj_lb[i][idx])
                PMD.set_lower_bound(ps[i][c], storage_inj_lb[i][idx])
                PMD.set_lower_bound(qs[i][c], storage_inj_lb[i][idx])
            end
            if !isinf(storage_inj_ub[i][idx])
                PMD.set_upper_bound(ps[i][c], storage_inj_ub[i][idx])
                PMD.set_upper_bound(qs[i][c], storage_inj_ub[i][idx])
            end
        end
    end

    # variable_storage_energy, variable_storage_charge and variable_storage_discharge
    se = var_scen["se"]
    sc = var_scen["sc"]
    sd = var_scen["sd"]

    # se, sc and sd bounds
    for (i, storage) in ref[:storage]
        PMD.set_upper_bound(se[i], storage["energy_rating"])
        PMD.set_upper_bound(sc[i], storage["charge_rating"])
        PMD.set_upper_bound(sd[i], storage["discharge_rating"])
    end

    # variable_storage_complementary_indicator and variable_storage_complementary_indicator
    sc_on = var_scen["sc_on"]
    sd_on = var_scen["sd_on"]

    # load variables
    pd = var_scen["pd"]
    qd = var_scen["qd"]
    pd_bus = var_scen["pd_bus"]
    qd_bus = var_scen["qd_bus"]
    Xdr = var_scen["Xdr"]
    Xdi = var_scen["Xdi"]
    CCr = var_scen["CCdr"]
    CCi = var_scen["CCdi"]
    for i in intersect(load_wye_ids, load_cone_ids)
        load = ref[:load][i]
        load_scen = deepcopy(load)
        load_scen["pd"] = load["pd"]*load_factor_scen["$i"]
        load_scen["qd"] = load["qd"]*load_factor_scen["$i"]
        bus = ref[:bus][load["load_bus"]]
        pmin, pmax, qmin, qmax = PMD._calc_load_pq_bounds(load_scen, bus)

        for (idx,c) in enumerate(load_connections[i])
            PMD.set_lower_bound(pd[i][c], pmin[idx])
            PMD.set_upper_bound(pd[i][c], pmax[idx])
            PMD.set_lower_bound(qd[i][c], qmin[idx])
            PMD.set_upper_bound(qd[i][c], qmax[idx])
        end
    end

    # variable_mc_capacitor_switch_state
    z_cap = var_scen["z_cap"]

    # variable_mc_capacitor_reactive_power
    qc = var_scen["qc"]

    # voltage sources are always grid-forming
    for ((t,j), z_inv) in z_inverter
        if t == :gen && startswith(ref[t][j]["source_id"], "voltage_source")
            JuMP.@constraint(model, z_inv == z_block[ref[:bus_block_map][ref[t][j]["$(t)_bus"]]])
        end
    end

    if !feas_chck
        # variable representing if switch ab has 'color' k
        y = var_scen["y"]

        # Eqs. (9)-(10)
        f = var_scen["f"]
        ϕ = var_scen["ϕ"]
        for kk in L # color
            for ab in keys(ref[:switch])
                JuMP.@constraint(model, f[kk,ab] >= -length(keys(ref[:switch]))*(z_switch[ab]))
                JuMP.@constraint(model, f[kk,ab] <=  length(keys(ref[:switch]))*(z_switch[ab]))
            end
        end

        # constrain each y to have only one color
        for ab in keys(ref[:switch])
            JuMP.@constraint(model, sum(y[(k,ab)] for k in L) <= z_switch[ab])
        end
    end

    # Eqs. (3)-(7)
    for k in L
        Dₖ = ref[:block_inverters][k]
        Tₖ = ref[:block_switches][k]

        if !isempty(Dₖ)
            # Eq. (14)
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) >= sum(1-z_switch[ab] for ab in Tₖ)-length(Tₖ)+z_block[k])
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) <= z_block[k])

            if !feas_chck
                # Eq. (4)-(5)
                for (t,j) in Dₖ
                    if t == :storage
                        pmin = fill(-Inf, length(ref[t][j]["connections"]))
                        pmax = fill( Inf, length(ref[t][j]["connections"]))
                        qmin = fill(-Inf, length(ref[t][j]["connections"]))
                        qmax = fill( Inf, length(ref[t][j]["connections"]))

                        for (idx,c) in enumerate(ref[t][j]["connections"])
                            pmin[idx] = storage_inj_lb[j][idx]
                            pmax[idx] = storage_inj_ub[j][idx]
                            qmin[idx] = max(storage_inj_lb[j][idx], ref[t][j]["qmin"])
                            qmax[idx] = min(storage_inj_ub[j][idx], ref[t][j]["qmax"])

                            if isfinite(pmax[idx]) && pmax[idx] >= 0
                                JuMP.@constraint(model, ps[j][c] <= pmax[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, ps[j][c] <= pmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(qmax[idx]) && qmax[idx] >= 0
                                JuMP.@constraint(model, qs[j][c] <= qmax[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, qs[j][c] <= qmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(pmin[idx]) && pmin[idx] <= 0
                                JuMP.@constraint(model, ps[j][c] >= pmin[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, ps[j][c] >= pmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(qmin[idx]) && qmin[idx] <= 0
                                JuMP.@constraint(model, qs[j][c] >= qmin[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, qs[j][c] >= qmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                        end
                    elseif t == :gen
                        pmin = ref[t][j]["pmin"]
                        pmax = ref[t][j]["pmax"]
                        qmin = ref[t][j]["qmin"]
                        qmax = ref[t][j]["qmax"]

                        for (idx,c) in enumerate(ref[t][j]["connections"])
                            if isfinite(pmax[idx]) && pmax[idx] >= 0
                                JuMP.@constraint(model, pg[j][c] <= pmax[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, pg[j][c] <= pmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(qmax[idx]) && qmax[idx] >= 0
                                JuMP.@constraint(model, qg[j][c] <= qmax[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, qg[j][c] <= qmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(pmin[idx]) && pmin[idx] <= 0
                                JuMP.@constraint(model, pg[j][c] >= pmin[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, pg[j][c] >= pmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                            if isfinite(qmin[idx]) && qmin[idx] <= 0
                                JuMP.@constraint(model, qg[j][c] >= qmin[idx] * (sum(z_switch[ab] for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                                JuMP.@constraint(model, qg[j][c] >= qmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(z_inverter[i] for i in Dₖ)))
                            end
                        end
                    end
                end
            end
        end

        if !feas_chck
            for ab in Tₖ
                # Eq. (6)
                JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) >= y[(k, ab)] - (1 - z_switch[ab]))
                JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) <= y[(k, ab)] + (1 - z_switch[ab]))

                # Eq. (8)
                JuMP.@constraint(model, y[(k,ab)] <= sum(z_inverter[i] for i in Dₖ))

                for dc in filter(x->x!=ab, Tₖ)
                    for k′ in L
                        # Eq. (7)
                        JuMP.@constraint(model, y[(k′,ab)] >= y[(k′,dc)] - (1 - z_switch[dc]) - (1 - z_switch[ab]))
                        JuMP.@constraint(model, y[(k′,ab)] <= y[(k′,dc)] + (1 - z_switch[dc]) + (1 - z_switch[ab]))
                    end
                end
            end

            # Eq. (11)
            JuMP.@constraint(model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1] == k, Tₖ)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2] == k, Tₖ)) + sum(ϕ[(k,ab)] for ab in Φₖ[k]) == length(L) - 1)

            # Eq. (15)
            JuMP.@constraint(model, z_block[k] <= sum(z_inverter[i] for i in Dₖ) + sum(y[(k′,ab)] for k′ in L for ab in Tₖ))

            for k′ in filter(x->x!=k, L)
                Tₖ′ = ref[:block_switches][k′]
                kk′ = map_virtual_pairs_id[k][(k,k′)]

                # Eq. (12)
                JuMP.@constraint(model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1]==k′, Tₖ′)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2]==k′, Tₖ′)) - ϕ[(k,(kk′))] == -1)

                # Eq. (13)
                for ab in Tₖ′
                    JuMP.@constraint(model, y[k,ab] <= 1 - ϕ[(k,kk′)])
                end
            end
        end
    end

    # constraint_mc_inverter_theta_ref
    for (i,bus) in ref[:bus]
        # reference bus "theta" constraint
        vmax = min(bus["vmax"]..., 2.0)
        if isfinite(vmax)
            if length(w[i]) > 1 && !isempty([z_inverter[inv_obj] for inv_obj in ref[:bus_inverters][i]])
                for t in 2:length(w[i])
                    JuMP.@constraint(model, w[i][t] - w[i][1] <=  vmax^2 * (1 - sum([z_inverter[inv_obj] for inv_obj in ref[:bus_inverters][i]])))
                    JuMP.@constraint(model, w[i][t] - w[i][1] >= -vmax^2 * (1 - sum([z_inverter[inv_obj] for inv_obj in ref[:bus_inverters][i]])))
                end
            end
        end
    end

    # constraint_mc_bus_voltage_block_on_off
    for (i,bus) in ref[:bus]
        # bus voltage on off constraint
        for (idx,t) in [(idx,t) for (idx,t) in enumerate(bus["terminals"]) if !bus["grounded"][idx]]
            isfinite(bus["vmax"][idx]) && JuMP.@constraint(model, w[i][t] <= bus["vmax"][idx]^2*z_block[ref[:bus_block_map][i]])
            isfinite(bus["vmin"][idx]) && JuMP.@constraint(model, w[i][t] >= bus["vmin"][idx]^2*z_block[ref[:bus_block_map][i]])
        end
    end

    # constraint_mc_generator_power_block_on_off
    for (i,gen) in ref[:gen]
        for (idx, c) in enumerate(gen["connections"])
            isfinite(gen["pmin"][idx]) && JuMP.@constraint(model, pg[i][c] >= gen["pmin"][idx]*z_block[ref[:gen_block_map][i]])
            isfinite(gen["qmin"][idx]) && JuMP.@constraint(model, qg[i][c] >= gen["qmin"][idx]*z_block[ref[:gen_block_map][i]])

            isfinite(gen["pmax"][idx]) && JuMP.@constraint(model, pg[i][c] <= gen["pmax"][idx]*z_block[ref[:gen_block_map][i]])
            isfinite(gen["qmax"][idx]) && JuMP.@constraint(model, qg[i][c] <= gen["qmax"][idx]*z_block[ref[:gen_block_map][i]])
        end
    end

    # constraint_mc_load_power
    for (load_id,load) in ref[:load]
        bus_id = load["load_bus"]
        bus = ref[:bus][bus_id]
        Td = [1 -1 0; 0 1 -1; -1 0 1]
        load_scen = deepcopy(load)
        load_scen["pd"] = load["pd"]*load_factor_scen["$(load_id)"]
        load_scen["qd"] = load["qd"]*load_factor_scen["$(load_id)"]
        a, alpha, b, beta = PMD._load_expmodel_params(load_scen, bus)
        pd0 = load_scen["pd"]
        qd0 = load_scen["qd"]
        if load["configuration"]==PMD.WYE
            if load["model"]==PMD.POWER
                pd[load_id] = JuMP.Containers.DenseAxisArray(pd0, load["connections"])
                qd[load_id] = JuMP.Containers.DenseAxisArray(qd0, load["connections"])
            elseif load["model"]==PMD.IMPEDANCE
                _w = w[bus_id][[c for c in load["connections"]]]
                pd[load_id] = a.*_w
                qd[load_id] = b.*_w
            else
                for (idx,c) in enumerate(load["connections"])
                    JuMP.@constraint(model, pd[load_id][c]==1/2*a[idx]*(w[bus_id][c]+1))
                    JuMP.@constraint(model, qd[load_id][c]==1/2*b[idx]*(w[bus_id][c]+1))
                end
            end

            pd_bus[load_id] = pd[load_id]
            qd_bus[load_id] = qd[load_id]

        elseif load["configuration"]==PMD.DELTA
            pd_bus[load_id] = LinearAlgebra.diag(Xdr[load_id]*Td)
            qd_bus[load_id] = LinearAlgebra.diag(Xdi[load_id]*Td)
            pd[load_id] = LinearAlgebra.diag(Td*Xdr[load_id])
            qd[load_id] = LinearAlgebra.diag(Td*Xdi[load_id])

            for (idx, c) in enumerate(load["connections"])
                if abs(pd0[idx]+im*qd0[idx]) == 0.0
                    JuMP.@constraint(model, Xdr[load_id][:,idx] .== 0)
                    JuMP.@constraint(model, Xdi[load_id][:,idx] .== 0)
                end
            end

            if load["model"]==PMD.POWER
                for (idx, c) in enumerate(load["connections"])
                    JuMP.@constraint(model, pd[load_id][idx]==pd0[idx])
                    JuMP.@constraint(model, qd[load_id][idx]==qd0[idx])
                end
            elseif load["model"]==PMD.IMPEDANCE
                for (idx,c) in enumerate(load["connections"])
                    JuMP.@constraint(model, pd[load_id][idx]==3*a[idx]*w[bus_id][[c for c in load["connections"]]][idx])
                    JuMP.@constraint(model, qd[load_id][idx]==3*b[idx]*w[bus_id][[c for c in load["connections"]]][idx])
                end
            else
                for (idx,c) in enumerate(load["connections"])
                    JuMP.@constraint(model, pd[load_id][idx]==sqrt(3)/2*a[idx]*(w[bus_id][[c for c in load["connections"]]][idx]+1))
                    JuMP.@constraint(model, qd[load_id][idx]==sqrt(3)/2*b[idx]*(w[bus_id][[c for c in load["connections"]]][idx]+1))
                end
            end
        end
    end

    # power balance constraints
    for (i,bus) in ref[:bus]
        uncontrolled_shunts = Tuple{Int,Vector{Int}}[]
        controlled_shunts = Tuple{Int,Vector{Int}}[]

        if !isempty(ref[:bus_conns_shunt][i]) && any(haskey(ref[:shunt][sh], "controls") for (sh, conns) in ref[:bus_conns_shunt][i])
            for (sh, conns) in ref[:bus_conns_shunt][i]
                if haskey(ref[:shunt][sh], "controls")
                    push!(controlled_shunts, (sh,conns))
                else
                    push!(uncontrolled_shunts, (sh, conns))
                end
            end
        else
            uncontrolled_shunts = ref[:bus_conns_shunt][i]
        end

        Gt, _ = build_bus_shunt_matrices(ref, bus["terminals"], ref[:bus_conns_shunt][i])
        _, Bt = build_bus_shunt_matrices(ref, bus["terminals"], uncontrolled_shunts)

        ungrounded_terminals = [(idx,t) for (idx,t) in enumerate(bus["terminals"]) if !bus["grounded"][idx]]

        pd_zblock = var_scen["pd_zblock"][i]
        qd_zblock = var_scen["qd_zblock"][i]

        for (l,conns) in ref[:bus_conns_load][i]
            for c in conns
                IM.relaxation_product(model, pd_bus[l][c], z_block[ref[:load_block_map][l]], pd_zblock[l][c])
                IM.relaxation_product(model, qd_bus[l][c], z_block[ref[:load_block_map][l]], qd_zblock[l][c])
            end
        end

        for (idx, t) in ungrounded_terminals
            JuMP.@constraint(model,
                sum(p[a][t] for (a, conns) in ref[:bus_arcs_conns_branch][i] if t in conns)
                + sum(psw[a_sw][t] for (a_sw, conns) in ref[:bus_arcs_conns_switch][i] if t in conns)
                + sum(pt[a_trans][t] for (a_trans, conns) in ref[:bus_arcs_conns_transformer][i] if t in conns)
                ==
                sum(pg[g][t] for (g, conns) in ref[:bus_conns_gen][i] if t in conns)
                - sum(ps[s][t] for (s, conns) in ref[:bus_conns_storage][i] if t in conns)
                - sum(pd_zblock[l][t] for (l, conns) in ref[:bus_conns_load][i] if t in conns)
                - sum((w[i][t] * LinearAlgebra.diag(Gt')[idx]) for (sh, conns) in ref[:bus_conns_shunt][i] if t in conns)
            )

            JuMP.@constraint(model,
                sum(q[a][t] for (a, conns) in ref[:bus_arcs_conns_branch][i] if t in conns)
                + sum(qsw[a_sw][t] for (a_sw, conns) in ref[:bus_arcs_conns_switch][i] if t in conns)
                + sum(qt[a_trans][t] for (a_trans, conns) in ref[:bus_arcs_conns_transformer][i] if t in conns)
                ==
                sum(qg[g][t] for (g, conns) in ref[:bus_conns_gen][i] if t in conns)
                - sum(qs[s][t] for (s, conns) in ref[:bus_conns_storage][i] if t in conns)
                - sum(qd_zblock[l][t] for (l, conns) in ref[:bus_conns_load][i] if t in conns)
                - sum((-w[i][t] * LinearAlgebra.diag(Bt')[idx]) for (sh, conns) in uncontrolled_shunts if t in conns)
                - sum(-qc[sh][t] for (sh, conns) in controlled_shunts if t in conns)
            )

            for (sh, sh_conns) in controlled_shunts
                if t in sh_conns
                    bs = LinearAlgebra.diag(ref[:shunt][sh]["bs"])[findfirst(isequal(t), sh_conns)]

                    w_lb, w_ub = IM.variable_domain(w[i][t])
                    JuMP.@constraint(model, z_cap[sh] <= z_block[ref[:bus_block_map][i]])
                    JuMP.@constraint(model, qc[sh] ≥ bs*z_cap[sh]*w_lb)
                    JuMP.@constraint(model, qc[sh] ≥ bs*w[t] + bs*z_cap[sh]*w_ub - bs*w_ub*z_block[ref[:bus_block_map][i]])
                    JuMP.@constraint(model, qc[sh] ≤ bs*z_cap[sh]*w_ub)
                    JuMP.@constraint(model, qc[sh] ≤ bs*w[t] + bs*z_cap[sh]*w_lb - bs*w_lb*z_block[ref[:bus_block_map][i]])
                end
            end
        end
    end

    # storage constraints
    for (i,strg) in ref[:storage]

        # constraint_storage_state
        JuMP.@constraint(model, se[i] - strg["energy"] == ref[:time_elapsed]*(strg["charge_efficiency"]*sc[i] - sd[i]/strg["discharge_efficiency"]))

        # constraint_storage_complementarity_mi_block_on_off
        JuMP.@constraint(model, sc_on[i] + sd_on[i] == z_block[ref[:storage_block_map][i]])
        JuMP.@constraint(model, sc_on[i]*strg["charge_rating"] >= sc[i])
        JuMP.@constraint(model, sd_on[i]*strg["discharge_rating"] >= sd[i])

        # constraint_mc_storage_block_on_off
        ncnds = length(strg["connections"])
        pmin = zeros(ncnds)
        pmax = zeros(ncnds)
        qmin = zeros(ncnds)
        qmax = zeros(ncnds)

        for (idx,c) in enumerate(strg["connections"])
            pmin[idx] = storage_inj_lb[i][idx]
            pmax[idx] = storage_inj_ub[i][idx]
            qmin[idx] = max(storage_inj_lb[i][idx], strg["qmin"])
            qmax[idx] = min(storage_inj_ub[i][idx], strg["qmax"])
        end

        pmin = maximum(pmin)
        pmax = minimum(pmax)
        qmin = maximum(qmin)
        qmax = minimum(qmax)

        isfinite(pmin) && JuMP.@constraint(model, sum(ps[i]) >= z_block[ref[:storage_block_map][i]]*pmin)
        isfinite(qmin) && JuMP.@constraint(model, sum(qs[i]) >= z_block[ref[:storage_block_map][i]]*qmin)

        isfinite(pmax) && JuMP.@constraint(model, sum(ps[i]) <= z_block[ref[:storage_block_map][i]]*pmax)
        isfinite(qmax) && JuMP.@constraint(model, sum(qs[i]) <= z_block[ref[:storage_block_map][i]]*qmax)

        # constraint_mc_storage_losses_block_on_off
        if JuMP.has_lower_bound(qsc[i]) && JuMP.has_upper_bound(qsc[i])
            qsc_zblock = var_scen["qsc_zblock"][i]

            JuMP.@constraint(model, qsc_zblock >= JuMP.lower_bound(qsc[i]) * z_block[ref[:storage_block_map][i]])
            JuMP.@constraint(model, qsc_zblock >= JuMP.upper_bound(qsc[i]) * z_block[ref[:storage_block_map][i]] + qsc[i] - JuMP.upper_bound(qsc[i]))
            JuMP.@constraint(model, qsc_zblock <= JuMP.upper_bound(qsc[i]) * z_block[ref[:storage_block_map][i]])
            JuMP.@constraint(model, qsc_zblock <= qsc[i] + JuMP.lower_bound(qsc[i]) * z_block[ref[:storage_block_map][i]] - JuMP.lower_bound(qsc[i]))

            JuMP.@constraint(model, sum(qs[i]) == qsc_zblock + strg["q_loss"] * z_block[ref[:storage_block_map][i]])
        else
            # Note that this is not supported in LP solvers when z_block is continuous
            JuMP.@constraint(model, sum(qs[i]) == qsc[i] * z_block[ref[:storage_block_map][i]] + strg["q_loss"] * z_block[ref[:storage_block_map][i]])
        end
        JuMP.@constraint(model, sum(ps[i]) + (sd[i] - sc[i]) == strg["p_loss"] * z_block[ref[:storage_block_map][i]])

        # constraint_mc_storage_thermal_limit
        _ps = [ps[i][c] for c in strg["connections"]]
        _qs = [qs[i][c] for c in strg["connections"]]

        ps_sqr = var_scen["ps_sqr"][i]
        qs_sqr = var_scen["qs_sqr"][i]

        for (idx,c) in enumerate(strg["connections"])
            ps_lb, ps_ub = IM.variable_domain(_ps[idx])
            PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, _ps[idx], ps_sqr[idx], [ps_lb, ps_ub], false)

            qs_lb, qs_ub = IM.variable_domain(_qs[idx])
            PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, _qs[idx], qs_sqr[idx], [qs_lb, qs_ub], false)
        end

        JuMP.@constraint(model, sum(ps_sqr .+ qs_sqr) <= strg["thermal_rating"]^2)

        # constraint_mc_storage_phase_unbalance_grid_following
        unbalance_factor = get(strg, "phase_unbalance_factor", Inf)
        if isfinite(unbalance_factor)
            sd_on_ps = var_scen["sd_on_ps"][i]
            sc_on_ps = var_scen["sc_on_ps"][i]
            sd_on_qs = var_scen["sd_on_qs"][i]
            sc_on_qs = var_scen["sc_on_qs"][i]
            ps_zinverter = var_scen["ps_zinverter"][i]
            qs_zinverter = var_scen["qs_zinverter"][i]
            sd_on_ps_zinverter = var_scen["sd_on_ps_zinverter"][i]
            sc_on_ps_zinverter = var_scen["sc_on_ps_zinverter"][i]
            sd_on_qs_zinverter = var_scen["sd_on_qs_zinverter"][i]
            sc_on_qs_zinverter = var_scen["sc_on_qs_zinverter"][i]
            for c in strg["connections"]
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sd_on[i], ps[i][c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sc_on[i], ps[i][c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sd_on[i], qs[i][c], sd_on_qs[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sc_on[i], qs[i][c], sc_on_qs[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], ps[i][c], ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], qs[i][c], qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], sd_on_ps[c], sd_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], sc_on_ps[c], sc_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], sd_on_qs[c], sd_on_qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
                PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], sc_on_qs[c], sc_on_qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
            end

            for (idx,c) in enumerate(strg["connections"])
                if idx < length(strg["connections"])
                    for d in strg["connections"][idx+1:end]
                        JuMP.@constraint(model, ps[i][c]-ps_zinverter[c] >= ps[i][d] - unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] + unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))
                        JuMP.@constraint(model, ps[i][c]-ps_zinverter[c] <= ps[i][d] + unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] - unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))

                        JuMP.@constraint(model, qs[i][c]-qs_zinverter[c] >= qs[i][d] - unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]) - qs_zinverter[d] + unbalance_factor*(-1*sd_on_qs_zinverter[d] + 1*sc_on_qs_zinverter[d]))
                        JuMP.@constraint(model, qs[i][c]-qs_zinverter[c] <= qs[i][d] + unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]) - qs_zinverter[d] - unbalance_factor*(-1*sd_on_qs_zinverter[d] + 1*sc_on_qs_zinverter[d]))
                    end
                end
            end
        end
    end

    # branch constraints
    for (i,branch) in ref[:branch]
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_idx = (i, f_bus, t_bus)
        t_idx = (i, t_bus, f_bus)

        r = branch["br_r"]
        x = branch["br_x"]
        g_sh_fr = branch["g_fr"]
        g_sh_to = branch["g_to"]
        b_sh_fr = branch["b_fr"]
        b_sh_to = branch["b_to"]

        f_connections = branch["f_connections"]
        t_connections = branch["t_connections"]
        N = length(f_connections)

        alpha = exp(-im*2*pi/3)
        Gamma = [1 alpha^2 alpha; alpha 1 alpha^2; alpha^2 alpha 1][f_connections,t_connections]
        MP = 2*(real(Gamma).*r + imag(Gamma).*x)
        MQ = 2*(real(Gamma).*x - imag(Gamma).*r)

        p_fr = p[f_idx]
        q_fr = q[f_idx]

        p_to = p[t_idx]
        q_to = q[t_idx]

        w_fr = w[f_bus]
        w_to = w[t_bus]

        # constraint_mc_power_losses
        for (idx, (fc,tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(model, p_fr[fc] + p_to[tc] == g_sh_fr[idx,idx]*w_fr[fc] +  g_sh_to[idx,idx]*w_to[tc])
            JuMP.@constraint(model, q_fr[fc] + q_to[tc] == -b_sh_fr[idx,idx]*w_fr[fc] + -b_sh_to[idx,idx]*w_to[tc])
        end

        p_s_fr = [p_fr[fc]- LinearAlgebra.diag(g_sh_fr)[idx].*w_fr[fc] for (idx,fc) in enumerate(f_connections)]
        q_s_fr = [q_fr[fc]+ LinearAlgebra.diag(b_sh_fr)[idx].*w_fr[fc] for (idx,fc) in enumerate(f_connections)]

        # constraint_mc_model_voltage_magnitude_difference
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(model, w_to[tc] == w_fr[fc] - sum(MP[idx,j]*p_s_fr[j] for j in 1:N) - sum(MQ[idx,j]*q_s_fr[j] for j in 1:N))
        end

        # constraint_mc_voltage_angle_difference
        for (idx, (fc, tc)) in enumerate(zip(branch["f_connections"], branch["t_connections"]))
            g_fr = branch["g_fr"][idx,idx]
            g_to = branch["g_to"][idx,idx]
            b_fr = branch["b_fr"][idx,idx]
            b_to = branch["b_to"][idx,idx]

            r = branch["br_r"][idx,idx]
            x = branch["br_x"][idx,idx]

            angmin = branch["angmin"]
            angmax = branch["angmax"]

            w_fr = w[f_bus][fc]
            p_fr = p[f_idx][fc]
            q_fr = q[f_idx][fc]

            JuMP.@constraint(model,
                tan(angmin[idx])*((1 + r*g_fr - x*b_fr)*(w_fr) - r*p_fr - x*q_fr)
                        <= ((-x*g_fr - r*b_fr)*(w_fr) + x*p_fr - r*q_fr)
                )
            JuMP.@constraint(model,
                tan(angmax[idx])*((1 + r*g_fr - x*b_fr)*(w_fr) - r*p_fr - x*q_fr)
                        >= ((-x*g_fr - r*b_fr)*(w_fr) + x*p_fr - r*q_fr)
                )
        end

        # ampacity constraints
        if haskey(branch, "c_rating_a") && any(branch["c_rating_a"] .< Inf)
            c_rating = branch["c_rating_a"]

            # constraint_mc_ampacity_from
            p_fr = [p[f_idx][c] for c in f_connections]
            q_fr = [q[f_idx][c] for c in f_connections]
            w_fr = [w[f_idx[2]][c] for c in f_connections]

            p_sqr_fr = var_scen["p_sqr_fr"][i]
            q_sqr_fr = var_scen["q_sqr_fr"][i]

            for (idx,c) in enumerate(f_connections)
                if isfinite(c_rating[idx])
                    p_lb, p_ub = IM.variable_domain(p_fr[idx])
                    q_lb, q_ub = IM.variable_domain(q_fr[idx])
                    w_ub = IM.variable_domain(w_fr[idx])[2]

                    if (!isfinite(p_lb) || !isfinite(p_ub)) && isfinite(w_ub)
                        p_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        p_lb = -p_ub
                    end
                    if (!isfinite(q_lb) || !isfinite(q_ub)) && isfinite(w_ub)
                        q_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        q_lb = -q_ub
                    end

                    all(isfinite(b) for b in [p_lb, p_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, p_fr[idx], p_sqr_fr[idx], [p_lb, p_ub], false)
                    all(isfinite(b) for b in [q_lb, q_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, q_fr[idx], q_sqr_fr[idx], [q_lb, q_ub], false)
                end
            end

            # constraint_mc_ampacity_to
            p_to = [p[t_idx][c] for c in t_connections]
            q_to = [q[t_idx][c] for c in t_connections]
            w_to = [w[t_idx[2]][c] for c in t_connections]

            p_sqr_to = var_scen["p_sqr_to"][i]
            q_sqr_to = var_scen["q_sqr_to"][i]

            for (idx,c) in enumerate(t_connections)
                if isfinite(c_rating[idx])
                    p_lb, p_ub = IM.variable_domain(p_to[idx])
                    q_lb, q_ub = IM.variable_domain(q_to[idx])
                    w_ub = IM.variable_domain(w_to[idx])[2]

                    if (!isfinite(p_lb) || !isfinite(p_ub)) && isfinite(w_ub)
                        p_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        p_lb = -p_ub
                    end
                    if (!isfinite(q_lb) || !isfinite(q_ub)) && isfinite(w_ub)
                        q_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        q_lb = -q_ub
                    end

                    all(isfinite(b) for b in [p_lb, p_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, p_to[idx], p_sqr_to[idx], [p_lb, p_ub], false)
                    all(isfinite(b) for b in [q_lb, q_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, q_to[idx], q_sqr_to[idx], [q_lb, q_ub], false)
                end
            end
        end
    end

    if !feas_chck
        # constraint_switch_close_action_limit
        if switch_close_actions_ub < Inf
            Δᵞs = var_scen["Δᵞs"]

            for (s, Δᵞ) in Δᵞs
                γ = z_switch[s]
                γ₀ = JuMP.start_value(γ)
                JuMP.@constraint(model, Δᵞ >=  γ * (1 - γ₀))
                JuMP.@constraint(model, Δᵞ >= -γ * (1 - γ₀))
            end
            JuMP.@constraint(model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= switch_close_actions_ub)
        end

        # constraint_radial_topology
        f_rad = var_scen["f_rad"]
        λ = var_scen["λ"]
        β = var_scen["β"]
        α = Dict()

        for (s,sw) in ref[:switch]
            (i,j) = (ref[:bus_block_map][sw["f_bus"]], ref[:bus_block_map][sw["t_bus"]])
            α[(i,j)] = z_switch[s]
        end

        for (i,j) in _L′
            for k in filter(kk->kk∉iᵣ,_N)
                f_rad[(k, i, j)] = JuMP.@variable(model, base_name="0_f_$((k,i,j))")
            end
            λ[(i,j)] = JuMP.@variable(model, base_name="0_lambda_$((i,j))", binary=true, lower_bound=0, upper_bound=1)

            if (i,j) ∈ _L₀
                β[(i,j)] = JuMP.@variable(model, base_name="0_beta_$((i,j))", lower_bound=0, upper_bound=1)
            end
        end

        JuMP.@constraint(model, sum((λ[(i,j)] + λ[(j,i)]) for (i,j) in _L) == length(_N) - 1)

        for (i,j) in _L₀
            JuMP.@constraint(model, λ[(i,j)] + λ[(j,i)] == β[(i,j)])
            JuMP.@constraint(model, α[(i,j)] <= β[(i,j)])
        end

        for k in filter(kk->kk∉iᵣ,_N)
            for _iᵣ in iᵣ
                jiᵣ = filter(((j,i),)->i==_iᵣ&&i!=j,_L)
                iᵣj = filter(((i,j),)->i==_iᵣ&&i!=j,_L)
                if !(isempty(jiᵣ) && isempty(iᵣj))
                    JuMP.@constraint(
                        model,
                        sum(f_rad[(k,j,i)] for (j,i) in jiᵣ) -
                        sum(f_rad[(k,i,j)] for (i,j) in iᵣj)
                        ==
                        -1.0
                    )
                end
            end

            jk = filter(((j,i),)->i==k&&i!=j,_L′)
            kj = filter(((i,j),)->i==k&&i!=j,_L′)
            if !(isempty(jk) && isempty(kj))
                JuMP.@constraint(
                    model,
                    sum(f_rad[(k,j,k)] for (j,i) in jk) -
                    sum(f_rad[(k,k,j)] for (i,j) in kj)
                    ==
                    1.0
                )
            end

            for i in filter(kk->kk∉iᵣ&&kk!=k,_N)
                ji = filter(((j,ii),)->ii==i&&ii!=j,_L′)
                ij = filter(((ii,j),)->ii==i&&ii!=j,_L′)
                if !(isempty(ji) && isempty(ij))
                    JuMP.@constraint(
                        model,
                        sum(f_rad[(k,j,i)] for (j,ii) in ji) -
                        sum(f_rad[(k,i,j)] for (ii,j) in ij)
                        ==
                        0.0
                    )
                end
            end

            for (i,j) in _L
                JuMP.@constraint(model, f_rad[(k,i,j)] >= 0)
                JuMP.@constraint(model, f_rad[(k,i,j)] <= λ[(i,j)])
                JuMP.@constraint(model, f_rad[(k,j,i)] >= 0)
                JuMP.@constraint(model, f_rad[(k,j,i)] <= λ[(j,i)])
            end
        end
    end

    # constraint_isolate_block
    for (s, switch) in ref[:switch_dispatchable]
        z_block_fr = z_block[ref[:bus_block_map][switch["f_bus"]]]
        z_block_to = z_block[ref[:bus_block_map][switch["t_bus"]]]

        γ = z_switch[s]
        JuMP.@constraint(model,  (z_block_fr - z_block_to) <=  (1-γ))
        JuMP.@constraint(model,  (z_block_fr - z_block_to) >= -(1-γ))
    end

    for b in keys(ref[:blocks])
        n_gen = length(ref[:block_gens][b])
        n_strg = length(ref[:block_storages][b])
        n_neg_loads = length([_b for (_b,ls) in ref[:block_loads] if any(any(ref[:load][l]["pd"] .< 0) for l in ls)])
        JuMP.@constraint(model, z_block[b] <= n_gen + n_strg + n_neg_loads + sum(z_switch[s] for s in keys(ref[:block_switches]) if s in keys(ref[:switch_dispatchable])))
    end

    for (i,switch) in ref[:switch]
        f_bus_id = switch["f_bus"]
        t_bus_id = switch["t_bus"]
        f_connections = switch["f_connections"]
        t_connections = switch["t_connections"]
        f_idx = (i, f_bus_id, t_bus_id)

        f_bus = ref[:bus][f_bus_id]
        t_bus = ref[:bus][t_bus_id]

        f_vmax = f_bus["vmax"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
        t_vmax = t_bus["vmax"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

        vmax = min.(fill(2.0, length(f_bus["vmax"])), f_vmax, t_vmax)

        rating = min.(fill(1.0, length(f_connections)), PMD._calc_branch_power_max_frto(switch, f_bus, t_bus)...)

        w_fr = w[f_bus_id]
        w_to = w[f_bus_id]

        # constraint_mc_switch_state_open_close
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(model, w_fr[fc] - w_to[tc] <=  vmax[idx].^2 * (1-z_switch[i]))
            JuMP.@constraint(model, w_fr[fc] - w_to[tc] >= -vmax[idx].^2 * (1-z_switch[i]))
        end

        for (idx, c) in enumerate(f_connections)
            JuMP.@constraint(model, psw[f_idx][c] <=  rating[idx] * z_switch[i])
            JuMP.@constraint(model, psw[f_idx][c] >= -rating[idx] * z_switch[i])
            JuMP.@constraint(model, qsw[f_idx][c] <=  rating[idx] * z_switch[i])
            JuMP.@constraint(model, qsw[f_idx][c] >= -rating[idx] * z_switch[i])
        end

        # constraint_mc_switch_ampacity
        if haskey(switch, "current_rating") && any(switch["current_rating"] .< Inf)
            c_rating = switch["current_rating"]

            psw_fr = [psw[f_idx][c] for c in f_connections]
            qsw_fr = [qsw[f_idx][c] for c in f_connections]
            w_fr = [w[f_idx[2]][c] for c in f_connections]

            psw_sqr_fr = var_scen["psw_sqr_fr"][i]
            qsw_sqr_fr = var_scen["qsw_sqr_fr"][i]

            for (idx,c) in enumerate(f_connections)
                if isfinite(c_rating[idx])
                    p_lb, p_ub = IM.variable_domain(psw_fr[idx])
                    q_lb, q_ub = IM.variable_domain(qsw_fr[idx])
                    w_ub = IM.variable_domain(w_fr[idx])[2]

                    if (!isfinite(p_lb) || !isfinite(p_ub)) && isfinite(w_ub)
                        p_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        p_lb = -p_ub
                    end
                    if (!isfinite(q_lb) || !isfinite(q_ub)) && isfinite(w_ub)
                        q_ub = sum(c_rating[isfinite.(c_rating)]) * w_ub
                        q_lb = -q_ub
                    end

                    all(isfinite(b) for b in [p_lb, p_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, psw_fr[idx], psw_sqr_fr[idx], [p_lb, p_ub], false)
                    all(isfinite(b) for b in [q_lb, q_ub]) && PMD.PolyhedralRelaxations.construct_univariate_relaxation!(model, x->x^2, qsw_fr[idx], qsw_sqr_fr[idx], [q_lb, q_ub], false)
                end
            end
        end
    end

    # transformer constraints
    for (trans_id,transformer) in ref[:transformer]
        f_bus = transformer["f_bus"]
        t_bus = transformer["t_bus"]
        f_idx = (trans_id, f_bus, t_bus)
        t_idx = (trans_id, t_bus, f_bus)
        configuration = transformer["configuration"]
        f_connections = transformer["f_connections"]
        t_connections = transformer["t_connections"]
        tm_set = transformer["tm_set"]
        tm_fixed = transformer["tm_fix"]
        tm_scale = PMD.calculate_tm_scale(transformer, ref[:bus][f_bus], ref[:bus][t_bus])
        pol = transformer["polarity"]

        if configuration == PMD.WYE
            tm = var_scen["tm"][trans_id]

            p_fr = [pt[f_idx][p] for p in f_connections]
            p_to = [pt[t_idx][p] for p in t_connections]
            q_fr = [qt[f_idx][p] for p in f_connections]
            q_to = [qt[t_idx][p] for p in t_connections]

            w_fr = w[f_bus]
            w_to = w[t_bus]

            tmsqr = var_scen["tmsqr"][trans_id]

            for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
                if tm_fixed[idx]
                    JuMP.@constraint(model, w_fr[fc] == (pol*tm_scale*tm[idx])^2*w_to[tc])
                else
                    PMD.PolyhedralRelaxations.construct_univariate_relaxation!(
                        model,
                        x->x^2,
                        tm[idx],
                        tmsqr[idx],
                        [
                            JuMP.has_lower_bound(tm[idx]) ? JuMP.lower_bound(tm[idx]) : 0.9,
                            JuMP.has_upper_bound(tm[idx]) ? JuMP.upper_bound(tm[idx]) : 1.1
                        ],
                        false
                    )

                    tmsqr_w_to = var_scen["tmsqr_w_to"][trans_id]
                    PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(
                        model,
                        tmsqr[idx],
                        w_to[tc],
                        tmsqr_w_to,
                        [JuMP.lower_bound(tmsqr[idx]), JuMP.upper_bound(tmsqr[idx])],
                        [
                            JuMP.has_lower_bound(w_to[tc]) ? JuMP.lower_bound(w_to[tc]) : 0.0,
                            JuMP.has_upper_bound(w_to[tc]) ? JuMP.upper_bound(w_to[tc]) : 1.1^2
                        ]
                    )

                    JuMP.@constraint(model, w_fr[fc] == (pol*tm_scale)^2*tmsqr_w_to)
                end
            end

            JuMP.@constraint(model, p_fr + p_to .== 0)
            JuMP.@constraint(model, q_fr + q_to .== 0)

        elseif configuration == PMD.DELTA
            tm = [tm_fixed[idx] ? tm_set[idx] : var(pm, nw, :tap, trans_id)[fc] for (idx,(fc,tc)) in enumerate(zip(f_connections,t_connections))]
            nph = length(tm_set)

            p_fr = [pt[f_idx][p] for p in f_connections]
            p_to = [pt[t_idx][p] for p in t_connections]
            q_fr = [qt[f_idx][p] for p in f_connections]
            q_to = [qt[t_idx][p] for p in t_connections]

            w_fr = w[f_bus]
            w_to = w[t_bus]

            for (idx,(fc, tc)) in enumerate(zip(f_connections,t_connections))
                # rotate by 1 to get 'previous' phase
                # e.g., for nph=3: 1->3, 2->1, 3->2
                jdx = (idx-1+1)%nph+1
                fd = f_connections[jdx]
                JuMP.@constraint(model, 3.0*(w_fr[fc] + w_fr[fd]) == 2.0*(pol*tm_scale*tm[idx])^2*w_to[tc])
            end

            for (idx,(fc, tc)) in enumerate(zip(f_connections,t_connections))
                # rotate by nph-1 to get 'previous' phase
                # e.g., for nph=3: 1->3, 2->1, 3->2
                jdx = (idx-1+nph-1)%nph+1
                fd = f_connections[jdx]
                td = t_connections[jdx]
                JuMP.@constraint(model, 2*p_fr[fc] == -(p_to[tc]+p_to[td])+(q_to[td]-q_to[tc])/sqrt(3.0))
                JuMP.@constraint(model, 2*q_fr[fc] ==  (p_to[tc]-p_to[td])/sqrt(3.0)-(q_to[td]+q_to[tc]))
            end
        end
    end

    # objective
    if !feas_chck
        delta_sw_state = var_scen["delta_sw_state"]

        for (s,switch) in ref[:switch_dispatchable]
            JuMP.@constraint(model, delta_sw_state[s] >=  (switch["state"] - z_switch[s]))
            JuMP.@constraint(model, delta_sw_state[s] >= -(switch["state"] - z_switch[s]))
        end
    end
end

# ╔═╡ 8a71bd48-86ab-4be8-8590-6a8819b2e074
## perform feasibility check by fixing common variables
function feasibility_check(scenario::Vector{Int}, all_var_common_soln::Dict{Any, Any}, load_factor::Dict{Int64, Dict{Any, Any}}; n_inf::Int=1)

    infeas_idx = []
    for scen in scenario
        var_scen = Dict()
        model_scen = JuMP.Model()
        JuMP.set_optimizer(model_scen, solver)

        variable_model(model_scen,var_scen,scen,load_factor[scen]; feas_chck=true)
        constraint_model(model_scen,var_scen,all_var_common_soln,load_factor[scen]; feas_chck=true)
        JuMP.optimize!(model_scen)
        sts = string(JuMP.termination_status(model_scen))
        if sts!="OPTIMAL"
            push!(infeas_idx,scen)
        end
        println("$scen $sts")
    end
    inf_scen = length(infeas_idx)>0 ? infeas_idx[1:n_inf] : []

    return inf_scen

end

# ╔═╡ 1649391d-239d-40c8-a148-dca2c4fb5167
## setup scenario model, solve and check feasibility
function solve_model(N_scen::Int, ΔL::Float64)

    # Generate scenarios
    load_factor = generate_load_scenarios(math, N_scen, ΔL)

    # create empty model and generate common variables
    model = JuMP.Model()
    JuMP.set_optimizer(model, solver)
    all_var_common = Dict()
    variable_common_model(model,all_var_common)

    # setup and solve model adding one scenario in each iteration
    all_var_scen = Dict(scen=> Dict() for scen=1:N_scen)
    all_var_common_soln = Dict()
    scenarios = [1]
    idx = 0
    viol_ind = true
    while length(scenarios)<=N_scen && viol_ind

        idx += 1

        for scen in scenarios[idx:end]
            # add variables to model
            variable_model(model,all_var_scen[scen],scen,load_factor[scen])

            # add constraints to model
            constraint_model(model,all_var_scen[scen],all_var_common,load_factor[scen])
        end

        # objective
        JuMP.@objective(model, Min, sum(
                sum( block_weights[i] * (1-all_var_scen[scen]["z_block"][i]) for (i,block) in ref[:blocks])
                + sum( ref[:switch_scores][l]*(1-all_var_common["z_switch"][l]) for l in keys(ref[:switch_dispatchable]) )
                + sum( all_var_scen[scen]["delta_sw_state"][l] for l in keys(ref[:switch_dispatchable])) / n_dispatchable_switches
                + sum( (strg["energy_rating"] - all_var_scen[scen]["se"][i]) for (i,strg) in ref[:storage]) / total_energy_ub
                + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * all_var_scen[scen]["pg"][i][c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in ref[:gen]) / total_energy_ub
        for scen in scenarios) )

        # solve manual model
        JuMP.optimize!(model)

        # print output
        obj_val = []
        for scen in scenarios
            obj_scen = sum( block_weights[i] * (1-all_var_scen[scen]["z_block"][i]) for (i,block) in ref[:blocks])+ sum( ref[:switch_scores][l]*(1-all_var_common["z_switch"][l]) for l in keys(ref[:switch_dispatchable]) )+ sum( all_var_scen[scen]["delta_sw_state"][l] for l in keys(ref[:switch_dispatchable])) / n_dispatchable_switches+ sum( (strg["energy_rating"] - all_var_scen[scen]["se"][i]) for (i,strg) in ref[:storage]) / total_energy_ub+ sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * all_var_scen[scen]["pg"][i][c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in ref[:gen]) / total_energy_ub
            push!(obj_val,round(JuMP.value(obj_scen), digits=4))
        end
        sts = string(JuMP.termination_status(model))
        println("$(scenarios): $(sts) Obj_val=$(obj_val)")
        println("Switch status: $([JuMP.value(all_var_common["z_switch"][i]) for i in keys(ref[:switch_dispatchable])])")
        println("Inverter status: $([JuMP.value(z_inv[i]) for ((t,i), z_inv) in all_var_common["z_inverter"]])")

        # store solution of common variables
        all_var_common_soln["z_inverter"] = Dict(
            (t,i) => JuMP.value(z_inv) for ((t,i), z_inv) in all_var_common["z_inverter"]
        )
        all_var_common_soln["z_switch"] = Dict(i => JuMP.value(all_var_common["z_switch"][i]) for i in keys(ref[:switch_dispatchable]))

        # feasibility check
        scenario = deleteat!([1:N_scen;], sort(scenarios))
        if length(scenario)==0
            viol_ind = false
        else
            infeas_idx = feasibility_check(scenario,all_var_common_soln,load_factor)
            if length(infeas_idx) > 0
                for idx in infeas_idx
                    push!(scenarios,idx)
                end
            else
                viol_ind = false
            end
        end
    end
end

# ╔═╡ 5607facf-bede-4816-9280-f0bb6706857c
## Build and solve model (all functions below this cell)
begin
	N_scen = 10  # number of scenarios
	ΔL = 0.15 # load uncertainty
	solve_model(N_scen,ΔL) # solve scenario model
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
InfrastructureModels = "2030c09a-7f63-5d83-885d-db604e0e9cc0"
Ipopt = "b6b21f68-93f8-5de0-b562-5493be1d77c9"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
PowerModelsDistribution = "d7431456-977f-11e9-2de3-97ff7677985e"
PowerModelsONM = "25264005-a304-4053-a338-565045d392ac"
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

[compat]
HiGHS = "~1.5.0"
InfrastructureModels = "~0.7.6"
Ipopt = "~1.2.0"
JuMP = "~1.9.0"
PowerModelsDistribution = "~0.14.7"
PowerModelsONM = "~3.3.0"
StatsBase = "~0.33.21"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[ASL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6252039f98492252f9e47c312c8ffda0e3b9e78d"
uuid = "ae81ac8f-d209-56e5-92de-9978fef736f9"
version = "0.1.3+0"

[[Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "cc37d689f599e8df4f464b2fa3870ff7db7492ef"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.6.1"

[[ArgParse]]
deps = ["Logging", "TextWrap"]
git-tree-sha1 = "3102bce13da501c9104df33549f511cd25264d7d"
uuid = "c7e460c6-2fb9-53a9-8c5b-16f535851c63"
version = "1.1.4"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[ArrayInterface]]
deps = ["Adapt", "LinearAlgebra", "Requires", "SnoopPrecompile", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "a89acc90c551067cd84119ff018619a1a76c6277"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "7.2.1"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "d9a9701b899b30332bbcb3e1679c41cce81fb0e8"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.3.2"

[[BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "SnoopPrecompile", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "c700cce799b51c9045473de751e9319bdd1c6e94"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.9"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c6d890a52d2c4d55d326439580c3b8d0875a77d9"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.7"

[[ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "485193efd2176b88e6622a39a246f8c5b600e74e"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.6"

[[CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "2e62a725210ce3c3c2e1a3080190e7ca491f18d7"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.7.2"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[Combinatorics]]
git-tree-sha1 = "08c8b6831dc00bfea825826be0bc8336fc369860"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.0.2"

[[CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "7a60c856b9fa189eb34f5f8a6f6b5529b7942957"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.6.1"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.1+0"

[[ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "89a9db8d28102b094992472d333674bd1a83ce2a"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.1"

[[DataAPI]]
git-tree-sha1 = "e8119c1a33d267e16108be441a287a6981ba1630"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.14.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "a4ad7ef19d2cdc2eff57abbbe68032b1cd0bd8f8"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.13.0"

[[Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "49eba9ad9f7ead780bfb7ee319f962c811c6d3b2"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.8"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[EzXML]]
deps = ["Printf", "XML2_jll"]
git-tree-sha1 = "0fa3b52a04a4e210aeb1626def9c90df3ae65268"
uuid = "8f5d6c58-4d21-5cfd-889c-e3ad7ee6a615"
version = "1.1.0"

[[FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Requires", "Setfield", "SparseArrays", "StaticArrays"]
git-tree-sha1 = "ed1b56934a2f7a65035976985da71b6a65b4f2cf"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.18.0"

[[ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "00e252f4d706b3d55a8863432e742bf5717b498d"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.35"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[Glob]]
git-tree-sha1 = "4df9f7e06108728ebf00a0a11edee4b29a482bb2"
uuid = "c27321d9-0574-5035-807b-f59d2c89b15c"
version = "1.3.0"

[[Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "1cf1d7dcb4bc32d7b4a5add4232db3750c27ecb4"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.8.0"

[[HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "37e4657cd56b11abe3d10cd4a1ec5fbdb4180263"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.7.4"

[[HiGHS]]
deps = ["HiGHS_jll", "MathOptInterface", "SnoopPrecompile", "SparseArrays"]
git-tree-sha1 = "c4e72223d3c5401cc3a7059e23c6717ba5a08482"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.5.0"

[[HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "53aadc2a53ef3ecc4704549b4791dea67657a4bb"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.5.1+0"

[[Hwloc]]
deps = ["Hwloc_jll", "Statistics"]
git-tree-sha1 = "8338d1bec813d12c4c0d443e3bdf5af564fb37ad"
uuid = "0e44f5e4-bd66-52a0-8798-143a42290a1d"
version = "2.2.0"

[[Hwloc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a35518b15f2e63b60c44ee72be5e3a8dbf570e1b"
uuid = "e33a78d0-f292-5ffc-b300-72abe9b543c8"
version = "2.9.0+0"

[[Inflate]]
git-tree-sha1 = "5cd07aab533df5170988219191dfad0519391428"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.3"

[[InfrastructureModels]]
deps = ["JuMP", "Memento"]
git-tree-sha1 = "88da90ad5d8ca541350c156bea2715f3a23836ce"
uuid = "2030c09a-7f63-5d83-885d-db604e0e9cc0"
version = "0.7.6"

[[IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "49510dfcb407e572524ba94aeae2fced1f3feb0f"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.8"

[[Ipopt]]
deps = ["Ipopt_jll", "LinearAlgebra", "MathOptInterface", "OpenBLAS32_jll", "SnoopPrecompile"]
git-tree-sha1 = "7690de6bc4eb8d8e3119dc707b5717326c4c0536"
uuid = "b6b21f68-93f8-5de0-b562-5493be1d77c9"
version = "1.2.0"

[[Ipopt_jll]]
deps = ["ASL_jll", "Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "MUMPS_seq_jll", "OpenBLAS32_jll", "Pkg", "libblastrampoline_jll"]
git-tree-sha1 = "563b23f40f1c83f328daa308ce0cdf32b3a72dc4"
uuid = "9cc047cb-c261-5740-88fc-0cf96f7bdcc7"
version = "300.1400.403+1"

[[IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[JSONSchema]]
deps = ["HTTP", "JSON", "URIs"]
git-tree-sha1 = "8d928db71efdc942f10e751564e6bbea1e600dfe"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "1.0.1"

[[JuMP]]
deps = ["LinearAlgebra", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "Printf", "SnoopPrecompile", "SparseArrays"]
git-tree-sha1 = "611b9f12f02c587d860c813743e6cec6264e94d8"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.9.0"

[[Juniper]]
deps = ["Distributed", "JSON", "LinearAlgebra", "MathOptInterface", "MutableArithmetics", "Random", "Statistics"]
git-tree-sha1 = "a0735f588cb750d89ddcfa2f429a2330b0f440c6"
uuid = "2ddba703-00a4-53a7-87a5-e8b9971dde84"
version = "0.9.1"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c7cb1f5d892775ba13767a87c7ada0b980ea0a71"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+2"

[[LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "Printf"]
git-tree-sha1 = "7bbea35cec17305fc70a0e5b4641477dc0789d9d"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.2.0"

[[LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "0a1b7c2863e44523180fdb3146534e265a91870b"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.23"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[METIS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "1fd0a97409e418b78c53fac671cf4622efdf0f21"
uuid = "d00139f3-1899-568f-a2f0-47f597d42d70"
version = "5.1.2+0"

[[MUMPS_seq_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "METIS_jll", "OpenBLAS32_jll", "Pkg", "libblastrampoline_jll"]
git-tree-sha1 = "f429d6bbe9ad015a2477077c9e89b978b8c26558"
uuid = "d7ed1dd3-d0ae-5e8e-bfb4-87a502085b8d"
version = "500.500.101+0"

[[MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "SnoopPrecompile", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "f219b62e601c2f2e8adb7b6c48db8a9caf381c82"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.13.1"

[[MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[Memento]]
deps = ["Dates", "Distributed", "Requires", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "bb2e8f4d9f400f6e90d57b34860f6abdc51398e5"
uuid = "f28f55f0-a522-5efc-85c2-fe41dfb9b2d9"
version = "1.4.1"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "3295d296288ab1a0a2528feb424b854418acff57"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.2.3"

[[NLSolversBase]]
deps = ["DiffResults", "Distributed", "FiniteDiff", "ForwardDiff"]
git-tree-sha1 = "a0b464d183da839699f4c79e7606d9d186ec172c"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "7.8.3"

[[NLsolve]]
deps = ["Distances", "LineSearches", "LinearAlgebra", "NLSolversBase", "Printf", "Reexport"]
git-tree-sha1 = "019f12e9a1a7880459d0173c182e6a99365d7ac1"
uuid = "2774e3e8-f4cf-5e23-947b-6d7e65073b56"
version = "4.5.1"

[[NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c6c2ed4b7acd2137b878eb96c68e63b76199d0f"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.17+0"

[[OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+0"

[[OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "6503b77492fd7fcb9379bf73cd31035670e3c509"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.3.3"

[[OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9ff31d101d987eb9d66bd8b176ac7c277beccd09"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.20+0"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[Parsers]]
deps = ["Dates", "SnoopPrecompile"]
git-tree-sha1 = "478ac6c952fddd4399e71d4779797c538d0ff2bf"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.5.8"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[PolyhedralRelaxations]]
deps = ["DataStructures", "ForwardDiff", "JuMP", "Logging", "LoggingExtras"]
git-tree-sha1 = "05f2adc696ae9a99be3de99dd8970d00a4dccefe"
uuid = "2e741578-48fa-11ea-2d62-b52c946f73a0"
version = "0.3.5"

[[PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[PowerModels]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "NLsolve", "SparseArrays"]
git-tree-sha1 = "951986db4efc4effb162e96d1914de35d876e48c"
uuid = "c36e90e8-916a-50a6-bd94-075b64ef4655"
version = "0.19.8"

[[PowerModelsDistribution]]
deps = ["CSV", "Dates", "FilePaths", "Glob", "InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Logging", "LoggingExtras", "PolyhedralRelaxations", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "fd2a5efc06acb1b449a985c48d4b3d8004a3b371"
uuid = "d7431456-977f-11e9-2de3-97ff7677985e"
version = "0.14.7"

[[PowerModelsONM]]
deps = ["ArgParse", "Combinatorics", "Dates", "Distributed", "EzXML", "Graphs", "HiGHS", "Hwloc", "InfrastructureModels", "Ipopt", "JSON", "JSONSchema", "JuMP", "Juniper", "LinearAlgebra", "Logging", "LoggingExtras", "Pkg", "PolyhedralRelaxations", "PowerModelsDistribution", "PowerModelsProtection", "PowerModelsStability", "Requires", "SHA", "Statistics", "StatsBase", "UUIDs"]
git-tree-sha1 = "07afe97994fe16a853410cddb33bbcb4fb4326a3"
uuid = "25264005-a304-4053-a338-565045d392ac"
version = "3.3.0"

[[PowerModelsProtection]]
deps = ["Graphs", "InfrastructureModels", "JuMP", "LinearAlgebra", "PowerModels", "PowerModelsDistribution", "Printf"]
git-tree-sha1 = "1c029770e1abe7b0970f49fc7791ea5704c4d00e"
uuid = "719c1aef-945b-435a-a240-4c2992e5e0df"
version = "0.5.2"

[[PowerModelsStability]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "PowerModelsDistribution"]
git-tree-sha1 = "758392c148f671473aad374a24ff26db72bc36cf"
uuid = "f9e4c324-c3b6-4bca-9c3d-419775f0bd17"
version = "0.3.2"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "77d3c4726515dca71f6d80fbb5e251088defe305"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.18"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "a4ada03f999bd01b3a25dcaa30b2d929fe537e00"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.1.0"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "ef28127915f4229c971eb43f3fc075dd3fe91880"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.2.0"

[[StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "6aa098ef1012364f2ede6b17bf358c7f1fbe90d4"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.17"

[[StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f9af7f195fb13589dd2e2d57fdb401717d2eb1f6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.5.0"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "1544b926975372da01227b382066ab70e574a3ec"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.1"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.1"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[TextWrap]]
git-tree-sha1 = "9250ef9b01b66667380cf3275b3f7488d0e25faf"
uuid = "b718987f-49a8-5099-9789-dcd902bef87d"
version = "1.0.1"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "94f38103c984f89cf77c402f2a68dbd870f8165f"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.11"

[[URIs]]
git-tree-sha1 = "074f993b0ca030848b897beff716d93aca60f06a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.2"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "93c41695bc1c08c46c5899f4fe06d6ead504bb73"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.10.3+0"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╠═26682490-9b7d-11ed-0507-6f82e14e7dee
# ╠═af37d952-9c0c-4801-a3a5-6ce57e645460
# ╠═5607facf-bede-4816-9280-f0bb6706857c
# ╠═5f2ccc29-9cfe-4a4b-9b5b-5a27feb2c1e7
# ╠═22bba14f-b8a2-4182-8984-d86d02ece5f3
# ╠═869740d0-ff54-4a6a-b322-e369748c5783
# ╠═8dfe4c01-b8ce-419a-8c1e-79360214eebe
# ╠═1649391d-239d-40c8-a148-dca2c4fb5167
# ╠═8a71bd48-86ab-4be8-8590-6a8819b2e074
# ╠═470b32c7-bbc4-4e32-b4f6-3af6eb3b678e
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
