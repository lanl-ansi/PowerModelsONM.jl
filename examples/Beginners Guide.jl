### A Pluto.jl notebook ###
# v0.19.22

using Markdown
using InteractiveUtils

# ╔═╡ d8124cac-293a-4a2d-ba70-bc75ec624712
using PowerModelsONM

# ╔═╡ ef2b5e56-d2d1-11eb-0686-51cf4afc8846
md"""
# Introduction to PowerModelsONM

This is an introduction to using PowerModelsONM, a Julia/JuMP library for optimizing the operations of networked microgrids.

To use PowerModelsONM, you will need to install the package via `Pkg.add()`.

In this Pluto notebook, we would normally install via the built-in Pluto notebook package manager:
"""

# ╔═╡ a3dd604d-b63e-4956-a6cb-16749e5ba17b
# ╠═╡ show_logs = false
# begin
	# using Pkg
	# Pkg.activate(;temp=true)
	# Pkg.add(Pkg.PackageSpec(; name="PowerModelsONM", version="3.0.0"))
# end

# ╔═╡ ae76a6e5-f114-476f-8c53-36e369586d0c
md"""
Throughout this tutorial, we will utilize data that is included in the PowerModelsONM package for unit testing, so we setup a variable for the data directory `test/data`
"""

# ╔═╡ 0641c9b7-4cb2-48a7-985a-fea34175a635
test_dir = joinpath(dirname(pathof(PowerModelsONM)), "../test/data")

# ╔═╡ d7d6bf22-36ce-4765-b7d9-a4fd7ca41a47
example_dir = joinpath(dirname(pathof(PowerModelsONM)), "../examples/data")

# ╔═╡ f2deeb76-33c5-4d85-a032-60773e0ebf04
ieee13_network_ex = joinpath(example_dir, "network.ieee13.dss")

# ╔═╡ fe5b1f7c-f7d9-4451-9942-3e86fea61a35
ieee13_settings_ex = joinpath(example_dir, "settings.ieee13.json")

# ╔═╡ 0b2651db-d938-4737-b63a-7679a5750d9c
ieee13_events_ex = joinpath(example_dir, "events.ieee13.json")

# ╔═╡ d01b5080-eb75-4a7c-b026-fe1d3bfe996c
ieee13_faults_test = joinpath(test_dir, "ieee13_faults.json")

# ╔═╡ 0ece8e62-7ce7-4a74-b403-0477b23600c6
ieee13_inverters_test = joinpath(test_dir, "ieee13_inverters.json")

# ╔═╡ 626cc32c-99b1-4383-a346-16538af31963
md"""
## How to use PowerModelsONM

PowerModelsONM is designed to have a straightforward workflow for optimizing the operation and recovering of distribution feeders under contingencies.

In particular, the workflow consists of sequential steps of

- data processing and preparation, which includes inputs such as
  - the base network (OpenDSS format)
  - timeseries data (contained in the DSS files)
  - events data, which contains the contingencies (json, see `models/events.v1.json`)
  - settings data, which contains supplemental information about the network model not supported in DSS (json, see `models/settings.v1.json`)
  - inverters data, which contains information about inverters for stability analysis (json, see `models/inverters.v1.json` and [PowerModelsStability documentation](https://github.com/lanl-ansi/PowerModelsStability.jl)
  - faults data, which contains pre-built faults over which to iterate during fault studies (json, see `models/faults.v1.json` and [PowerModelsProtection documentation](https://github.com/lanl-ansi/PowerModelsProtection.jl)
- optimal switching (osw) / maximal load delivery (mld) problem
- optimal dispatch (OPF) problem
- statistical analysis and outputs, which includes information about
  - device action timeline, such as the switch configurations at every timestep and which loads have been shed by the algorithm,
  - microgrid statistics, such as min, mean, max voltages, storage state of charge, analysis of load served, analysis of generation sources, etc.
  - Powerflow outputs, which contains dispatch setpoints and bus voltage magnitudes
  - Small signal stability results
  - Fault analysis results
"""

# ╔═╡ 51e6236d-f6eb-4dcf-9b03-1f9b04848ce7
begin
	open(joinpath(dirname(pathof(PowerModelsONM)), "../docs/src/assets/onm_process_flow_v4.png"), "r") do io
		HTML(read(io, String))
	end
end

