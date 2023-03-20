### A Pluto.jl notebook ###
# v0.19.22

using Markdown
using InteractiveUtils

# ╔═╡ bbe09ba9-63fb-4b33-ae27-eb05cb9fd936
html"""
<style>
	main {
		margin: 0 auto;
		max-width: 2000px;
    	padding-left: max(160px, 10%);
    	padding-right: max(160px, 10%);
	}
</style>
"""

# ╔═╡ bdfca444-f5f0-413f-8a47-8346de453d12
md"""# JuMP Model by Hand - MLD-Block

This notebook is intended to illustrate how one would build the JuMP model for a MLD problem of the "block" type (i.e., `build_block_mld(pm::AbstractUBFModels)`) with the LinDist3Flow (i.e., `LPUBFDiagPowerModel`) formulation.

## Outline

### Environment Setup

This is based on `PowerModelsONM.jl@3.0.0`.

### Solver

This notebook uses the [HiGHS solver](https://github.com/jump-dev/HiGHS.jl).

### Data Model

This notebook uses a modified IEEE-13 case that is [included in PowerModelsONM.jl](https://github.com/lanl-ansi/PowerModelsONM.jl/blob/v3.0.0/test/data/ieee13_feeder.dss).

What is loaded here is the single-network, **not** multinetwork (i.e., time-series) version of the feeder.

There are two bounds that need to be included for the problem being defined in this notebook, voltage bounds on buses, which are applied via the function `apply_voltage_bounds!`, and a switch close-action upper bound.

### JuMP Model

Next we build two versions of the JuMP model. The first is one built using the included PowerModelsONM.jl functions: specifically, `instantiate_onm_model`. The second JuMP model is the one we build by hand, avoiding multiple dispatch, so as to make it explicit each variable and constraint that is contained in the model.

### Model comparison

At the end we do a quick comparison of the two models, and look at their solutions to ensure that they are equivalent.
"""

# ╔═╡ 3b579de0-8d2a-4e94-8daf-0d3833a90ab4
md"## Environment Setup"

# ╔═╡ ad36afcf-6a7e-4913-b15a-5f19ba383b27
begin
	import PowerModelsONM as ONM
	import PowerModelsDistribution as PMD
	import InfrastructureModels as IM
	import JuMP
	import HiGHS
	import LinearAlgebra
end

# ╔═╡ 4de82775-e012-44a5-a440-d7f54792d284
onm_path = joinpath(dirname(pathof(ONM)), "..")

# ╔═╡ b41082c7-87f1-42e3-8c20-4d6cddc79375
md"## Solver Instance Setup"

# ╔═╡ 7b252a89-19e4-43ba-b795-24299074753e
solver = JuMP.optimizer_with_attributes(
	HiGHS.Optimizer,
	"presolve"=>"off",
	"primal_feasibility_tolerance"=>1e-6,
	"dual_feasibility_tolerance"=>1e-6,
	"mip_feasibility_tolerance"=>1e-4,
	"mip_rel_gap"=>1e-4,
	"small_matrix_value"=>1e-12,
	"allow_unbounded_or_infeasible"=>true
)

# ╔═╡ d7dbea25-f1b1-4823-982b-0d5aa9d6ea26
md"""## Data Model Setup

This notebook uses the modified IEEE13 disitribution feeder case that is included in PowerModelsONM.jl

This uses the `parse_file` function included in PowerModelsDistribution.jl, which is a dependency of PowerModelsONM.jl.
"""

# ╔═╡ cc2aba3c-a412-4c20-8635-2cdcf369d2c8
eng = PMD.parse_file(joinpath(onm_path, "test/data/ieee13_feeder.dss"))

# ╔═╡ e66a945e-f437-4ed6-9702-1daf3bccc958
md"""### Set max actions

In order to run the block-mld problem in ONM, an upper bound for the number of switch closing-actions is required. In this case, because the network data is **not** multinetwork, we will set the upper bound to `Inf`, but typically one would want to apply a per-timestep limit to see a progression of switching actions.
"""

# ╔═╡ 88beadb3-e87b-46e4-8aec-826324cd6112
eng["switch_close_actions_ub"] = Inf

# ╔═╡ 588344bb-6f8b-463e-896d-725ceb167cb4
md"""### Apply voltage bounds

For several of the linearizations of constraints, finite voltage bounds are required. Here we can apply voltage bounds using PowerModelsDistribution.jl's `apply_voltage_bounds!` function, which will apply per-unit bounds of `0.9 <= vm <= 1.1` by default, though those can be altered in the function call.
"""

# ╔═╡ 8f41758a-5523-487d-9a5b-712ffec668ee
PMD.apply_voltage_bounds!(eng)

# ╔═╡ b9582cb1-0f92-42ef-88b8-fb7e98ff6c3b
md"""### Convert ENGINEERING to MATHEMATICAL Model

To build a JuMP model, we require the `MATHEMATICAL` representation of the network model, which is normally performed automatically by PowerModelsDistribution, but here we need to do it manually using `transform_data_model`.

The ONM version of this function used below includes several augmentations required to pass along extra data parameters that are not contained in the base PowerModelsDistribution data models.
"""

# ╔═╡ 6fa5d4f4-997d-4340-bdc5-1b2801815351
math = ONM.transform_data_model(eng)

# ╔═╡ ebe9dc84-f289-4ae4-bd26-6071106d6a28
md"""### Build ref structure

When building the JuMP model, we heavily utilitize a `ref` data structure, which creates several helper data structures that make iterating through the data easier. Again, normally this structure is created automatically, but to manually build a JuMP model we need to build it manually. Also, normally there are top-level keys that are not necessary for the building of this non-multi-infrastructure, non-multinetwork data model, so we have abstracted them out.
"""

# ╔═╡ e096d427-0916-40be-8f05-444e8f37b410
ref = IM.build_ref(
	math,
	PMD.ref_add_core!,
	union(ONM._default_global_keys, PMD._pmd_math_global_keys),
	PMD.pmd_it_name;
	ref_extensions=ONM._default_ref_extensions
)[:it][:pmd][:nw][IM.nw_id_default]


# ╔═╡ e6496923-ee2b-46a0-9d81-624197d3cb02
md"""## JuMP Model by Hand

In this Section, we will actually build the JuMP Model by hand.

First we need to create an empty JuMP Model.
"""

# ╔═╡ afc66e0a-8aed-4d1a-9cf9-15f537b57b95
model = JuMP.Model()

# ╔═╡ 0590de28-76c6-485a-ae8e-bf76c0c9d924
md"""### Variables

This section will add all the variables necessary for the block-mld problem, in the same order that variables are created in `build_block_mld`.
"""

# ╔═╡ 379efc70-7458-41f5-a8d4-dcdf59fc9a6e
md"""#### Block variables

These variables are used to represent the "status", i.e., whether they are energized or not, of each of the possible load-blocks.
"""

# ╔═╡ c19ed861-e91c-44e6-b0be-e4b56629481c
# variable_block_indicator
z_block = JuMP.@variable(
	model,
	[i in keys(ref[:blocks])],
	base_name="0_z_block",
	lower_bound=0,
	upper_bound=1,
	binary=true
)

# ╔═╡ 4269aa45-2c4c-4be5-8776-d25b39e5fe90
md"""#### Inverter variables

These variables are used to represent whether an "inverter" object, i.e., generator, solar PV, energy storage, etc., are Grid Forming (`1`) or Grid Following (`0`).
"""

# ╔═╡ 962476bf-fa55-484d-b9f6-fc09d1d891ee
# variable_inverter_indicator
z_inverter = Dict(
	(t,i) => get(ref[t][i], "inverter", 1) == 1 ? JuMP.@variable(
		model,
		base_name="0_$(t)_z_inverter_$(i)",
		binary=true,
		lower_bound=0,
		upper_bound=1,
	) : 0 for t in [:storage, :gen] for i in keys(ref[t])
)

# ╔═╡ 1480b91d-fcbb-46c1-9a47-c4daa99731a2
md"""#### Bus voltage variables

These variables are used to represent the squared voltage magnitudes `w` for each terminal on each bus.

By default, voltage magnitudes have a lower bound of `0.0` to avoid infeasibilities, since this is an on-off problem. There are constraints applied later that enforce lower-bounds based on `z_block`.
"""

# ╔═╡ 04eea7b8-ff6c-4650-b01e-31301257ded4
# variable_mc_bus_voltage_on_off -> variable_mc_bus_voltage_magnitude_sqr_on_off
w = Dict(
	i => JuMP.@variable(
		model,
		[t in bus["terminals"]],
		base_name="0_w_$i",
		lower_bound=0,
	) for (i,bus) in ref[:bus]
)

# ╔═╡ 05312fc9-b125-42e8-a9bd-7129f63ddc9a
md"As noted above, we do require finite upper bounds on voltage magnitudes"

# ╔═╡ 91014d35-e30b-4af7-9324-3cde48242342
# w bounds
for (i,bus) in ref[:bus]
	for (idx,t) in enumerate(bus["terminals"])
		isfinite(bus["vmax"][idx]) && JuMP.set_upper_bound(w[i][t], bus["vmax"][idx]^2)
	end
end

# ╔═╡ 3277219e-589d-47db-9374-e6712a4a40c4
md"""#### Branch variables

`variable_mc_branch_power`

These variables represent the real and reactive powers on the from- and to-sides of each of the branches, for each from- and to-connection on that branch.
"""

# ╔═╡ ac115a18-ce73-436a-800e-a83b27c6cee7
branch_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_branch] for ((l,i,j), connections) in entry)

# ╔═╡ bca9289f-bf4f-4ec2-af5f-373b70b4e614
# variable_mc_branch_power_real
p = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in ref[:branch][l]["f_connections"]],
			base_name="0_p_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_branch_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in ref[:branch][l]["t_connections"]],
			base_name="0_p_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_branch_to]
	)...,
)

# ╔═╡ beb258c4-97da-4044-b8d1-abc695e8a910
# p bounds
for (l,i,j) in ref[:arcs_branch]
	smax = PMD._calc_branch_power_max(ref[:branch][l], ref[:bus][i])
	for (idx, c) in enumerate(branch_connections[(l,i,j)])
		PMD.set_upper_bound(p[(l,i,j)][c],  smax[idx])
		PMD.set_lower_bound(p[(l,i,j)][c], -smax[idx])
	end
