### A Pluto.jl notebook ###
# v0.19.9

using Markdown
using InteractiveUtils

# ╔═╡ a3dd604d-b63e-4956-a6cb-16749e5ba17b
# ╠═╡ show_logs = false
begin
	using Pkg
	Pkg.activate(;temp=true)
	Pkg.add(Pkg.PackageSpec(; name="PowerModelsONM", version="3.0.0"))
end

# ╔═╡ d8124cac-293a-4a2d-ba70-bc75ec624712
using PowerModelsONM

# ╔═╡ ef2b5e56-d2d1-11eb-0686-51cf4afc8846
md"""
# Introduction to PowerModelsONM

This is an introduction to using PowerModelsONM, a Julia/JuMP library for optimizing the operations of networked microgrids.

To use PowerModelsONM, you will need to install the package via `Pkg.add()`.

In this Pluto notebook, we would normally install via the built-in Pluto notebook package manager:
"""

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

# ╔═╡ Cell order:
# ╟─ef2b5e56-d2d1-11eb-0686-51cf4afc8846
# ╠═a3dd604d-b63e-4956-a6cb-16749e5ba17b
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