# ╔═╡ 583c7e8f-4e2b-4a91-8edf-681e55b55bfd
md"""### Inputs

The first and foremost piece of data you will need is the network definition files in OpenDSS format. For more information on what is currently supported see [PowerModelsDistribution](https://github.com/lanl-ansi/PowerModelsDistribution.jl).

Using `parse_network` will return a `network`, which is a "multinetwork" representation of the timeseries contained in the DSS specification, and `base_network`, which is the topological reality of the system, without the expansion into a multinetwork.
"""

# ╔═╡ 4891479c-9eb5-494e-ad1f-9bd52a171c57
base_network, network = parse_network(ieee13_network_ex)

# ╔═╡ e1f1b7cf-d8ad-432d-ac98-95860e1ec65d
md"""
multinetworks are data structures which contains a full network definition under `"nw"` with the time varying values written directly to that copy.

Each timestep, or "subnetwork", will be indexed by the string representation of an integer, in order.

For example, the timestep named `"2"`, which corresponds in this case to timestep `2.0` (which you can find under `"mn_lookup"`), can be explored like this:
"""

# ╔═╡ f7636969-d29b-415e-8fe4-d725b6fa97d0
network["nw"]["2"]

# ╔═╡ c6dbd392-2269-4572-8b07-ff7f233b8c89
md"""
### Settings

There are many things that cannot be easily represented in the DSS specification, specifically relating to optimization bounds, which is not the use case for OpenDSS. To support specifying these extra types of settings, we have created a settings JSON Schema.

In this example, we load some settings that have been found to fit the loaded data model well.
"""

# ╔═╡ e686d58d-50ea-4789-93e7-5f3c41ee53ad
settings = parse_settings(ieee13_settings_ex)

# ╔═╡ 70b6075c-b548-44d2-b301-9621023e06e0
md"""
However, using the `build_settings` helper function it is straightforward to generate these settings files with some reasonable defaults, which can be edited further.
"""

# ╔═╡ cf4b988d-0774-4e5f-8ded-4db1ca869066
settings_from_build_settings = build_settings(
	base_network;
	vm_lb_pu=0.8,
	vm_ub_pu=1.2,
	vad_deg=5.0,
	max_switch_actions=1
)

# ╔═╡ 27fd182f-3cdc-4568-b6f5-cae1b5e2e1a2
md"""
Settings can be easily applied via `apply_settings`, which will return a copy of the network data structure.

It should be noted that settings are applied to the `base_network`, i.e., not the multinetwork data structure.
"""

# ╔═╡ b4bec7ca-ee1b-42e2-aea2-86e8b5c3dc46
base_network_settings = apply_settings(base_network, settings)

# ╔═╡ 01690a4a-33da-4207-86d9-c55d962f07ce
md"""
It is necessary to rebuild the multinetwork data structure after applying settings.
"""

# ╔═╡ 8abcb814-472a-4bf9-a02c-b04a6c4a1084
network_settings = make_multinetwork(base_network_settings)

# ╔═╡ 1b10ab40-5b24-4370-984d-cce1de0f95f5
md"""
### Contingencies (Events)

To apply a contingency to a network, we need to define a contingency using the events schema.

In this example, we load a contingency where in timestep 1 a switching action isolates a microgrid, and ensures that another switch always stays closed (because it is a fuse).
"""

# ╔═╡ e941118d-5b63-4886-bacd-82291f4c01c4
raw_events = parse_events(ieee13_events_ex)

# ╔═╡ 353e797c-6155-4d7b-bb79-440d7b8f8ae2
md"""
These events are "raw events", in that they have not yet been parsed into the native network data format. These raw events are a vector, in order, that defines a sequence of events.

To parse the events into the native format, we need to have the network data
"""

# ╔═╡ 05454fe0-2368-4c67-ad82-bec852c56b85
events = parse_events(raw_events, network)

# ╔═╡ 8134f0d4-7719-42e0-8f72-6967115d6bb6
md"""
As you can see, this structure now looks much more like the native network definition, allowing you to see how we parse events into actual actions in the timeseries representation.

To apply these events to a network, we can use `apply_events`, which will return a copy of the original network data structure.
"""

# ╔═╡ b0f23e3a-3859-467f-a8d1-5bdcf05132f8
network_settings_events = apply_events(network_settings, events)