end

# ╔═╡ e00d2fdc-a416-4259-b29e-b5608897da9b
# variable_mc_branch_power_imaginary
q = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in ref[:branch][l]["f_connections"]],
			base_name="0_q_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_branch_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in ref[:branch][l]["t_connections"]],
			base_name="0_q_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_branch_to]
	)...,
)

# ╔═╡ 855a0057-610a-4274-86bb-95ceef674257
# q bounds
for (l,i,j) in ref[:arcs_branch]
	smax = PMD._calc_branch_power_max(ref[:branch][l], ref[:bus][i])
	for (idx, c) in enumerate(branch_connections[(l,i,j)])
		PMD.set_upper_bound(q[(l,i,j)][c],  smax[idx])
		PMD.set_lower_bound(q[(l,i,j)][c], -smax[idx])
	end
end

# ╔═╡ 080a174a-c63b-4284-a06d-1031fda7e3a9
md"""#### Switch variables

`variable_mc_switch_power`

These variables represent the from- and to-side real and reactive powers on switches for each from- and to-side connection on the switch.

Because switches are modeled as zero-length objects, the from- and to-side powers are equivalent, and therefore an explicit type erasure is necessary.
"""

# ╔═╡ 3177e943-c635-493a-9be6-c2ade040c447
switch_arc_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_switch] for ((l,i,j), connections) in entry)

# ╔═╡ 5e0f7d2d-d6f9-40d9-b3a4-4404c2c66950
# variable_mc_switch_power_real
psw = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in switch_arc_connections[(l,i,j)]],
			base_name="0_psw_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_switch_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in switch_arc_connections[(l,i,j)]],
			base_name="0_psw_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_switch_to]
	)...,
)

# ╔═╡ 6c8163e3-5a18-4561-a9f4-834e42657f7d
# _psw bounds
for (l,i,j) in ref[:arcs_switch]
	smax = PMD._calc_branch_power_max(ref[:switch][l], ref[:bus][i])
	for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
		PMD.set_upper_bound(psw[(l,i,j)][c],  smax[idx])
		PMD.set_lower_bound(psw[(l,i,j)][c], -smax[idx])
	end
end

# ╔═╡ 9f98ca07-532d-4fc6-a1bd-13a182b0db50
# this explicit type erasure is necessary
begin
    psw_expr = Dict( (l,i,j) => psw[(l,i,j)] for (l,i,j) in ref[:arcs_switch_from] )
    psw_expr = merge(psw_expr, Dict( (l,j,i) => -1.0.*psw[(l,i,j)] for (l,i,j) in ref[:arcs_switch_from]))

    # This is needed to get around error: "unexpected affine expression in nlconstraint"
    psw_auxes = Dict(
        (l,i,j) => JuMP.@variable(
            model, [c in switch_arc_connections[(l,i,j)]],
            base_name="0_psw_aux_$((l,i,j))"
		) for (l,i,j) in ref[:arcs_switch]
    )
    for ((l,i,j), psw_aux) in psw_auxes
        for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
            JuMP.@constraint(model, psw_expr[(l,i,j)][c] == psw_aux[c])
        end
    end

	# overwrite psw
	for (k,psw_aux) in psw_auxes
		psw[k] = psw_aux
	end
end

# ╔═╡ 7f709599-084b-433f-9b6a-6ded827b69f2
# variable_mc_switch_power_imaginary
qsw = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in switch_arc_connections[(l,i,j)]],
			base_name="0_qsw_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_switch_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in switch_arc_connections[(l,i,j)]],
			base_name="0_qsw_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_switch_to]
	)...,
)

# ╔═╡ b84ba9e4-5ce2-4b10-bb45-eed88c6a4bbe
# qsw bounds
for (l,i,j) in ref[:arcs_switch]
	smax = PMD._calc_branch_power_max(ref[:switch][l], ref[:bus][i])
	for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
		PMD.set_upper_bound(qsw[(l,i,j)][c],  smax[idx])
		PMD.set_lower_bound(qsw[(l,i,j)][c], -smax[idx])
	end
end

# ╔═╡ 5e538b33-20ae-4520-92ec-efc01494ffcc
# this explicit type erasure is necessary
begin
    qsw_expr = Dict( (l,i,j) => qsw[(l,i,j)] for (l,i,j) in ref[:arcs_switch_from] )
    qsw_expr = merge(qsw_expr, Dict( (l,j,i) => -1.0.*qsw[(l,i,j)] for (l,i,j) in ref[:arcs_switch_from]))

    # This is needed to get around error: "unexpected affine expression in nlconstraint"
    qsw_auxes = Dict(
        (l,i,j) => JuMP.@variable(
            model, [c in switch_arc_connections[(l,i,j)]],
            base_name="0_qsw_aux_$((l,i,j))"
		) for (l,i,j) in ref[:arcs_switch]
    )
    for ((l,i,j), qsw_aux) in qsw_auxes
        for (idx, c) in enumerate(switch_arc_connections[(l,i,j)])
            JuMP.@constraint(model, qsw_expr[(l,i,j)][c] == qsw_aux[c])
        end
    end

	# overwrite psw
	for (k,qsw_aux) in qsw_auxes
		qsw[k] = qsw_aux
	end
end

# ╔═╡ 44b283ee-e28c-473d-922f-8f1b8f982f10
# variable_switch_state
z_switch = Dict(i => JuMP.@variable(
	model,
	base_name="0_switch_state",
	binary=true,
	lower_bound=0,
	upper_bound=1,
) for i in keys(ref[:switch_dispatchable]))

# ╔═╡ e910ae7a-680e-44a5-a35d-cabe2dfa50d0
# fixed switches
for i in [i for i in keys(ref[:switch]) if !(i in keys(ref[:switch_dispatchable]))]
	z_switch[i] = ref[:switch][i]["state"]
end

# ╔═╡ 44fe57a1-edce-45c7-9a8b-40857bddc285
md"""#### Transformer variables

`variable_mc_transformer_power`

These variables represent the from- and to-side real and reactive powers for transformers for each from- and to-side connection.
"""

# ╔═╡ 06523a91-4665-4e31-b6e2-732cbfd0e0e4
transformer_connections = Dict((l,i,j) => connections for (bus,entry) in ref[:bus_arcs_conns_transformer] for ((l,i,j), connections) in entry)

# ╔═╡ 867253fa-32ee-4ab4-bc42-3f4c2f0e5fa4
# variable_mc_transformer_power_real
pt = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in transformer_connections[(l,i,j)]],
			base_name="0_pt_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_transformer_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in transformer_connections[(l,i,j)]],
			base_name="0_pt_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_transformer_to]
	)...,
)

# ╔═╡ 6e61aac8-5a50-47a7-a150-6557a47e2d3b
# pt bounds
for arc in ref[:arcs_transformer_from]
	(l,i,j) = arc
	rate_a_fr, rate_a_to = PMD._calc_transformer_power_ub_frto(ref[:transformer][l], ref[:bus][i], ref[:bus][j])

	for (idx, (fc,tc)) in enumerate(zip(transformer_connections[(l,i,j)], transformer_connections[(l,j,i)]))
		PMD.set_lower_bound(pt[(l,i,j)][fc], -rate_a_fr[idx])
		PMD.set_upper_bound(pt[(l,i,j)][fc],  rate_a_fr[idx])
		PMD.set_lower_bound(pt[(l,j,i)][tc], -rate_a_to[idx])
		PMD.set_upper_bound(pt[(l,j,i)][tc],  rate_a_to[idx])
	end
end

# ╔═╡ a675e62f-c55e-4d70-85d8-83b5845cd063
# variable_mc_transformer_power_imaginary
qt = Dict(
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in transformer_connections[(l,i,j)]],
			base_name="0_qt_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_transformer_from]
	)...,
	Dict(
		(l,i,j) => JuMP.@variable(
			model,
			[c in transformer_connections[(l,i,j)]],
			base_name="0_qt_($l,$i,$j)"
		) for (l,i,j) in ref[:arcs_transformer_to]
	)...,
)

# ╔═╡ 732df933-40ca-409c-9d88-bb80ea6d21b0
# qt bounds
for arc in ref[:arcs_transformer_from]
	(l,i,j) = arc
	rate_a_fr, rate_a_to = PMD._calc_transformer_power_ub_frto(ref[:transformer][l], ref[:bus][i], ref[:bus][j])

	for (idx, (fc,tc)) in enumerate(zip(transformer_connections[(l,i,j)], transformer_connections[(l,j,i)]))
		PMD.set_lower_bound(qt[(l,i,j)][fc], -rate_a_fr[idx])
		PMD.set_upper_bound(qt[(l,i,j)][fc],  rate_a_fr[idx])
		PMD.set_lower_bound(qt[(l,j,i)][tc], -rate_a_to[idx])
		PMD.set_upper_bound(qt[(l,j,i)][tc],  rate_a_to[idx])
	end
end

# ╔═╡ 17002ccb-16c2-449c-849a-70f090fea5e6
md"""
`variable_mc_oltc_tansformer_tap`

The following variables represent the tap ratio of the transformer for each non-fixed-tap connection on the transformer"""

# ╔═╡ fdb80bf1-8c88-474e-935c-9e7c230b5b72
p_oltc_ids = [id for (id,trans) in ref[:transformer] if !all(trans["tm_fix"])]

# ╔═╡ 9de1c3d1-fb60-42e2-8d53-111842337458
# variable_mc_oltc_transformer_tap
tap = Dict(
	i => JuMP.@variable(
		model,
        [p in 1:length(ref[:transformer][i]["f_connections"])],
		base_name="0_tm_$(i)",
	) for i in keys(filter(x->!all(x.second["tm_fix"]), ref[:transformer]))
)

# ╔═╡ 7cf6b40c-f89b-44bc-847d-a06a92d86098
# tap bounds
for tr_id in p_oltc_ids, p in 1:length(ref[:transformer][tr_id]["f_connections"])
	PMD.set_lower_bound(tap[tr_id][p], ref[:transformer][tr_id]["tm_lb"][p])
	PMD.set_upper_bound(tap[tr_id][p], ref[:transformer][tr_id]["tm_ub"][p])
end

# ╔═╡ 9d51b315-b501-4140-af02-b645f04ec7a7
md"""#### Generator variables

`variable_mc_generator_power_on_off`

The following variables represent the real and reactive powers for each connection of generator objects.

Because these are "on-off" variables, the bounds need to at least include `0.0`
"""

