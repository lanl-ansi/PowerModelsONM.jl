### A Pluto.jl notebook ###
# v0.19.22

using Markdown
using InteractiveUtils

# ╔═╡ 784b4bba-c289-11ed-33e0-79401cc7afb6
# ╠═╡ show_logs = false
begin
	using Pkg
	Pkg.activate(tempdir())
	
	Pkg.develop(;path="..")
	Pkg.add("HiGHS")
	
	using PowerModelsONM
	import HiGHS
end

# ╔═╡ 026f8c13-8036-4b37-8941-3dc0cd8126b4
md"# Configure Environment"

# ╔═╡ 3ecf53c8-ec80-4db2-9ea8-91b51ec1296c
md"# Setup data path"

# ╔═╡ 41da7641-9c41-423d-bef7-082eb74264de
onm_data_path = joinpath(dirname(pathof(PowerModelsONM)), "../examples/data")

# ╔═╡ 87b05d1a-cb3e-4397-9976-3a6442f99728
md"# Load settings"

# ╔═╡ 4fe0a632-25dc-4eaf-89c3-cb6161f81f24
# ╠═╡ show_logs = false
settings = parse_settings(joinpath(onm_data_path, "settings.ieee13mod.json"))

# ╔═╡ 2ef3ad30-78a9-4839-8364-8ff7775bcb81
md"# Setup MIP Solver"

# ╔═╡ 57c11919-f328-46e2-bfb0-44427d75147c
begin
	solver = optimizer_with_attributes(HiGHS.Optimizer, settings["solvers"]["HiGHS"]...)
end

# ╔═╡ 9004814e-5eef-4ab1-a9eb-e4ca480a7554
md"# Load Data"

# ╔═╡ cd950be6-22ff-429e-bec4-7ebd7fd4f118
begin
	eng = parse_file(joinpath(onm_data_path, "network.ieee13mod.dss"))
	eng = apply_settings(eng, settings)
	eng["time_elapsed"] = 1.0
	eng["switch_close_actions_ub"] = Inf

	eng
end

# ╔═╡ 98504c3d-157b-4add-9550-39e4082d5e92
md"# Solve block MLD problem with no contingencies"

# ╔═╡ 18a2f0a9-56e1-4540-9adc-2188a7961037
# ╠═╡ show_logs = false
r = solve_block_mld(eng, LPUBFDiagPowerModel, solver)

# ╔═╡ 9e291b38-0670-49fc-9d6d-41290c1cc561
md"## Switch states results"

# ╔═╡ aaf1afc7-8dcd-4dd2-b38c-7a3ab385e50e
Dict(i => obj["state"] for (i,obj) in r["solution"]["switch"])

# ╔═╡ 20d0822f-6ec6-448f-be70-9a0a4e5a19c4
md"# Solve block MLD Problem with disabled substation"

# ╔═╡ c3481183-39a5-4ac5-ae3a-0cf5b8e367c7
begin
	eng_isolated = deepcopy(eng)
	eng_isolated["switch"]["cb_101"]["state"] = OPEN
	eng_isolated["switch"]["cb_101"]["dispatchable"] = NO

	eng_isolated
end

# ╔═╡ cecfa268-9ae5-4a40-87c2-49b2022113d5
# ╠═╡ show_logs = false
r_isolated = solve_block_mld(eng_isolated, LPUBFDiagPowerModel, solver)

# ╔═╡ ace66ab3-2d8a-4eeb-b749-abdbb0773650
md"## Switch state results"

# ╔═╡ 859d7748-88d7-4e09-9c26-397f5e668dd4
Dict(i => obj["state"] for (i,obj) in r_isolated["solution"]["switch"])

# ╔═╡ 8b688e4a-7aa9-4203-81e3-ea54c6ba64c3
md"## Load shed results"

# ╔═╡ 5c700af1-b96f-48bf-87e1-f391e7cb7472
Dict(i => obj["status"] for (i,obj) in r_isolated["solution"]["load"])

# ╔═╡ 18ef5664-01ce-4013-b7e1-07ba06f86a5f
md"# Robust partitioning with uncertainty"