# ╔═╡ 72736da6-917e-4cc1-8aff-0923d4c637e9
md"""
Like with settings, we can use a useful helper function `build_events` to create a simple events file with some reasonable defults.
"""

# ╔═╡ d20f4d1c-c8bc-41bd-8f9a-2ee7ee931697
events_from_build_events = build_events(base_network)

# ╔═╡ 438b71e6-aca2-49b4-ab15-e747d335f331
md"""
## Analysis

In this next section we will cover the different optimization problems and analyses that we can perform with PowerModelsONM.

### Optimization Solvers

In order to actually solve any of the optimization problems within PowerModelsONM, you will need to initialize some optimization solvers.

PowerModelsONM has several solvers built-in in case you don't want to create your own, and can be created with `build_solver_instances`, which will ouput a Dictionary with

- `"nlp_solver"`: Ipopt
- `"mip_solver"`: HiGHS
- `"lp_solver"`: HiGHS
- `"minlp_solver"`: Juniper
- `"misocp_solver"`: Juniper

"""

# ╔═╡ a8ce787f-6a2c-4c97-940c-8331fbda1f3c
md"To create some solvers, it is useful to have some solver settings. The settings structure contains some reasonable defaults."

# ╔═╡ 87959af2-47b2-484c-8396-98f87a4abc2b
settings["solvers"]

# ╔═╡ 7197dba8-4fb3-460b-8fe3-a0efc59a2d98
md"In this case, the settings defaulted to using the Gurobi solver, which we should correct for this notebook"

# ╔═╡ ad417629-caf6-4efd-8861-d7a40c58b53f
settings["solvers"]["useGurobi"] = false

# ╔═╡ a566fb16-6368-4edb-846c-0dc1917e15da
md"Now, we build some solver instances with these settings"

# ╔═╡ c733df10-79b1-4b72-8c74-fe1fabfead44
solvers = build_solver_instances(; solver_options=settings["solvers"])

# ╔═╡ 8ce619a2-fe39-4b77-beda-bde92878cb86
md"""
### Optimal Switching (osw / mld)

Now that we have a network with contingencies and settings, we want to solve a optimal switching / mld problem.

First, it should be noted that because loads are most typically not individually controllable in distribution feeders, with a few notable exceptions, loads must largely be shed by isolating a load block with switching actions. A load block is defined as a block of buses which can be fully isolated from the grid by opening one or more _operable_ switches.

To accomodate this reality, we can extended PowerModelsDistribution by adding the ability to assign load status variables to multiple loads (_i.e._, by block), and adding constraints that isolate blocks of load that are desired to be shed to maintain operability of the rest of the grid.

Second, the optimal switching problem currently uses the LinDist3Flow model (`PowerModelsDistribution.LPUBFDiagModel`), which is a quadratic approximation, due to the presence of mixed integers.

Finally, the optimial switching problem currently solves sequentially, rather than globally over the entire multinetwork, which means switch configurations and storage energies are manually updated after each timestep is solved.

To run the optimal switching problem, use `optimize_switches`
"""

# ╔═╡ 484fc544-157e-4fda-a97b-3c791063b1b8
optimal_switching_results = optimize_switches(network_settings_events, solvers["mip_solver"]; algorithm="rolling-horizon")


# ╔═╡ e5a55ef5-e3df-40a3-b0bf-cb6b4a1fec2d
md"""
The result is a dictionary, indexed by the subnetwork indexes discussed before, with the results of each timestep, where the actual solution is contained under `"solution"`.
"""

# ╔═╡ 53c406c3-5312-41b6-a774-55d7406ce4d0
optimal_switching_results["1"]["solution"]

# ╔═╡ cfe3ba9f-7bbb-4d1e-a0da-b0e262017779
md"""
### Optimal Dispatch (opf)

Because the optimal switching is performed with a) a linear approximation, and b) sequentially, it is advisable to run a separate optimal dispatch solve on the resulting multinetwork

First though, we will want to propagate the switch configuration to the multinetwork data structure using `apply_switch_solutions!`.
"""

# ╔═╡ 9733ae2e-5d24-4c7c-ad95-2a7f88fbe249
network_settings_events_osw = apply_switch_solutions(network_settings_events, optimal_switching_results)