# ╔═╡ dabecbec-8cd0-48f7-8a13-0bdecd45eb85
# variable_mc_generator_power_real_on_off
pg = Dict(
	i => JuMP.@variable(
		model,
        [c in gen["connections"]],
		base_name="0_pg_$(i)",
	) for (i,gen) in ref[:gen]
)

# ╔═╡ c0764ed0-4b2c-4bf5-98db-9b7349560530
# pg bounds
for (i,gen) in ref[:gen]
	for (idx,c) in enumerate(gen["connections"])
		isfinite(gen["pmin"][idx]) && JuMP.set_lower_bound(pg[i][c], min(0.0, gen["pmin"][idx]))
		isfinite(gen["pmax"][idx]) && JuMP.set_upper_bound(pg[i][c], gen["pmax"][idx])
	end
end

# ╔═╡ 733cb346-2d08-4c35-8596-946b31ecc7e9
# variable_mc_generator_power_imaginary_on_off
qg = Dict(
	i => JuMP.@variable(
		model,
        [c in gen["connections"]],
		base_name="0_qg_$(i)",
	) for (i,gen) in ref[:gen]
)

# ╔═╡ 466f22aa-52ff-442f-be00-f4f32e24a173
# qg bounds
for (i,gen) in ref[:gen]
	for (idx,c) in enumerate(gen["connections"])
		isfinite(gen["qmin"][idx]) && JuMP.set_lower_bound(qg[i][c], min(0.0, gen["qmin"][idx]))
		isfinite(gen["qmax"][idx]) && JuMP.set_upper_bound(qg[i][c], gen["qmax"][idx])
	end
end

# ╔═╡ e10f9a86-74f1-4dfb-87c9-fcd920e23c27
md"""#### Storage variables

`variable_mc_storage_power_mi_on_off`

These variables represent all of the variables that are required to model storage objects, including:

- real and reactive power variables
- imaginary power control variables
- stored energy
- charging and discharging variables
- indicator variables for charging and discharging
"""

# ╔═╡ efc78626-3a50-4c7d-8a7d-ba2b67df57e3
# variable_mc_storage_power_real_on_off
ps = Dict(
	i => JuMP.@variable(
		model,
        [c in ref[:storage][i]["connections"]],
		base_name="0_ps_$(i)",
	) for i in keys(ref[:storage])
)

# ╔═╡ e841b4d8-1e8e-4fd9-b805-4ee0c6359df5
# ps bounds
for (i,strg) in ref[:storage]
	flow_lb, flow_ub = PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])
	for (idx, c) in enumerate(strg["connections"])
		if !isinf(flow_lb[i][idx])
			PMD.set_lower_bound(ps[i][c], flow_lb[i][idx])
		end
		if !isinf(flow_ub[i][idx])
			PMD.set_upper_bound(ps[i][c], flow_ub[i][idx])
		end
	end
end

# ╔═╡ de4839e1-5ac0-415d-8928-e4a9a358deae
# variable_mc_storage_power_imaginary_on_off
qs = Dict(
	i => JuMP.@variable(
		model,
        [c in ref[:storage][i]["connections"]],
		base_name="0_qs_$(i)",
	) for i in keys(ref[:storage])
)

# ╔═╡ 1b858a96-f894-4276-90a2-aa9833d9dd37
# qs bounds
for (i,strg) in ref[:storage]
	flow_lb, flow_ub =PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])
	for (idx, c) in enumerate(strg["connections"])
		if !isinf(flow_lb[i][idx])
			PMD.set_lower_bound(qs[i][c], flow_lb[i][idx])
		end
		if !isinf(flow_ub[i][idx])
			PMD.set_upper_bound(qs[i][c], flow_ub[i][idx])
		end
	end
end

# ╔═╡ 70dec0fa-a87c-4266-819d-a2ad5903d24a
# variable_mc_storage_power_control_imaginary_on_off
qsc = JuMP.@variable(
	model,
	[i in keys(ref[:storage])],
	base_name="0_qsc_$(i)"
)

# ╔═╡ 463ae91e-5533-46d0-8907-32f9d5ba17cf
# qsc bounds
for (i,storage) in ref[:storage]
	inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])
	if isfinite(sum(inj_lb[i])) || haskey(storage, "qmin")
		lb = max(sum(inj_lb[i]), sum(get(storage, "qmin", -Inf)))
		JuMP.set_lower_bound(qsc[i], min(lb, 0.0))
	end
	if isfinite(sum(inj_ub[i])) || haskey(storage, "qmax")
		ub = min(sum(inj_ub[i]), sum(get(storage, "qmax", Inf)))
		JuMP.set_upper_bound(qsc[i], max(ub, 0.0))
	end
end

# ╔═╡ 00aa935b-0f1a-43ae-8437-bde5e34c1fcd
# variable_storage_energy
se = JuMP.@variable(model,
	[i in keys(ref[:storage])],
	base_name="0_se",
	lower_bound = 0.0,
)

# ╔═╡ cafb8b69-ebc1-49d6-afe5-ff8af54eb222
# se bounds
for (i, storage) in ref[:storage]
	PMD.set_upper_bound(se[i], storage["energy_rating"])
end

# ╔═╡ bc2c0bea-621c-45f6-bc72-3d8907a280dc
# variable_storage_charge
sc = JuMP.@variable(model,
	[i in keys(ref[:storage])],
	base_name="0_sc",
	lower_bound = 0.0,
)

# ╔═╡ 503bdbad-70f8-42d2-977b-af6ba06b2cde
# sc bounds
for (i, storage) in ref[:storage]
	PMD.set_upper_bound(sc[i], storage["charge_rating"])
end

# ╔═╡ e8dfb521-6750-4df6-b4ff-0cabf5989e8f
# variable_storage_discharge
sd = JuMP.@variable(model,
	[i in keys(ref[:storage])],
	base_name="0_sd",
	lower_bound = 0.0,
)

# ╔═╡ 70850ada-165a-4e0d-942a-9dc311add0a6
# sd bounds
for (i, storage) in ref[:storage]
	PMD.set_upper_bound(sd[i], storage["discharge_rating"])
end

# ╔═╡ d226e83d-b405-4dd3-9697-471bdbff97a2
# variable_storage_complementary_indicator
sc_on = JuMP.@variable(model,
	[i in keys(ref[:storage])],
	base_name="0_sc_on",
	binary = true,
	lower_bound=0,
	upper_bound=1
)

# ╔═╡ 050f3e9f-62e9-445d-8c95-9f0419c01c0e
# variable_storage_complementary_indicator
sd_on = JuMP.@variable(model,
	[i in keys(ref[:storage])],
	base_name="0_sd_on",
	binary = true,
	lower_bound=0,
	upper_bound=1
)

# ╔═╡ eb1af86d-a40c-411d-a211-d7a43386bf44
md"""#### Load variables

`variable_mc_load_power`

This initializes some power variables for loads. At this point, only variables for certain types of loads are required, and otherwise the load variables are largely created by the load constraints that are applied later on.

The types of loads that need to be created ahead of time are:

- Complex power matrix variables for delta loads
- Complex current matrix variables for delta loads
- Real and reactive power variables for wye loads that require cone constraints (e.g., constant current loads)

We also want to create the empty variable dictionaries so that we can populate them with the constraints later.

It should be noted that there are two variables for loads, `pd/qd_bus` and `pd/qd`. The `_bus` variables are related to the non-`_bus` variables depending on the type of connection of the load. See [PowerModelsDistribution documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/stable/manual/load-model.html) for details.
"""

# ╔═╡ ace2c946-7984-4c17-bedb-06dccd6e8a36
load_wye_ids = [id for (id, load) in ref[:load] if load["configuration"]==PMD.WYE]

# ╔═╡ 8386d993-ffcc-4c6a-a91b-247f8c97a2ff
load_del_ids = [id for (id, load) in ref[:load] if load["configuration"]==PMD.DELTA]

# ╔═╡ b5408b8a-eff4-4d42-9ba7-707a40d92956
load_cone_ids = [id for (id, load) in ref[:load] if PMD._check_load_needs_cone(load)]

# ╔═╡ b7a7e78a-8f0f-4f47-9f37-8ecf3ddc4972
load_connections = Dict{Int,Vector{Int}}(id => load["connections"] for (id,load) in ref[:load])

# ╔═╡ 86d65cab-d073-4e77-bc0f-3d7e135dcbf8
begin
	pd = Dict()
	qd = Dict()
	pd_bus = Dict()
	qd_bus = Dict()

	# variable_mc_load_power_delta_aux
    bound = Dict{eltype(load_del_ids), Matrix{Real}}()
    for id in load_del_ids
        load = ref[:load][id]
        bus_id = load["load_bus"]
        bus = ref[:bus][bus_id]
        cmax = PMD._calc_load_current_max(load, bus)
        bound[id] = bus["vmax"][[findfirst(isequal(c), bus["terminals"]) for c in load_connections[id]]]*cmax'
    end
    (Xdr,Xdi) = PMD.variable_mx_complex(model, load_del_ids, load_connections, load_connections; symm_bound=bound, name="0_Xd")

	# variable_mc_load_current
    cmin = Dict{eltype(load_del_ids), Vector{Real}}()
    cmax = Dict{eltype(load_del_ids), Vector{Real}}()
    for (id, load) in ref[:load]
        bus_id = load["load_bus"]
        bus = ref[:bus][bus_id]
        cmin[id], cmax[id] = PMD._calc_load_current_magnitude_bounds(load, bus)
    end
    (CCdr, CCdi) = PMD.variable_mx_hermitian(model, load_del_ids, load_connections; sqrt_upper_bound=cmax, sqrt_lower_bound=cmin, name="0_CCd")

	# variable_mc_load_power
	for i in intersect(load_wye_ids, load_cone_ids)
		pd[i] = JuMP.@variable(
			model,
        	[c in load_connections[i]],
			base_name="0_pd_$(i)"
        )
    	qd[i] = JuMP.@variable(
			model,
        	[c in load_connections[i]],
			base_name="0_qd_$(i)"
        )

		load = ref[:load][i]
		bus = ref[:bus][load["load_bus"]]
		pmin, pmax, qmin, qmax = PMD._calc_load_pq_bounds(load, bus)
		for (idx,c) in enumerate(load_connections[i])
			PMD.set_lower_bound(pd[i][c], pmin[idx])
			PMD.set_upper_bound(pd[i][c], pmax[idx])
			PMD.set_lower_bound(qd[i][c], qmin[idx])
			PMD.set_upper_bound(qd[i][c], qmax[idx])
		end
	end