# ╔═╡ c36adc4b-9f6f-4fe3-b486-7827fb041de2
md"## Generate contingencies"

# ╔═╡ 0a9e64ec-c53c-44dd-b485-396b56167597
contingencies = generate_n_minus_contingencies(eng, 6)

# ╔═╡ 33d453a2-ec3f-4439-b9e6-5f416bbc4bdb
md"## Generate load scenarios"

# ╔═╡ 7ae25ebd-c176-45a4-b830-46b33ed3ac1c
# ╠═╡ show_logs = false
begin
	N = 5      # number of scenarios
	ΔL = 0.1   # load variability around base value
	load_scenarios = generate_load_scenarios(eng, N, ΔL)
end

# ╔═╡ 17b73634-4f7a-4258-aec6-965f31bb22ff
md"## Generate robust partitions for load scenarios"

# ╔═╡ bf5242c8-68e8-465c-a3be-5e8d3d31a509
# ╠═╡ show_logs = false
results = generate_load_robust_partitions(eng, contingencies, load_scenarios, LPUBFDiagPowerModel, solver)


# ╔═╡ 439ddec3-f731-419a-b6e4-47ad547d0776
md"## Update partition ranking for contingencies with uncertainty"

# ╔═╡ 4e269559-ceb2-4362-b33c-fcbde0d3e700
_, robust_partitions_uncertainty = generate_ranked_robust_partitions_with_uncertainty(eng, results);

# ╔═╡ b9568c6f-ddeb-4074-bf12-116546e056ac
robust_partitions_uncertainty

# ╔═╡ Cell order:
# ╟─026f8c13-8036-4b37-8941-3dc0cd8126b4
# ╠═784b4bba-c289-11ed-33e0-79401cc7afb6
# ╟─3ecf53c8-ec80-4db2-9ea8-91b51ec1296c
# ╠═41da7641-9c41-423d-bef7-082eb74264de
# ╟─87b05d1a-cb3e-4397-9976-3a6442f99728
# ╠═4fe0a632-25dc-4eaf-89c3-cb6161f81f24
# ╟─2ef3ad30-78a9-4839-8364-8ff7775bcb81
# ╠═57c11919-f328-46e2-bfb0-44427d75147c
# ╟─9004814e-5eef-4ab1-a9eb-e4ca480a7554
# ╠═cd950be6-22ff-429e-bec4-7ebd7fd4f118
# ╟─98504c3d-157b-4add-9550-39e4082d5e92
# ╠═18a2f0a9-56e1-4540-9adc-2188a7961037
# ╟─9e291b38-0670-49fc-9d6d-41290c1cc561
# ╠═aaf1afc7-8dcd-4dd2-b38c-7a3ab385e50e
# ╟─20d0822f-6ec6-448f-be70-9a0a4e5a19c4
# ╠═c3481183-39a5-4ac5-ae3a-0cf5b8e367c7
# ╠═cecfa268-9ae5-4a40-87c2-49b2022113d5
# ╟─ace66ab3-2d8a-4eeb-b749-abdbb0773650
# ╠═859d7748-88d7-4e09-9c26-397f5e668dd4
# ╟─8b688e4a-7aa9-4203-81e3-ea54c6ba64c3
# ╠═5c700af1-b96f-48bf-87e1-f391e7cb7472
# ╟─18ef5664-01ce-4013-b7e1-07ba06f86a5f
# ╟─c36adc4b-9f6f-4fe3-b486-7827fb041de2
# ╠═0a9e64ec-c53c-44dd-b485-396b56167597
# ╟─33d453a2-ec3f-4439-b9e6-5f416bbc4bdb
# ╠═7ae25ebd-c176-45a4-b830-46b33ed3ac1c
# ╠═17b73634-4f7a-4258-aec6-965f31bb22ff
# ╠═bf5242c8-68e8-465c-a3be-5e8d3d31a509
# ╟─439ddec3-f731-419a-b6e4-47ad547d0776
# ╠═4e269559-ceb2-4362-b33c-fcbde0d3e700
# ╠═b9568c6f-ddeb-4074-bf12-116546e056ac