# ╔═╡ be5a2e83-51a8-4676-a6e0-8aac6640e5a4
begin
	for (n,nw) in network_settings_events_osw["nw"]
		for (_,bus) in nw["bus"]
			delete!(bus, "vm_lb")
			delete!(bus, "vm_ub")
		end
	end

	md"""
Then we can run `optimize_dispatch` on the resulting network, in this case using the ACR Unbalanced model from PowerModelsDistribution and our NLP solver.
"""
end

# ╔═╡ bda997b3-e790-4af4-94c8-f8ebf3f34140
optimal_dispatch_results = optimize_dispatch(network, PowerModelsONM.PMD.ACRUPowerModel, solvers["nlp_solver"])

# ╔═╡ 53cf78c6-e5b4-4888-96d1-c14c35e66be8
md"""
### Fault Analysis (fs)

Fault analysis is brought to PowerModelsONM courtesy of PowerModelsProtection.

It should be noted that if no faults are pre-defined, as they are in this example, faults will be automatically generated iteratively and can end up taking a significant time to solve depending on the size of the network.

Here we use an example faults file from our unit tests.
"""

# ╔═╡ 3a3da57c-4783-4e79-b19a-a50633419eb1
faults = parse_faults(ieee13_faults_test)

# ╔═╡ 8ea1a7a5-b515-494b-86b8-584c8243d7f1
md"""
To run a fault study we simply use `run_fault_studies`
"""

# ╔═╡ 13adb9f5-ded7-4674-b789-60bdca8bccf0
fault_studies_results = run_fault_studies(network_settings_events_osw, solvers["nlp_solver"]; faults=faults)

# ╔═╡ 3a8bab18-14e7-4c61-a304-390ae1e5d535
md"""
### Small signal stability Analysis

Small signal stability analysis is brought to PowerModelsONM courtesy of PowerModelsStability

Currently PowerModelsStability is quite limited and may not work on more complex networks, but here we demonstrate the basic usage of this feature

For stability analysis, we need to define some inverter properties, which we have included in the unit test data
"""

# ╔═╡ 8fb0fb4d-3b6c-4e76-907f-7d03d7ac0601
inverters = parse_inverters(ieee13_inverters_test)

# ╔═╡ 9bbf0909-218b-4ba8-bd49-93d839fd1c35
md"""
To run a stability analysis we simply use `run_stability_analysis`
"""

# ╔═╡ b87dbbf3-2326-48fb-8d45-9a407ca2ed82
stability_results = run_stability_analysis(network_settings_events_osw, inverters, solvers["nlp_solver"])

# ╔═╡ 74e7866b-fdf5-49af-aeda-e02f67047b74
md"""
## Statistics and Outputs

In this section we will cover the different built-in statistical analysis functions included in PowerModelsONM.

The various results dictionaries can all be used in different ways, and you should not feel limited to the analyses included in PowerModelsONM.

### Action Statistics

First up are statistics about the actions taken during the MLD optimization. For this we have two primary functions, `get_timestep_device_actions`, which will get a full list of the switch configurations and loads shed at each timestep
"""

# ╔═╡ 35f58253-d264-4da2-aa09-d48f306984b1
get_timestep_device_actions(network_settings_events_osw, optimal_switching_results)

# ╔═╡ a9664398-0ca3-40d7-92b7-5b11796a5c1b
md"""
and `get_timestep_switch_changes`, which is a list of switches whose `state` has changed since the last timestep.
"""

# ╔═╡ 21a22427-88c2-49d1-9d9c-a93be0cb1ebf
get_timestep_switch_changes(network_settings_events, optimal_switching_results)

# ╔═╡ 9b999688-6f02-49e6-8835-15d97a38095f
md"""
`get_timestep_switch_changes` is especially useful for seeing at a glance if the actions at each timestep make sense, particular for larger networks where there are a lot of dispatchable switches.

### Dispatch Statistics

The next category of statistics is related to the optimal dispatch problem. Again, there are two primary analysis functions, `get_timestep_voltage_statistics`, which will get the voltages minimum, maximum, and mean for each timestep, in per-unit representation,
"""

# ╔═╡ a9e2b5d0-d5a1-47c6-b692-00a468be245d
get_timestep_voltage_statistics(optimal_dispatch_results["solution"], network_settings_events_osw)

# ╔═╡ da1a0fed-b9f7-47ef-b633-e2b76aa05225
md"""
and `get_timestep_dispatch`, which will collect the dispatch information about the generation assets, and all voltages at buses in SI units
"""