end

# ╔═╡ 80c50ee0-fb55-4c2c-86dd-434524d1a5e7
md"""#### Capacitor variables

`variable_mc_capcontrol`

This model includes the ability to support capacitor controls (i.e., CapControl objects in DSS).

These variables represent

- indicator variables for the capacitor (shunt) objects
- reactive power variables for the capacitor (shunt) objects
"""

# ╔═╡ dc4d7b85-c968-4271-9e44-f80b90e4d6af
# variable_mc_capacitor_switch_state
z_cap = Dict(
	i => JuMP.@variable(
		model,
		[p in cap["connections"]],
		base_name="0_cap_sw_$(i)",
		binary = true,
	) for (i,cap) in [(id,cap) for (id,cap) in ref[:shunt] if haskey(cap,"controls")]
)

# ╔═╡ dfafbbcd-9465-4a78-867b-25703b5157ba
# variable_mc_capacitor_reactive_power
qc = Dict(
	i => JuMP.@variable(
		model,
		[p in cap["connections"]],
		base_name="0_cap_cur_$(i)",
	) for (i,cap) in [(id,cap) for (id,cap) in ref[:shunt] if haskey(cap,"controls")]
)

# ╔═╡ cae714ed-ac90-454f-b2ec-e3bb13a71056
md"""### Constraints

In this section we add our constraints
"""

# ╔═╡ 47f8d8f4-c6e3-4f78-93d3-c5bb4938a754
md"""#### Inverter constraint

This constraint requires that there be only one Grid Forming inverter (`z_inverter=1`) for any given connected-component.
"""

# ╔═╡ 378f45ee-2e0e-428b-962f-fd686bc5d063
# constraint_grid_forming_inverter_per_cc
begin
	# Set of base connected components
    L = Set(keys(ref[:blocks]))

    # variable representing if switch ab has 'color' k
    y = Dict()
    for k in L
        for ab in keys(ref[:switch])
            y[(k,ab)] = JuMP.@variable(
                model,
                base_name="0_y_gfm[$k,$ab]",
                binary=true,
                lower_bound=0,
                upper_bound=1
            )
        end
    end

    # switch pairs to ids and vise-versa
    map_id_pairs = Dict(id => (ref[:bus_block_map][sw["f_bus"]],ref[:bus_block_map][sw["t_bus"]]) for (id,sw) in ref[:switch])

    # set of *virtual* edges between component k and all other components k′
    Φₖ = Dict(k => Set() for k in L)
    map_virtual_pairs_id = Dict(k=>Dict() for k in L)

    # Eqs. (9)-(10)
    f = Dict()
    ϕ = Dict()
    for kk in L # color
        for ab in keys(ref[:switch])
            f[(kk,ab)] = JuMP.@variable(
                model,
                base_name="0_f_gfm[$kk,$ab]"
            )
            JuMP.@constraint(model, f[kk,ab] >= -length(keys(ref[:switch]))*(z_switch[ab]))
            JuMP.@constraint(model, f[kk,ab] <=  length(keys(ref[:switch]))*(z_switch[ab]))
        end

        touched = Set()
        ab = 1

        for k in sort(collect(L)) # fr block
            for k′ in sort(collect(filter(x->x!=k,L))) # to block
                if (k,k′) ∉ touched
                    map_virtual_pairs_id[kk][(k,k′)] = map_virtual_pairs_id[kk][(k′,k)] = ab
                    push!(touched, (k,k′), (k′,k))

                    ϕ[(kk,ab)] = JuMP.@variable(
                        model,
                        base_name="0_phi_gfm[$kk,$ab]",
                        lower_bound=0,
                        upper_bound=1
                    )

                    ab += 1
                end
            end
        end

        Φₖ[kk] = Set([map_virtual_pairs_id[kk][(kk,k′)] for k′ in filter(x->x!=kk,L)])
    end

    # voltage sources are always grid-forming
    for ((t,j), z_inv) in z_inverter
        if t == :gen && startswith(ref[t][j]["source_id"], "voltage_source")
            JuMP.@constraint(model, z_inv == z_block[ref[:bus_block_map][ref[t][j]["$(t)_bus"]]])
        end
    end

    # Eq. (2)
    # constrain each y to have only one color
    for ab in keys(ref[:switch])
        JuMP.@constraint(model, sum(y[(k,ab)] for k in L) <= z_switch[ab])
    end

    # storage flow upper/lower bounds
    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])

    # Eqs. (3)-(7)
    for k in L
        Dₖ = ref[:block_inverters][k]
        Tₖ = ref[:block_switches][k]

        if !isempty(Dₖ)
            # Eq. (14)
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) >= sum(1-z_switch[ab] for ab in Tₖ)-length(Tₖ)+z_block[k])
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) <= z_block[k])

            # Eq. (4)-(5)
            for (t,j) in Dₖ
                if t == :storage
                    pmin = fill(-Inf, length(ref[t][j]["connections"]))
                    pmax = fill( Inf, length(ref[t][j]["connections"]))
                    qmin = fill(-Inf, length(ref[t][j]["connections"]))
                    qmax = fill( Inf, length(ref[t][j]["connections"]))

                    for (idx,c) in enumerate(ref[t][j]["connections"])
                        pmin[idx] = inj_lb[j][idx]
                        pmax[idx] = inj_ub[j][idx]
                        qmin[idx] = max(inj_lb[j][idx], ref[t][j]["qmin"])
                        qmax[idx] = min(inj_ub[j][idx], ref[t][j]["qmax"])

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

        for ab in Tₖ
            # Eq. (6)
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) >= y[(k, ab)] - (1 - z_switch[ab]))
            JuMP.@constraint(model, sum(z_inverter[i] for i in Dₖ) <= y[(k, ab)] + (1 - z_switch[ab]))

            for dc in filter(x->x!=ab, Tₖ)
                for k′ in L
                    # Eq. (7)
                    JuMP.@constraint(model, y[(k′,ab)] >= y[(k′,dc)] - (1 - z_switch[dc]) - (1 - z_switch[ab]))
                    JuMP.@constraint(model, y[(k′,ab)] <= y[(k′,dc)] + (1 - z_switch[dc]) + (1 - z_switch[ab]))
                end
            end

            # Eq. (8)
            JuMP.@constraint(model, y[(k,ab)] <= sum(z_inverter[i] for i in Dₖ))
        end

        # Eq. (11)
        JuMP.@constraint(model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1] == k, Tₖ)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2] == k, Tₖ)) + sum(ϕ[(k,ab)] for ab in Φₖ[k]) == length(L) - 1)

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

        # Eq. (15)
        JuMP.@constraint(model, z_block[k] <= sum(z_inverter[i] for i in Dₖ) + sum(y[(k′,ab)] for k′ in L for ab in Tₖ))
    end
end

# ╔═╡ 4bfb96ae-2087-41a8-b9b0-3f4b346992a2
md"""#### Bus constraints

There are two contraints on buses:

- a constraint that enforces that a bus connected to a grid-forming inverter is a slack bus
- an "on-off" constraint that enforces that bus voltage is zero if the load block is not energized (`z_block=0`)
"""

# ╔═╡ b7a30f17-1f3b-497a-ab1c-bc9ce1ac6e56
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

# ╔═╡ d1136370-9fc2-47c6-a773-d4dc7901db83
# constraint_mc_bus_voltage_block_on_off
for (i,bus) in ref[:bus]
	# bus voltage on off constraint
	for (idx,t) in [(idx,t) for (idx,t) in enumerate(bus["terminals"]) if !bus["grounded"][idx]]
		isfinite(bus["vmax"][idx]) && JuMP.@constraint(model, w[i][t] <= bus["vmax"][idx]^2*z_block[ref[:bus_block_map][i]])
		isfinite(bus["vmin"][idx]) && JuMP.@constraint(model, w[i][t] >= bus["vmin"][idx]^2*z_block[ref[:bus_block_map][i]])
	end
end

# ╔═╡ 8e564c5e-8c0e-4001-abaa-bf9575d41089
md"""#### Generator constraints

Generators need "on-off" constraints that enforce that a generator is "off" if the load block containing it is not energized (`z_block=0`)
"""

# ╔═╡ 05b0aad1-a41b-4fe7-8b76-70848f71d9d2
# constraint_mc_generator_power_block_on_off
for (i,gen) in ref[:gen]
    for (idx, c) in enumerate(gen["connections"])
        isfinite(gen["pmin"][idx]) && JuMP.@constraint(model, pg[i][c] >= gen["pmin"][idx]*z_block[ref[:gen_block_map][i]])
        isfinite(gen["qmin"][idx]) && JuMP.@constraint(model, qg[i][c] >= gen["qmin"][idx]*z_block[ref[:gen_block_map][i]])

        isfinite(gen["pmax"][idx]) && JuMP.@constraint(model, pg[i][c] <= gen["pmax"][idx]*z_block[ref[:gen_block_map][i]])
        isfinite(gen["qmax"][idx]) && JuMP.@constraint(model, qg[i][c] <= gen["qmax"][idx]*z_block[ref[:gen_block_map][i]])
    end
end

# ╔═╡ 074845c0-f5ae-4a7c-bf94-3fcade5fdab8
md"""#### Load constraints

The following creates the load power constraints for the different supported load configurations (wye or delta) and types (constant power, constant impedance, and constant current).
"""

