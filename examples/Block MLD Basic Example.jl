### A Pluto.jl notebook ###
# v0.19.5

using Markdown
using InteractiveUtils

# ╔═╡ da854ce8-dba5-11ec-125f-8d121de9288f
using Pkg

# ╔═╡ e8dd4b8e-bc68-408e-a6f6-32fec5f74942
begin
	Pkg.activate(;temp=true)
	Pkg.add(Pkg.PackageSpec(;name="PowerModelsONM", rev="v3.0-rc"))
	Pkg.add(
		[
			"PowerModelsDistribution",
			"InfrastructureModels",
			"JuMP",
			"HiGHS",
		]
	)
end

# ╔═╡ 9c81254c-38ba-4b67-bf00-f067039d1706
md"""# Block MLD Basic Example

This notebook provides a basic example of how to apply only the block-mld problem to a single time step and solve the JuMP model.

This example "decomposes" the problem, removing a lot of the automatic user-friendly steps so that users may understand how to access the JuMP model directly.

"""

# ╔═╡ 605b5a16-8d40-42e0-a9d7-d33640fdee00
md"""## TEMP: Install necessary packages

This section can be removed after release
"""

# ╔═╡ 79be1100-92fa-4701-8617-8e316b4b49d2
md"## Import necessary packages"

# ╔═╡ aeac5a27-d7f9-451f-9a76-0486d03da582
begin
	import PowerModelsONM as ONM
	import PowerModelsDistribution as PMD
	import InfrastructureModels as IM
	import JuMP
	import HiGHS
end

# ╔═╡ 9d5af5c9-7a5f-409b-a1fb-3f158af37153
md"We will need the path to PowerModelsONM so that we can use the included data models"

# ╔═╡ a5abfeb8-8f11-433b-a0d5-e0f33f0b6cb6
onm_path = joinpath(dirname(pathof(ONM)), "..")

# ╔═╡ 4a36eb92-35c7-4d73-9ed0-6a3ed0e756c5
md"""## Parse data model using ONM functions

This function auto-creates the multinetwork data structure, but for this example we will ignore it.
"""

# ╔═╡ ecfdb2aa-98fe-4c13-afd7-7fb4ecd198df
eng, _ = ONM.parse_network("$onm_path/test/data/ieee13_feeder.dss")

# ╔═╡ 5ead58cb-f5cb-4a7d-91ea-4158e5005cdd
md"At a minimum, the MLD problems require finite voltage bounds, so we apply the basic $$\pm$$0.1 p.u. "

# ╔═╡ 3aa1c98d-e888-4595-b13f-44a3f01e9ac2
PMD.apply_voltage_bounds!(eng; vm_lb=0.9, vm_ub=1.1)

# ╔═╡ 971dd7d9-9789-4d20-86b2-19778cacc0c9
md"Normally, the functions in PowerModelsONM and PowerModelsDistribution will automatically handle data conversion between the ENGINEERING and MATHEMATICAL data models, but to make it explicit we are converting it here to illustrate the different transformations"

# ╔═╡ 0c07c4c1-e76c-4dc3-8bb2-1ccad2a092ea
math = ONM.transform_data_model(eng)

# ╔═╡ 73493d29-f13e-4993-a033-b09cf7ec4040
md"## Build the JuMP model"

# ╔═╡ 7b395675-ed36-4587-b314-ce247d706ffe
pm = ONM.instantiate_onm_model(math, PMD.LPUBFDiagPowerModel, ONM.build_block_mld)

# ╔═╡ ef3f8b62-0e09-45fd-908b-065a4447b67d
md"## Instantiate a solver and attach it"

# ╔═╡ 7bcc1e19-f982-44cb-bbc0-df72eca756eb
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

# ╔═╡ 4c16cc15-c71e-46d0-a30e-841cffeee032
JuMP.set_optimizer(pm.model, solver)

# ╔═╡ fe6e5d8e-627f-45c5-8667-9870ec330c1d
md"## Optimize JuMP Model"

# ╔═╡ bef50174-bdf5-4fbd-9ef9-7a581add3ed2
JuMP.optimize!(pm.model)

# ╔═╡ e9f3622a-e410-420c-87d7-d17c3146a62f
md"## Extract the result from the JuMP Model"

# ╔═╡ fbe9f92c-19f0-46a0-ae50-a0e50fc2efd6
result = IM.build_result(pm, JuMP.solve_time(pm.model); solution_processors=ONM._default_solution_processors)

# ╔═╡ cd502839-64fd-4ac6-9fd6-c5798fa317d0
md"## Convert the solution to the ENGINEERING model"

# ╔═╡ 97346e89-e1c2-4190-82de-57959179f13f
sol_eng = PMD.transform_solution(result["solution"], math)

# ╔═╡ Cell order:
# ╟─9c81254c-38ba-4b67-bf00-f067039d1706
# ╟─605b5a16-8d40-42e0-a9d7-d33640fdee00
# ╠═da854ce8-dba5-11ec-125f-8d121de9288f
# ╠═e8dd4b8e-bc68-408e-a6f6-32fec5f74942
# ╟─79be1100-92fa-4701-8617-8e316b4b49d2
# ╠═aeac5a27-d7f9-451f-9a76-0486d03da582
# ╟─9d5af5c9-7a5f-409b-a1fb-3f158af37153
# ╠═a5abfeb8-8f11-433b-a0d5-e0f33f0b6cb6
# ╟─4a36eb92-35c7-4d73-9ed0-6a3ed0e756c5
# ╠═ecfdb2aa-98fe-4c13-afd7-7fb4ecd198df
# ╟─5ead58cb-f5cb-4a7d-91ea-4158e5005cdd
# ╠═3aa1c98d-e888-4595-b13f-44a3f01e9ac2
# ╟─971dd7d9-9789-4d20-86b2-19778cacc0c9
# ╠═0c07c4c1-e76c-4dc3-8bb2-1ccad2a092ea
# ╟─73493d29-f13e-4993-a033-b09cf7ec4040
# ╠═7b395675-ed36-4587-b314-ce247d706ffe
# ╟─ef3f8b62-0e09-45fd-908b-065a4447b67d
# ╠═7bcc1e19-f982-44cb-bbc0-df72eca756eb
# ╠═4c16cc15-c71e-46d0-a30e-841cffeee032
# ╟─fe6e5d8e-627f-45c5-8667-9870ec330c1d
# ╠═bef50174-bdf5-4fbd-9ef9-7a581add3ed2
# ╟─e9f3622a-e410-420c-87d7-d17c3146a62f
# ╠═fbe9f92c-19f0-46a0-ae50-a0e50fc2efd6
# ╟─cd502839-64fd-4ac6-9fd6-c5798fa317d0
# ╠═97346e89-e1c2-4190-82de-57959179f13f