# ╔═╡ d73f0289-7c23-4a74-8601-cbd7e61caff7
get_timestep_dispatch(optimal_dispatch_results["solution"], network_settings_events)

# ╔═╡ eff4b469-eb16-4126-91cf-a6b4b6c9ed18
md"""
### Microgrid Statistics

This next category of statistics is related to the microgrids, and has three primary analysis functions. First, `get_timestep_load_served` collects information about what percentage of load is supported by the grid vs microgrids
"""

# ╔═╡ bc0ab54b-9bfd-46f4-a424-235ff15dbc1f
get_timestep_load_served(optimal_dispatch_results["solution"], network_settings_events_osw)

# ╔═╡ 8c1ce17c-3ff8-4292-929f-12bf80838427
md"""
Next is `get_timestep_generator_profiles`, which collects information about the sources of generation, separating out grid mix, solar, storage, and deisel.
"""

# ╔═╡ d1eb32f6-e632-4ffa-b71d-7ae600b17a47
get_timestep_generator_profiles(optimal_dispatch_results["solution"])

# ╔═╡ 3fc33951-1627-44e6-baec-fb04d6b28b24
md"""
Finally is `get_timestep_storage_soc`, which returns how much energy storage charge is remaining in the network at each timestep (which is none in this case, because there is no storage in this network).
"""

# ╔═╡ 7277f686-c0ca-4304-bffc-aee8bef1eba7
get_timestep_storage_soc(optimal_dispatch_results["solution"], network_settings_events_osw)

# ╔═╡ 7cf3e0fd-355a-4b80-b6ab-4903c318a71f
md"""
### Fault Statistics

In the fault analysis category, there is only one function for analysis, `get_timestep_fault_currents`, which will collect

- information about the fault
- fault currents and voltages at the protection devices

"""

# ╔═╡ b1d28290-61eb-482d-9279-6f8f616c3cf5
get_timestep_fault_currents(fault_studies_results, faults, network_settings_events_osw)

# ╔═╡ c22200b8-d57e-4960-8714-c51102cbccd7
md"""
### Stability Statistics

Finally is stability statistics, which again only has one function, `get_timestep_stability`, which returns whether a timestep returned as stable at that timestep
"""

# ╔═╡ 1d30b557-afbe-4527-84d7-d742f2abdb93
get_timestep_stability(stability_results)

# ╔═╡ a2f8c882-6fed-48f9-a554-c69e354ba0c0
md"""
## Run the entire workflow via `entrypoint`

When you are not interested in recreating the workflow step-by-step, or you want to use a compiled binary, docker image, or simply use Julia from the commandline, the `entrypoint` function will do all of the work for you.

Even if you use it from the Julia REPL, it can be very beneficial, because it will output every step in a single data structure.
"""

# ╔═╡ 753c3b4c-861b-4787-b304-b4d3b1b84be0
args = Dict{String,Any}(
	"network" => ieee13_network_ex,
	"events" => ieee13_events_ex,
	"settings" => ieee13_settings_ex,
	"inverters" => ieee13_inverters_test,
	"faults" => ieee13_faults_test,
)

# ╔═╡ 5c6e9ace-de55-4b45-84f8-876e7c04f664
md"Normally, we would simply call `entrypoint(args)` at this point, but to ensure that this problem solves in reasonable time, we will adjust some settings first, which will require some additional steps."

# ╔═╡ 1a68e9eb-1e37-4049-9480-74cb185c7531
md"First, we load the data using `prepare_data!`, which will do all the necessary parsing of the network, settings, and events files"

# ╔═╡ 24ea3ffc-ec31-4b18-a8f6-b5ede42ff33c
prepare_data!(args)

# ╔═╡ b8a81954-8115-4e88-9d19-4ea3abec15ed
md"Then we can use `set_settings!` to adjust some options in the `args` data structure"

# ╔═╡ 550ebcd5-9b7c-435e-9450-4eb5a94aac03
set_settings!(
	args,
	Dict(
		("solvers","useGurobi") => false,
		("solvers","HiGHS","time_limit") => 300.0,
		("solvers","Ipopt","max_cpu_time") => 300.0,
		("options","problem","operations-algorithm") => "rolling-horizon",
		("options","problem","dispatch-formulation") => "lindistflow",
		("options","constraints","disable-microgrid-networking") => true,
		("options","problem","skip") => ["stability","faults"]
	)
)