# ╔═╡ 8be57ed0-0c7e-40d5-b780-28eb9f9c2490
# constraint_mc_load_power
for (load_id,load) in ref[:load]
    pd0 = load["pd"]
    qd0 = load["qd"]
    bus_id = load["load_bus"]
    bus = ref[:bus][bus_id]
    terminals = bus["terminals"]

    a, alpha, b, beta = PMD._load_expmodel_params(load, bus)
    vmin, vmax = PMD._calc_load_vbounds(load, bus)
    wmin = vmin.^2
    wmax = vmax.^2
    pmin, pmax, qmin, qmax = PMD._calc_load_pq_bounds(load, bus)

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
				JuMP.@constraint(model, pd[load_id][c]==1/2*a[idx]*(w[bus_id][c]+1+(1-z_block[ref[:bus_block_map][bus_id]])))
				JuMP.@constraint(model, qd[load_id][c]==1/2*b[idx]*(w[bus_id][c]+1+(1-z_block[ref[:bus_block_map][bus_id]])))
            end
        end

		pd_bus[load_id] = pd[load_id]
        qd_bus[load_id] = qd[load_id]

    elseif load["configuration"]==PMD.DELTA
        Td = [1 -1 0; 0 1 -1; -1 0 1]

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
                JuMP.@constraint(model, pd[load_id][idx]==sqrt(3)/2*a[idx]*(w[bus_id][[c for c in load["connections"]]][idx]+1+(1-z_block[ref[:bus_block_map][bus_id]])))
                JuMP.@constraint(model, qd[load_id][idx]==sqrt(3)/2*b[idx]*(w[bus_id][[c for c in load["connections"]]][idx]+1+(1-z_block[ref[:bus_block_map][bus_id]])))
            end
        end
    end
end

# ╔═╡ 068a66eb-35ef-45ff-8448-75fe67eec38f
md"""#### Power balance constraints

The following models the power balance constraints, i.e., enforces that power-in and power-out of every bus are balanced.

This constraint can shed load, using the introduction of `z_block` to the power balance equations, and can also control capacitors.
"""

# ╔═╡ e32ada08-9f79-47b9-bfef-eaf5f8bbc058
"PMD native version requires too much information, this is a simplified function"
function build_bus_shunt_matrices(ref, terminals, bus_shunts)
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

# ╔═╡ d6c7baee-8c8e-4cd9-ba35-06edad733e91
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

    pd_zblock = Dict(l => JuMP.@variable(model, [c in conns], base_name="0_pd_zblock_$(l)") for (l,conns) in ref[:bus_conns_load][i])
    qd_zblock = Dict(l => JuMP.@variable(model, [c in conns], base_name="0_qd_zblock_$(l)") for (l,conns) in ref[:bus_conns_load][i])

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
    end
end

# ╔═╡ 5e7470f6-2bb5-49fb-93d7-1b8c8e402526
md"""#### Storage constraints

The follow models the constraints necessary to model storage, including:

- the storage "state", i.e., how much energy is remaining in the storage after the time-elapsed
- the "on-off" constraint that controls whether the storage is charging or discharging (it can only be one or another)
- the power "on-off" constraints, that ensure that the storage is off if the load block is not energized (`z_block=0`)
- the storage losses, which connects the powers to the charging/discharging variables
- the thermal limit constraints
- a storage balance constraint, which ensures that the powers outputted from the storage are within some bound of each other, if the storage is in grid following mode
"""

# ╔═╡ 8c44ebe8-a2e9-4480-b1d8-b3c19350c029
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

    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref[:storage], ref[:bus])
    for (idx,c) in enumerate(strg["connections"])
        pmin[idx] = inj_lb[i][idx]
        pmax[idx] = inj_ub[i][idx]
        qmin[idx] = max(inj_lb[i][idx], strg["qmin"])
        qmax[idx] = min(inj_ub[i][idx], strg["qmax"])
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
        qsc_zblock = JuMP.@variable(model, base_name="0_qd_zblock_$(i)")

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

    ps_sqr = [JuMP.@variable(model, base_name="0_ps_sqr_$(i)_$(c)") for c in strg["connections"]]
    qs_sqr = [JuMP.@variable(model, base_name="0_qs_sqr_$(i)_$(c)") for c in strg["connections"]]

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
	    sd_on_ps = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_ps_$(i)")
	    sc_on_ps = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_ps_$(i)")
	    sd_on_qs = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_qs_$(i)")
	    sc_on_qs = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_qs_$(i)")
	    for c in strg["connections"]
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sd_on[i], ps[i][c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sc_on[i], ps[i][c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sd_on[i], qs[i][c], sd_on_qs[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, sc_on[i], qs[i][c], sc_on_qs[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
	    end

	    ps_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_ps_zinverter_$(i)")
	    qs_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_qs_zinverter_$(i)")
	    for c in strg["connections"]
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], ps[i][c], ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[i][c]), JuMP.upper_bound(ps[i][c])])
	        PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(model, z_inverter[(:storage,i)], qs[i][c], qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[i][c]), JuMP.upper_bound(qs[i][c])])
	    end

	    sd_on_ps_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_ps_zinverter_$(i)")
	    sc_on_ps_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_ps_zinverter_$(i)")
	    sd_on_qs_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sd_on_qs_zinverter_$(i)")
	    sc_on_qs_zinverter = JuMP.@variable(model, [c in strg["connections"]], base_name="0_sc_on_qs_zinverter_$(i)")
	    for c in strg["connections"]
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

# ╔═╡ 20d08693-413b-4a52-9f54-d8f25b492b50
md"""#### Branch constraints

The following constraints model the losses, voltage differences, and limits (ampacity) across branches.
"""

# ╔═╡ f2d2375d-2ca2-4e97-87f2-5adbf250d152
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

    p_fr = p[f_idx]
    q_fr = q[f_idx]

    p_to = p[t_idx]
    q_to = q[t_idx]

    w_fr = w[f_bus]
    w_to = w[t_bus]

    f_connections = branch["f_connections"]
    t_connections = branch["t_connections"]

	# constraint_mc_power_losses
	for (idx, (fc,tc)) in enumerate(zip(f_connections, t_connections))
        JuMP.@constraint(model, p_fr[fc] + p_to[tc] == g_sh_fr[idx,idx]*w_fr[fc] +  g_sh_to[idx,idx]*w_to[tc])
        JuMP.@constraint(model, q_fr[fc] + q_to[tc] == -b_sh_fr[idx,idx]*w_fr[fc] + -b_sh_to[idx,idx]*w_to[tc])
    end

    w_fr = w[f_bus]
    w_to = w[t_bus]

    p_fr = p[f_idx]
    q_fr = q[f_idx]

	p_s_fr = [p_fr[fc]- LinearAlgebra.diag(g_sh_fr)[idx].*w_fr[fc] for (idx,fc) in enumerate(f_connections)]
    q_s_fr = [q_fr[fc]+ LinearAlgebra.diag(b_sh_fr)[idx].*w_fr[fc] for (idx,fc) in enumerate(f_connections)]

	alpha = exp(-im*2*pi/3)
    Gamma = [1 alpha^2 alpha; alpha 1 alpha^2; alpha^2 alpha 1][f_connections,t_connections]

    MP = 2*(real(Gamma).*r + imag(Gamma).*x)
    MQ = 2*(real(Gamma).*x - imag(Gamma).*r)

    N = length(f_connections)

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

        w_fr = w[f_bus][fc]
        p_fr = p[f_idx][fc]
        q_fr = q[f_idx][fc]

		angmin = branch["angmin"]
		angmax = branch["angmax"]

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

	    p_sqr_fr = [JuMP.@variable(model, base_name="0_p_sqr_$(f_idx)[$(c)]") for c in f_connections]
	    q_sqr_fr = [JuMP.@variable(model, base_name="0_q_sqr_$(f_idx)[$(c)]") for c in f_connections]

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

	    p_sqr_to = [JuMP.@variable(model, base_name="0_p_sqr_$(t_idx)[$(c)]") for c in t_connections]
	    q_sqr_to = [JuMP.@variable(model, base_name="0_q_sqr_$(t_idx)[$(c)]") for c in t_connections]

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

# ╔═╡ 978048ae-170a-4b83-8dee-1715350e75cc
md"""#### Switch constraints

The following constraints model general constraints on topology, and the powers and voltages on either side of the switch, dependent on the state of the switch (i.e., open or closed), including:

- a switch close-action limit, which limits the maximum number of switch closures allowed, but allows for unlimited switch opening actions to allow for load shedding if necessary
- a radiality constraint, which requires that the topology be a spanning forest, i.e., that each connected component have radial topology (no cycles)
- a constraint that "isolates" load blocks, which prevents switches from being closed if one load block is shed but the other is not
- a constraint that enforces zero power flow across a switch if the switch is open, and inside the power limits otherwise
- a constraint that enforaces that voltages be equal on either side of a switch if the switch is closed, and unpinned otherwise
"""

# ╔═╡ 23d0f743-d7be-400a-9972-4337ae1bffff
# constraint_switch_close_action_limit
begin
	switch_close_actions_ub = ref[:switch_close_actions_ub]

	if switch_close_actions_ub < Inf
		Δᵞs = Dict(l => JuMP.@variable(model, base_name="0_delta_switch_state_$(l)") for l in keys(ref[:switch_dispatchable]))
		for (s, Δᵞ) in Δᵞs
			γ = z_switch[s]
			γ₀ = JuMP.start_value(γ)
			JuMP.@constraint(model, Δᵞ >=  γ * (1 - γ₀))
			JuMP.@constraint(model, Δᵞ >= -γ * (1 - γ₀))
		end

		JuMP.@constraint(model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= switch_close_actions_ub)
	end
end

# ╔═╡ a63763bf-1f87-400e-b4cd-b112c9a0cd64
# constraint_radial_topology
begin
	f_rad = Dict()
    λ = Dict()
    β = Dict()
    α = Dict()

    _N₀ = collect(keys(ref[:blocks]))
    _L₀ = ref[:block_pairs]

    virtual_iᵣ = maximum(_N₀)+1
    _N = [_N₀..., virtual_iᵣ]
    iᵣ = [virtual_iᵣ]

    _L = [_L₀..., [(virtual_iᵣ, n) for n in _N₀]...]
    _L′ = union(_L, Set([(j,i) for (i,j) in _L]))

    for (i,j) in _L′
        for k in filter(kk->kk∉iᵣ,_N)
            f_rad[(k, i, j)] = JuMP.@variable(model, base_name="0_f_$((k,i,j))")
        end
        λ[(i,j)] = JuMP.@variable(model, base_name="0_lambda_$((i,j))", binary=true, lower_bound=0, upper_bound=1)

        if (i,j) ∈ _L₀
            β[(i,j)] = JuMP.@variable(model, base_name="0_beta_$((i,j))", lower_bound=0, upper_bound=1)
        end
    end

    for (s,sw) in ref[:switch]
        (i,j) = (ref[:bus_block_map][sw["f_bus"]], ref[:bus_block_map][sw["t_bus"]])
        α[(i,j)] = z_switch[s]
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

    JuMP.@constraint(model, sum((λ[(i,j)] + λ[(j,i)]) for (i,j) in _L) == length(_N) - 1)

    for (i,j) in _L₀
        JuMP.@constraint(model, λ[(i,j)] + λ[(j,i)] == β[(i,j)])
        JuMP.@constraint(model, α[(i,j)] <= β[(i,j)])
    end