# ╔═╡ 8b192733-2e26-4e9c-a4d9-45e8fbf3571d
md"Finally, we can execute the `entrypoint` function, which will perform all parts of the ONM workflow"

# ╔═╡ 32073778-e62a-46ee-9797-3988be5c8fba
entrypoint_results = entrypoint(args)

# ╔═╡ 6b1d3355-11ff-4aec-b6b2-b0fe0183dca6
md"""
As you can see, every step in the workflow is represented in the results, which has the benefit of aiding in debugging.

In particular, all of the statistics and analysis can be found under `"output_data"`
"""

# ╔═╡ d418b2bf-a01d-43bf-8cd0-ca53be431a9f
entrypoint_results["output_data"]

# ╔═╡ 5b3c882d-c7c0-4acc-9d05-fafde347e4ff
md"""
## Troubleshooting and Debugging

If you are having trouble getting your network to solve, the first place to look will be the optimization bounds. While DSS is an excellent format for defining networks, including their topology and time series data, it is not intended to define bounds for optimization problems, which is what we are attempting to solve here.

In many cases, the default bounds from DSS are either much too restrictive, such as in the case of line limits, or completely non-existant, such as in the case of bus voltage bounds or line angle different bounds.
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
PowerModelsONM = "25264005-a304-4053-a338-565045d392ac"

[compat]
PowerModelsONM = "~3.3.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.5"
manifest_format = "2.0"
project_hash = "82960f1fea6f8599cf098b5c5b722c9464c46ab0"

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
# ╟─ef2b5e56-d2d1-11eb-0686-51cf4afc8846
# ╠═d8124cac-293a-4a2d-ba70-bc75ec624712
# ╟─ae76a6e5-f114-476f-8c53-36e369586d0c
# ╠═0641c9b7-4cb2-48a7-985a-fea34175a635
# ╠═d7d6bf22-36ce-4765-b7d9-a4fd7ca41a47
# ╠═f2deeb76-33c5-4d85-a032-60773e0ebf04
# ╠═fe5b1f7c-f7d9-4451-9942-3e86fea61a35
# ╠═0b2651db-d938-4737-b63a-7679a5750d9c
# ╠═d01b5080-eb75-4a7c-b026-fe1d3bfe996c
# ╠═0ece8e62-7ce7-4a74-b403-0477b23600c6
# ╠═626cc32c-99b1-4383-a346-16538af31963
# ╠═51e6236d-f6eb-4dcf-9b03-1f9b04848ce7
# ╠═583c7e8f-4e2b-4a91-8edf-681e55b55bfd
# ╠═4891479c-9eb5-494e-ad1f-9bd52a171c57
# ╟─e1f1b7cf-d8ad-432d-ac98-95860e1ec65d
# ╠═f7636969-d29b-415e-8fe4-d725b6fa97d0
# ╟─c6dbd392-2269-4572-8b07-ff7f233b8c89
# ╠═e686d58d-50ea-4789-93e7-5f3c41ee53ad
# ╟─70b6075c-b548-44d2-b301-9621023e06e0
# ╠═cf4b988d-0774-4e5f-8ded-4db1ca869066
# ╟─27fd182f-3cdc-4568-b6f5-cae1b5e2e1a2
# ╠═b4bec7ca-ee1b-42e2-aea2-86e8b5c3dc46
# ╟─01690a4a-33da-4207-86d9-c55d962f07ce
# ╠═8abcb814-472a-4bf9-a02c-b04a6c4a1084
# ╟─1b10ab40-5b24-4370-984d-cce1de0f95f5
# ╠═e941118d-5b63-4886-bacd-82291f4c01c4
# ╟─353e797c-6155-4d7b-bb79-440d7b8f8ae2
# ╠═05454fe0-2368-4c67-ad82-bec852c56b85
# ╟─8134f0d4-7719-42e0-8f72-6967115d6bb6
# ╠═b0f23e3a-3859-467f-a8d1-5bdcf05132f8
# ╟─72736da6-917e-4cc1-8aff-0923d4c637e9
# ╠═d20f4d1c-c8bc-41bd-8f9a-2ee7ee931697
# ╟─438b71e6-aca2-49b4-ab15-e747d335f331
# ╟─a8ce787f-6a2c-4c97-940c-8331fbda1f3c
# ╠═87959af2-47b2-484c-8396-98f87a4abc2b
# ╟─7197dba8-4fb3-460b-8fe3-a0efc59a2d98
# ╠═ad417629-caf6-4efd-8861-d7a40c58b53f
# ╟─a566fb16-6368-4edb-846c-0dc1917e15da
# ╠═c733df10-79b1-4b72-8c74-fe1fabfead44
# ╟─8ce619a2-fe39-4b77-beda-bde92878cb86
# ╠═484fc544-157e-4fda-a97b-3c791063b1b8
# ╟─e5a55ef5-e3df-40a3-b0bf-cb6b4a1fec2d
# ╠═53c406c3-5312-41b6-a774-55d7406ce4d0
# ╟─cfe3ba9f-7bbb-4d1e-a0da-b0e262017779
# ╠═9733ae2e-5d24-4c7c-ad95-2a7f88fbe249
# ╟─be5a2e83-51a8-4676-a6e0-8aac6640e5a4
# ╠═bda997b3-e790-4af4-94c8-f8ebf3f34140
# ╟─53cf78c6-e5b4-4888-96d1-c14c35e66be8
# ╠═3a3da57c-4783-4e79-b19a-a50633419eb1
# ╟─8ea1a7a5-b515-494b-86b8-584c8243d7f1
# ╠═13adb9f5-ded7-4674-b789-60bdca8bccf0
# ╟─3a8bab18-14e7-4c61-a304-390ae1e5d535
# ╠═8fb0fb4d-3b6c-4e76-907f-7d03d7ac0601
# ╟─9bbf0909-218b-4ba8-bd49-93d839fd1c35
# ╠═b87dbbf3-2326-48fb-8d45-9a407ca2ed82
# ╟─74e7866b-fdf5-49af-aeda-e02f67047b74
# ╠═35f58253-d264-4da2-aa09-d48f306984b1
# ╟─a9664398-0ca3-40d7-92b7-5b11796a5c1b
# ╠═21a22427-88c2-49d1-9d9c-a93be0cb1ebf
# ╟─9b999688-6f02-49e6-8835-15d97a38095f
# ╠═a9e2b5d0-d5a1-47c6-b692-00a468be245d
# ╟─da1a0fed-b9f7-47ef-b633-e2b76aa05225
# ╠═d73f0289-7c23-4a74-8601-cbd7e61caff7
# ╟─eff4b469-eb16-4126-91cf-a6b4b6c9ed18
# ╠═bc0ab54b-9bfd-46f4-a424-235ff15dbc1f
# ╟─8c1ce17c-3ff8-4292-929f-12bf80838427
# ╠═d1eb32f6-e632-4ffa-b71d-7ae600b17a47
# ╟─3fc33951-1627-44e6-baec-fb04d6b28b24
# ╠═7277f686-c0ca-4304-bffc-aee8bef1eba7
# ╟─7cf3e0fd-355a-4b80-b6ab-4903c318a71f
# ╠═b1d28290-61eb-482d-9279-6f8f616c3cf5
# ╟─c22200b8-d57e-4960-8714-c51102cbccd7
# ╠═1d30b557-afbe-4527-84d7-d742f2abdb93
# ╟─a2f8c882-6fed-48f9-a554-c69e354ba0c0
# ╠═753c3b4c-861b-4787-b304-b4d3b1b84be0
# ╟─5c6e9ace-de55-4b45-84f8-876e7c04f664
# ╟─1a68e9eb-1e37-4049-9480-74cb185c7531
# ╠═24ea3ffc-ec31-4b18-a8f6-b5ede42ff33c
# ╟─b8a81954-8115-4e88-9d19-4ea3abec15ed
# ╠═550ebcd5-9b7c-435e-9450-4eb5a94aac03
# ╠═8b192733-2e26-4e9c-a4d9-45e8fbf3571d
# ╠═32073778-e62a-46ee-9797-3988be5c8fba
# ╟─6b1d3355-11ff-4aec-b6b2-b0fe0183dca6
# ╠═d418b2bf-a01d-43bf-8cd0-ca53be431a9f
# ╟─5b3c882d-c7c0-4acc-9d05-fafde347e4ff
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