end

# ╔═╡ 9d6af6e9-435a-43e6-980a-0658a4b449a1
# constraint_isolate_block
begin
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
end

# ╔═╡ 1e1b3303-1508-4acb-8dd0-3cf0c64d0a78
for (i,switch) in ref[:switch]
	f_bus_id = switch["f_bus"]
	t_bus_id = switch["t_bus"]
	f_connections = switch["f_connections"]
	t_connections = switch["t_connections"]
	f_idx = (i, f_bus_id, t_bus_id)

	w_fr = w[f_bus_id]
    w_to = w[f_bus_id]

    f_bus = ref[:bus][f_bus_id]
    t_bus = ref[:bus][t_bus_id]

    f_vmax = f_bus["vmax"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
    t_vmax = t_bus["vmax"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

    vmax = min.(fill(2.0, length(f_bus["vmax"])), f_vmax, t_vmax)

	# constraint_mc_switch_state_open_close
    for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
        JuMP.@constraint(model, w_fr[fc] - w_to[tc] <=  vmax[idx].^2 * (1-z_switch[i]))
        JuMP.@constraint(model, w_fr[fc] - w_to[tc] >= -vmax[idx].^2 * (1-z_switch[i]))
    end

    rating = min.(fill(1.0, length(f_connections)), PMD._calc_branch_power_max_frto(switch, f_bus, t_bus)...)

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

	    psw_sqr_fr = [JuMP.@variable(model, base_name="0_psw_sqr_$(f_idx)[$(c)]") for c in f_connections]
	    qsw_sqr_fr = [JuMP.@variable(model, base_name="0_qsw_sqr_$(f_idx)[$(c)]") for c in f_connections]

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

# ╔═╡ 9b7446d5-0751-4df6-b716-e8d5f85848a8
md"""#### Transformer Constraints

The following constraints model wye and delta connected transformers, including the capability to adjust the tap variables for voltage stability.
"""

# ╔═╡ 0bad7fc4-0a8d-46e7-b126-91b3542fed42
for (i,transformer) in ref[:transformer]
    f_bus = transformer["f_bus"]
    t_bus = transformer["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)
    configuration = transformer["configuration"]
    f_connections = transformer["f_connections"]
    t_connections = transformer["t_connections"]
    tm_set = transformer["tm_set"]
    tm_fixed = transformer["tm_fix"]
    tm_scale = PMD.calculate_tm_scale(transformer, ref[:bus][f_bus], ref[:bus][t_bus])
    pol = transformer["polarity"]

    if configuration == PMD.WYE
		tm = [tm_fixed[idx] ? tm_set[idx] : var(pm, nw, :tap, trans_id)[idx] for (idx,(fc,tc)) in enumerate(zip(f_connections,t_connections))]

	    p_fr = [pt[f_idx][p] for p in f_connections]
	    p_to = [pt[t_idx][p] for p in t_connections]
	    q_fr = [qt[f_idx][p] for p in f_connections]
	    q_to = [qt[t_idx][p] for p in t_connections]

	    w_fr = w[f_bus]
	    w_to = w[t_bus]

	    tmsqr = [
			tm_fixed[i] ? tm[i]^2 : JuMP.@variable(
				model,
				base_name="0_tmsqr_$(trans_id)_$(f_connections[i])",
				start=JuMP.start_value(tm[i])^2,
				lower_bound=JuMP.has_lower_bound(tm[i]) ? JuMP.lower_bound(tm[i])^2 : 0.9^2,
				upper_bound=JuMP.has_upper_bound(tm[i]) ? JuMP.upper_bound(tm[i])^2 : 1.1^2
			) for i in 1:length(tm)
		]

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

	            tmsqr_w_to = JuMP.@variable(model, base_name="0_tmsqr_w_to_$(trans_id)_$(t_bus)_$(tc)")
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

# ╔═╡ 6df404eb-d816-4ae4-ae3f-a39505f79669
md"""### Objective

Below is the objective function used for the block-mld problem, which includes terms for

- minimizing the amount of load shed
- minimizing the number of switches left open
- minimizing the number of switches changing from one state to another
- maximizing the amount of stored energy at the end of the elapsed time
- minimizing the cost of generation

"""

# ╔═╡ 5c04b2c2-e83b-4289-b439-2e016a20678e
begin
	delta_sw_state = JuMP.@variable(
		model,
		[i in keys(ref[:switch_dispatchable])],
		base_name="$(i)_delta_sw_state",
	)

	for (s,switch) in ref[:switch_dispatchable]
		JuMP.@constraint(model, delta_sw_state[s] >=  (switch["state"] - z_switch[s]))
		JuMP.@constraint(model, delta_sw_state[s] >= -(switch["state"] - z_switch[s]))
    end

    total_energy_ub = sum(strg["energy_rating"] for (i,strg) in ref[:storage])
    total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (i, gen) in ref[:gen]])

    total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax

    n_dispatchable_switches = length(keys(ref[:switch_dispatchable]))
	n_dispatchable_switches = n_dispatchable_switches < 1 ? 1 : n_dispatchable_switches

	block_weights = ref[:block_weights]

    JuMP.@objective(model, Min,
            sum( block_weights[i] * (1-z_block[i]) for (i,block) in ref[:blocks])
			+ sum( ref[:switch_scores][l]*(1-z_switch[l]) for l in keys(ref[:switch_dispatchable]) )
            + sum( delta_sw_state[l] for l in keys(ref[:switch_dispatchable])) / n_dispatchable_switches
            + sum( (strg["energy_rating"] - se[i]) for (i,strg) in ref[:storage]) / total_energy_ub
            + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * pg[i][c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in ref[:gen]) / total_energy_ub
    )
end

# ╔═╡ a78fb463-0ffe-41db-a48b-63a4ae9ff3f7
md"""## Model comparison

In this section we compare the models and their solutions, to see if they are equivalent.
"""

# ╔═╡ 52867723-336e-460d-a1a6-a7993778b3e9
md"""### JuMP Model as built automatically by ONM

Here, we build the JuMP model using the built-in ONM tools. Specifically, we use the `instantiate_onm_model` function, to build the block-mld problem `build_block_mld`, using the LinDist3Flow formulation `LPUBFDiagPowerModel`.

We are doing this so that we can compare the automatically built model against the manually built one.
"""

# ╔═╡ d9cd6181-cd1d-48f9-b610-f3b2dea1c640
orig_model = ONM.instantiate_onm_model(eng, PMD.LPUBFDiagPowerModel, ONM.build_block_mld).model

# ╔═╡ bc4e4a20-2584-4706-a4d7-ad0d9de43351
md"""#### Save automatic model to disk for comparison

If it is desired to look at the model in a file, to more directly compare it to another model, change `false` to `true`.
"""

# ╔═╡ 9ffd1f23-f82c-45b5-9a69-9fde7e296cf1
if false
	orig_dest = JuMP.MOI.FileFormats.Model(format = JuMP.MOI.FileFormats.FORMAT_MPS)
	JuMP.MOI.copy_to(orig_dest, pm_orig.model)
	JuMP.MOI.write_to_file(orig_dest, "orig_model.mof.mps")
end

# ╔═╡ 61e70040-9fc4-4681-a25f-d144a857aabd
md"""### Manual Model

Below is a summary of the JuMP model that was built by-hand above.
"""

# ╔═╡ efcd69c1-6ea2-4524-a053-bfb40fb01dda
model

# ╔═╡ 4938609f-ce32-4798-bfc8-c6ca205e1209
md"""#### Save manual model to disk for comparison

If it is desired to look at the model in a file, to more directly compare it to another model, change `false` to `true`.
"""

# ╔═╡ ba60b4e3-fcdc-4efc-994b-1872a8f58703
if false
	new_dest = JuMP.MOI.FileFormats.Model(format = JuMP.MOI.FileFormats.FORMAT_MOF)
	JuMP.MOI.copy_to(new_dest, model)
	JuMP.MOI.write_to_file(new_dest, "new_model.mof.json")
end

# ╔═╡ 8c545f8e-22b3-4f53-a02d-5473bc9e1a3a
md"""### Solve original model
"""

# ╔═╡ cfd8e9d3-1bb0-42a2-920d-5e343609c237
JuMP.set_optimizer(orig_model, solver)

# ╔═╡ 6dd1b166-1a00-4e89-b46f-9621bf35982f
JuMP.optimize!(orig_model)

# ╔═╡ 25970a05-5503-455c-9b56-d0147702371c
md"### Solve Manual Model"

# ╔═╡ b758be56-9ed0-4474-8361-73b3d2de89af
JuMP.set_optimizer(model, solver)

# ╔═╡ 5084a4ed-1638-4d77-91e4-5d77788ce0fe
JuMP.optimize!(model)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
InfrastructureModels = "2030c09a-7f63-5d83-885d-db604e0e9cc0"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
PowerModelsDistribution = "d7431456-977f-11e9-2de3-97ff7677985e"
PowerModelsONM = "25264005-a304-4053-a338-565045d392ac"

[compat]
HiGHS = "~1.5.0"
InfrastructureModels = "~0.7.6"
JuMP = "~1.9.0"
PowerModelsDistribution = "~0.14.7"
PowerModelsONM = "~3.3.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.5"
manifest_format = "2.0"
project_hash = "b37846044adbb6a07e479c5b24209480732b82a7"

[[deps.ASL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6252039f98492252f9e47c312c8ffda0e3b9e78d"
uuid = "ae81ac8f-d209-56e5-92de-9978fef736f9"
version = "0.1.3+0"

[[deps.Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "cc37d689f599e8df4f464b2fa3870ff7db7492ef"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.6.1"

[[deps.ArgParse]]
deps = ["Logging", "TextWrap"]
git-tree-sha1 = "3102bce13da501c9104df33549f511cd25264d7d"
uuid = "c7e460c6-2fb9-53a9-8c5b-16f535851c63"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[deps.ArrayInterface]]
deps = ["Adapt", "LinearAlgebra", "Requires", "SnoopPrecompile", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "a89acc90c551067cd84119ff018619a1a76c6277"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "7.2.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "d9a9701b899b30332bbcb3e1679c41cce81fb0e8"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.3.2"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "SnoopPrecompile", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "c700cce799b51c9045473de751e9319bdd1c6e94"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.9"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c6d890a52d2c4d55d326439580c3b8d0875a77d9"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.7"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "485193efd2176b88e6622a39a246f8c5b600e74e"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.6"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "2e62a725210ce3c3c2e1a3080190e7ca491f18d7"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.7.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[deps.Combinatorics]]
git-tree-sha1 = "08c8b6831dc00bfea825826be0bc8336fc369860"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.0.2"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "7a60c856b9fa189eb34f5f8a6f6b5529b7942957"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.6.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.1+0"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "89a9db8d28102b094992472d333674bd1a83ce2a"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.1"

[[deps.DataAPI]]
git-tree-sha1 = "e8119c1a33d267e16108be441a287a6981ba1630"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.14.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "a4ad7ef19d2cdc2eff57abbbe68032b1cd0bd8f8"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.13.0"

[[deps.Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "49eba9ad9f7ead780bfb7ee319f962c811c6d3b2"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.8"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.EzXML]]
deps = ["Printf", "XML2_jll"]
git-tree-sha1 = "0fa3b52a04a4e210aeb1626def9c90df3ae65268"
uuid = "8f5d6c58-4d21-5cfd-889c-e3ad7ee6a615"
version = "1.1.0"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Requires", "Setfield", "SparseArrays", "StaticArrays"]
git-tree-sha1 = "ed1b56934a2f7a65035976985da71b6a65b4f2cf"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.18.0"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "00e252f4d706b3d55a8863432e742bf5717b498d"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.35"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.Glob]]
git-tree-sha1 = "4df9f7e06108728ebf00a0a11edee4b29a482bb2"
uuid = "c27321d9-0574-5035-807b-f59d2c89b15c"
version = "1.3.0"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "1cf1d7dcb4bc32d7b4a5add4232db3750c27ecb4"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.8.0"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "37e4657cd56b11abe3d10cd4a1ec5fbdb4180263"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.7.4"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "MathOptInterface", "SnoopPrecompile", "SparseArrays"]
git-tree-sha1 = "c4e72223d3c5401cc3a7059e23c6717ba5a08482"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.5.0"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "53aadc2a53ef3ecc4704549b4791dea67657a4bb"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.5.1+0"

[[deps.Hwloc]]
deps = ["Hwloc_jll", "Statistics"]
git-tree-sha1 = "8338d1bec813d12c4c0d443e3bdf5af564fb37ad"
uuid = "0e44f5e4-bd66-52a0-8798-143a42290a1d"
version = "2.2.0"

[[deps.Hwloc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a35518b15f2e63b60c44ee72be5e3a8dbf570e1b"
uuid = "e33a78d0-f292-5ffc-b300-72abe9b543c8"
version = "2.9.0+0"

[[deps.Inflate]]
git-tree-sha1 = "5cd07aab533df5170988219191dfad0519391428"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.3"

[[deps.InfrastructureModels]]
deps = ["JuMP", "Memento"]
git-tree-sha1 = "88da90ad5d8ca541350c156bea2715f3a23836ce"
uuid = "2030c09a-7f63-5d83-885d-db604e0e9cc0"
version = "0.7.6"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "49510dfcb407e572524ba94aeae2fced1f3feb0f"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.8"

[[deps.Ipopt]]
deps = ["Ipopt_jll", "LinearAlgebra", "MathOptInterface", "OpenBLAS32_jll", "SnoopPrecompile"]
git-tree-sha1 = "7690de6bc4eb8d8e3119dc707b5717326c4c0536"
uuid = "b6b21f68-93f8-5de0-b562-5493be1d77c9"
version = "1.2.0"

[[deps.Ipopt_jll]]
deps = ["ASL_jll", "Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "MUMPS_seq_jll", "OpenBLAS32_jll", "Pkg", "libblastrampoline_jll"]
git-tree-sha1 = "563b23f40f1c83f328daa308ce0cdf32b3a72dc4"
uuid = "9cc047cb-c261-5740-88fc-0cf96f7bdcc7"
version = "300.1400.403+1"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JSONSchema]]
deps = ["HTTP", "JSON", "URIs"]
git-tree-sha1 = "8d928db71efdc942f10e751564e6bbea1e600dfe"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "1.0.1"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "Printf", "SnoopPrecompile", "SparseArrays"]
git-tree-sha1 = "611b9f12f02c587d860c813743e6cec6264e94d8"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.9.0"

[[deps.Juniper]]
deps = ["Distributed", "JSON", "LinearAlgebra", "MathOptInterface", "MutableArithmetics", "Random", "Statistics"]
git-tree-sha1 = "a0735f588cb750d89ddcfa2f429a2330b0f440c6"
uuid = "2ddba703-00a4-53a7-87a5-e8b9971dde84"
version = "0.9.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c7cb1f5d892775ba13767a87c7ada0b980ea0a71"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+2"

[[deps.LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "Printf"]
git-tree-sha1 = "7bbea35cec17305fc70a0e5b4641477dc0789d9d"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.2.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "0a1b7c2863e44523180fdb3146534e265a91870b"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.23"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[deps.METIS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "1fd0a97409e418b78c53fac671cf4622efdf0f21"
uuid = "d00139f3-1899-568f-a2f0-47f597d42d70"
version = "5.1.2+0"

[[deps.MUMPS_seq_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "METIS_jll", "OpenBLAS32_jll", "Pkg", "libblastrampoline_jll"]
git-tree-sha1 = "f429d6bbe9ad015a2477077c9e89b978b8c26558"
uuid = "d7ed1dd3-d0ae-5e8e-bfb4-87a502085b8d"
version = "500.500.101+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "SnoopPrecompile", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "f219b62e601c2f2e8adb7b6c48db8a9caf381c82"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.13.1"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[deps.Memento]]
deps = ["Dates", "Distributed", "Requires", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "bb2e8f4d9f400f6e90d57b34860f6abdc51398e5"
uuid = "f28f55f0-a522-5efc-85c2-fe41dfb9b2d9"
version = "1.4.1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "3295d296288ab1a0a2528feb424b854418acff57"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.2.3"

[[deps.NLSolversBase]]
deps = ["DiffResults", "Distributed", "FiniteDiff", "ForwardDiff"]
git-tree-sha1 = "a0b464d183da839699f4c79e7606d9d186ec172c"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "7.8.3"

[[deps.NLsolve]]
deps = ["Distances", "LineSearches", "LinearAlgebra", "NLSolversBase", "Printf", "Reexport"]
git-tree-sha1 = "019f12e9a1a7880459d0173c182e6a99365d7ac1"
uuid = "2774e3e8-f4cf-5e23-947b-6d7e65073b56"
version = "4.5.1"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c6c2ed4b7acd2137b878eb96c68e63b76199d0f"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.17+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "6503b77492fd7fcb9379bf73cd31035670e3c509"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.3.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9ff31d101d987eb9d66bd8b176ac7c277beccd09"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.20+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates", "SnoopPrecompile"]
git-tree-sha1 = "478ac6c952fddd4399e71d4779797c538d0ff2bf"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.5.8"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[deps.PolyhedralRelaxations]]
deps = ["DataStructures", "ForwardDiff", "JuMP", "Logging", "LoggingExtras"]
git-tree-sha1 = "05f2adc696ae9a99be3de99dd8970d00a4dccefe"
uuid = "2e741578-48fa-11ea-2d62-b52c946f73a0"
version = "0.3.5"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.PowerModels]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "NLsolve", "SparseArrays"]
git-tree-sha1 = "951986db4efc4effb162e96d1914de35d876e48c"
uuid = "c36e90e8-916a-50a6-bd94-075b64ef4655"
version = "0.19.8"

[[deps.PowerModelsDistribution]]
deps = ["CSV", "Dates", "FilePaths", "Glob", "InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Logging", "LoggingExtras", "PolyhedralRelaxations", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "fd2a5efc06acb1b449a985c48d4b3d8004a3b371"
uuid = "d7431456-977f-11e9-2de3-97ff7677985e"
version = "0.14.7"

[[deps.PowerModelsONM]]
deps = ["ArgParse", "Combinatorics", "Dates", "Distributed", "EzXML", "Graphs", "HiGHS", "Hwloc", "InfrastructureModels", "Ipopt", "JSON", "JSONSchema", "JuMP", "Juniper", "LinearAlgebra", "Logging", "LoggingExtras", "Pkg", "PolyhedralRelaxations", "PowerModelsDistribution", "PowerModelsProtection", "PowerModelsStability", "Requires", "SHA", "Statistics", "StatsBase", "UUIDs"]
git-tree-sha1 = "07afe97994fe16a853410cddb33bbcb4fb4326a3"
uuid = "25264005-a304-4053-a338-565045d392ac"
version = "3.3.0"

[[deps.PowerModelsProtection]]
deps = ["Graphs", "InfrastructureModels", "JuMP", "LinearAlgebra", "PowerModels", "PowerModelsDistribution", "Printf"]
git-tree-sha1 = "1c029770e1abe7b0970f49fc7791ea5704c4d00e"
uuid = "719c1aef-945b-435a-a240-4c2992e5e0df"
version = "0.5.2"

[[deps.PowerModelsStability]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "PowerModelsDistribution"]
git-tree-sha1 = "758392c148f671473aad374a24ff26db72bc36cf"
uuid = "f9e4c324-c3b6-4bca-9c3d-419775f0bd17"
version = "0.3.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "77d3c4726515dca71f6d80fbb5e251088defe305"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.18"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "a4ada03f999bd01b3a25dcaa30b2d929fe537e00"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.1.0"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "ef28127915f4229c971eb43f3fc075dd3fe91880"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.2.0"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "6aa098ef1012364f2ede6b17bf358c7f1fbe90d4"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.17"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f9af7f195fb13589dd2e2d57fdb401717d2eb1f6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.5.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "1544b926975372da01227b382066ab70e574a3ec"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TextWrap]]
git-tree-sha1 = "9250ef9b01b66667380cf3275b3f7488d0e25faf"
uuid = "b718987f-49a8-5099-9789-dcd902bef87d"
version = "1.0.1"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "94f38103c984f89cf77c402f2a68dbd870f8165f"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.11"

[[deps.URIs]]
git-tree-sha1 = "074f993b0ca030848b897beff716d93aca60f06a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.2"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "93c41695bc1c08c46c5899f4fe06d6ead504bb73"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.10.3+0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─bbe09ba9-63fb-4b33-ae27-eb05cb9fd936
# ╟─bdfca444-f5f0-413f-8a47-8346de453d12
# ╟─3b579de0-8d2a-4e94-8daf-0d3833a90ab4
# ╠═ad36afcf-6a7e-4913-b15a-5f19ba383b27
# ╠═4de82775-e012-44a5-a440-d7f54792d284
# ╟─b41082c7-87f1-42e3-8c20-4d6cddc79375
# ╠═7b252a89-19e4-43ba-b795-24299074753e
# ╟─d7dbea25-f1b1-4823-982b-0d5aa9d6ea26
# ╠═cc2aba3c-a412-4c20-8635-2cdcf369d2c8
# ╟─e66a945e-f437-4ed6-9702-1daf3bccc958
# ╠═88beadb3-e87b-46e4-8aec-826324cd6112
# ╟─588344bb-6f8b-463e-896d-725ceb167cb4
# ╠═8f41758a-5523-487d-9a5b-712ffec668ee
# ╟─b9582cb1-0f92-42ef-88b8-fb7e98ff6c3b
# ╠═6fa5d4f4-997d-4340-bdc5-1b2801815351
# ╟─ebe9dc84-f289-4ae4-bd26-6071106d6a28
# ╠═e096d427-0916-40be-8f05-444e8f37b410
# ╟─e6496923-ee2b-46a0-9d81-624197d3cb02
# ╠═afc66e0a-8aed-4d1a-9cf9-15f537b57b95
# ╟─0590de28-76c6-485a-ae8e-bf76c0c9d924
# ╟─379efc70-7458-41f5-a8d4-dcdf59fc9a6e
# ╠═c19ed861-e91c-44e6-b0be-e4b56629481c
# ╟─4269aa45-2c4c-4be5-8776-d25b39e5fe90
# ╠═962476bf-fa55-484d-b9f6-fc09d1d891ee
# ╟─1480b91d-fcbb-46c1-9a47-c4daa99731a2
# ╠═04eea7b8-ff6c-4650-b01e-31301257ded4
# ╟─05312fc9-b125-42e8-a9bd-7129f63ddc9a
# ╠═91014d35-e30b-4af7-9324-3cde48242342
# ╟─3277219e-589d-47db-9374-e6712a4a40c4
# ╠═ac115a18-ce73-436a-800e-a83b27c6cee7
# ╠═bca9289f-bf4f-4ec2-af5f-373b70b4e614
# ╠═beb258c4-97da-4044-b8d1-abc695e8a910
# ╠═e00d2fdc-a416-4259-b29e-b5608897da9b
# ╠═855a0057-610a-4274-86bb-95ceef674257
# ╟─080a174a-c63b-4284-a06d-1031fda7e3a9
# ╠═3177e943-c635-493a-9be6-c2ade040c447
# ╠═5e0f7d2d-d6f9-40d9-b3a4-4404c2c66950
# ╠═6c8163e3-5a18-4561-a9f4-834e42657f7d
# ╠═9f98ca07-532d-4fc6-a1bd-13a182b0db50
# ╠═7f709599-084b-433f-9b6a-6ded827b69f2
# ╠═b84ba9e4-5ce2-4b10-bb45-eed88c6a4bbe
# ╠═5e538b33-20ae-4520-92ec-efc01494ffcc
# ╠═44b283ee-e28c-473d-922f-8f1b8f982f10
# ╠═e910ae7a-680e-44a5-a35d-cabe2dfa50d0
# ╟─44fe57a1-edce-45c7-9a8b-40857bddc285
# ╠═06523a91-4665-4e31-b6e2-732cbfd0e0e4
# ╠═867253fa-32ee-4ab4-bc42-3f4c2f0e5fa4
# ╠═6e61aac8-5a50-47a7-a150-6557a47e2d3b
# ╠═a675e62f-c55e-4d70-85d8-83b5845cd063
# ╠═732df933-40ca-409c-9d88-bb80ea6d21b0
# ╟─17002ccb-16c2-449c-849a-70f090fea5e6
# ╠═fdb80bf1-8c88-474e-935c-9e7c230b5b72
# ╠═9de1c3d1-fb60-42e2-8d53-111842337458
# ╠═7cf6b40c-f89b-44bc-847d-a06a92d86098
# ╟─9d51b315-b501-4140-af02-b645f04ec7a7
# ╠═dabecbec-8cd0-48f7-8a13-0bdecd45eb85
# ╠═c0764ed0-4b2c-4bf5-98db-9b7349560530
# ╠═733cb346-2d08-4c35-8596-946b31ecc7e9
# ╠═466f22aa-52ff-442f-be00-f4f32e24a173
# ╟─e10f9a86-74f1-4dfb-87c9-fcd920e23c27
# ╠═efc78626-3a50-4c7d-8a7d-ba2b67df57e3
# ╠═e841b4d8-1e8e-4fd9-b805-4ee0c6359df5
# ╠═de4839e1-5ac0-415d-8928-e4a9a358deae
# ╠═1b858a96-f894-4276-90a2-aa9833d9dd37
# ╠═70dec0fa-a87c-4266-819d-a2ad5903d24a
# ╠═463ae91e-5533-46d0-8907-32f9d5ba17cf
# ╠═00aa935b-0f1a-43ae-8437-bde5e34c1fcd
# ╠═cafb8b69-ebc1-49d6-afe5-ff8af54eb222
# ╠═bc2c0bea-621c-45f6-bc72-3d8907a280dc
# ╠═503bdbad-70f8-42d2-977b-af6ba06b2cde
# ╠═e8dfb521-6750-4df6-b4ff-0cabf5989e8f
# ╠═70850ada-165a-4e0d-942a-9dc311add0a6
# ╠═d226e83d-b405-4dd3-9697-471bdbff97a2
# ╠═050f3e9f-62e9-445d-8c95-9f0419c01c0e
# ╟─eb1af86d-a40c-411d-a211-d7a43386bf44
# ╠═ace2c946-7984-4c17-bedb-06dccd6e8a36
# ╠═8386d993-ffcc-4c6a-a91b-247f8c97a2ff
# ╠═b5408b8a-eff4-4d42-9ba7-707a40d92956
# ╠═b7a7e78a-8f0f-4f47-9f37-8ecf3ddc4972
# ╠═86d65cab-d073-4e77-bc0f-3d7e135dcbf8
# ╟─80c50ee0-fb55-4c2c-86dd-434524d1a5e7
# ╠═dc4d7b85-c968-4271-9e44-f80b90e4d6af
# ╠═dfafbbcd-9465-4a78-867b-25703b5157ba
# ╟─cae714ed-ac90-454f-b2ec-e3bb13a71056
# ╟─47f8d8f4-c6e3-4f78-93d3-c5bb4938a754
# ╠═378f45ee-2e0e-428b-962f-fd686bc5d063
# ╟─4bfb96ae-2087-41a8-b9b0-3f4b346992a2
# ╠═b7a30f17-1f3b-497a-ab1c-bc9ce1ac6e56
# ╠═d1136370-9fc2-47c6-a773-d4dc7901db83
# ╟─8e564c5e-8c0e-4001-abaa-bf9575d41089
# ╠═05b0aad1-a41b-4fe7-8b76-70848f71d9d2
# ╟─074845c0-f5ae-4a7c-bf94-3fcade5fdab8
# ╠═8be57ed0-0c7e-40d5-b780-28eb9f9c2490
# ╟─068a66eb-35ef-45ff-8448-75fe67eec38f
# ╠═e32ada08-9f79-47b9-bfef-eaf5f8bbc058
# ╠═d6c7baee-8c8e-4cd9-ba35-06edad733e91
# ╟─5e7470f6-2bb5-49fb-93d7-1b8c8e402526
# ╠═8c44ebe8-a2e9-4480-b1d8-b3c19350c029
# ╟─20d08693-413b-4a52-9f54-d8f25b492b50
# ╠═f2d2375d-2ca2-4e97-87f2-5adbf250d152
# ╟─978048ae-170a-4b83-8dee-1715350e75cc
# ╠═23d0f743-d7be-400a-9972-4337ae1bffff
# ╠═a63763bf-1f87-400e-b4cd-b112c9a0cd64
# ╠═9d6af6e9-435a-43e6-980a-0658a4b449a1
# ╠═1e1b3303-1508-4acb-8dd0-3cf0c64d0a78
# ╟─9b7446d5-0751-4df6-b716-e8d5f85848a8
# ╠═0bad7fc4-0a8d-46e7-b126-91b3542fed42
# ╟─6df404eb-d816-4ae4-ae3f-a39505f79669
# ╠═5c04b2c2-e83b-4289-b439-2e016a20678e
# ╟─a78fb463-0ffe-41db-a48b-63a4ae9ff3f7
# ╟─52867723-336e-460d-a1a6-a7993778b3e9
# ╠═d9cd6181-cd1d-48f9-b610-f3b2dea1c640
# ╟─bc4e4a20-2584-4706-a4d7-ad0d9de43351
# ╠═9ffd1f23-f82c-45b5-9a69-9fde7e296cf1
# ╟─61e70040-9fc4-4681-a25f-d144a857aabd
# ╠═efcd69c1-6ea2-4524-a053-bfb40fb01dda
# ╟─4938609f-ce32-4798-bfc8-c6ca205e1209
# ╠═ba60b4e3-fcdc-4efc-994b-1872a8f58703
# ╟─8c545f8e-22b3-4f53-a02d-5473bc9e1a3a
# ╠═cfd8e9d3-1bb0-42a2-920d-5e343609c237
# ╠═6dd1b166-1a00-4e89-b46f-9621bf35982f
# ╟─25970a05-5503-455c-9b56-d0147702371c
# ╠═b758be56-9ed0-4474-8361-73b3d2de89af
# ╠═5084a4ed-1638-4d77-91e4-5d77788ce0fe
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
