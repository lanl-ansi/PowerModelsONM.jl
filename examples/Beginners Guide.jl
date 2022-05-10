### A Pluto.jl notebook ###
# v0.19.0

using Markdown
using InteractiveUtils

# ╔═╡ d8124cac-293a-4a2d-ba70-bc75ec624712
using PowerModelsONM


# ╔═╡ ef2b5e56-d2d1-11eb-0686-51cf4afc8846
md"""
# Introduction to PowerModelsONM

This is an introduction to using PowerModelsONM, a Julia/JuMP library for optimizing the operations of networked microgrids.

To use PowerModelsONM, you will need to install the package via `Pkg.add()`.

In this Pluto notebook, we will install via the built-in Pluto notebook package manager:
"""

# ╔═╡ ae76a6e5-f114-476f-8c53-36e369586d0c
md"""
Throughout this tutorial, we will utilize data that is included in the PowerModelsONM package for unit testing, so we setup a variable for the data directory `test/data`
"""

# ╔═╡ 0641c9b7-4cb2-48a7-985a-fea34175a635
data_dir = joinpath(dirname(pathof(PowerModelsONM)), "..", "test", "data")


# ╔═╡ 626cc32c-99b1-4383-a346-16538af31963
begin

setup_logging!(Dict{String,Any}("verbose"=>true))

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

### Inputs

The first and foremost piece of data you will need is the network definition files in OpenDSS format. For more information on what is currently supported see [PowerModelsDistribution](https://github.com/lanl-ansi/PowerModelsDistribution.jl).

Using `parse_network` will return a `network`, which is a "multinetwork" representation of the timeseries contained in the DSS specification, and `base_network`, which is the topological reality of the system, without the expansion into a multinetwork.
"""
end

# ╔═╡ 4891479c-9eb5-494e-ad1f-9bd52a171c57
base_network, network = parse_network(joinpath(data_dir, "ieee13_feeder.dss"))


# ╔═╡ e1f1b7cf-d8ad-432d-ac98-95860e1ec65d
md"""
multinetworks are data structures which contains a full network definition under `"nw"` with the time varying values written directly to that copy.

Each timestep, or "subnetwork", will be indexed by the string representation of an integer, in order.

For example, the timestep named `"2"`, which corresponds in this case to timestep `2.0` (which you can find under `"mn_lookup"`), can be explored like this:
"""

# ╔═╡ f7636969-d29b-415e-8fe4-d725b6fa97d0
network["nw"]["2"]


# ╔═╡ 1b10ab40-5b24-4370-984d-cce1de0f95f5
md"""
### Contingencies (Events)

To apply a contingency to a network, we need to define a contingency using the events schema.

In this example, we load a contingency where in timestep 1 a switching action isolates a microgrid, and ensures that another switch always stays closed (because it is a fuse).
"""

# ╔═╡ e941118d-5b63-4886-bacd-82291f4c01c4
raw_events = parse_events(joinpath(data_dir, "ieee13_events.json"))


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
network_events = apply_events(network, events)


# ╔═╡ c6dbd392-2269-4572-8b07-ff7f233b8c89
md"""
### Settings

There are many things that cannot be easily represented in the DSS specification, specifically relating to optimization bounds, which is not the use case for OpenDSS. To support specifying these extra types of settings, we have created a settings JSON Schema.

In this example, we load some settings that set the maximum allowed switching actions at each timestep (`"switch_close_actions_ub"`), how much time has elapsed during each timestep (`"time_elapsed"`, in hours), and a cold-load pickup factor (`"clpu_factor"`) for each load.
"""

# ╔═╡ e686d58d-50ea-4789-93e7-5f3c41ee53ad
settings = parse_settings(joinpath(data_dir, "ieee13_settings.json"))


# ╔═╡ 27fd182f-3cdc-4568-b6f5-cae1b5e2e1a2
md"""
Like with events, settings can be easily applied via `apply_settings`, which will return a copy of the network data structure.
"""

# ╔═╡ 6c421881-9df0-42c3-bf15-a1d4665bcb84
begin
	dep_runtime_args = Dict{String,Any}(
		"voltage-lower-bound" => 0.8,
		"voltage-upper-bound" => 1.2,
		"voltage-angle-difference" => 5,
		"max-switch-actions" => 1
	)
	settings_w_dep_args = deepcopy(settings)
	PowerModelsONM._convert_deprecated_runtime_args!(dep_runtime_args, settings_w_dep_args, base_network, length(network_events["nw"]))

	network_events_settings = apply_settings(network_events, settings_w_dep_args)
end


# ╔═╡ 70b6075c-b548-44d2-b301-9621023e06e0
md"""
It should be noted that in the above block we did a slight trick using some deprecated runtime arguments to quickly create a better settings. In the future, additional helper functions will be added to assist users in applying some of these common settings
"""

# ╔═╡ 438b71e6-aca2-49b4-ab15-e747d335f331
md"""
## Analysis

In this next section we will cover the different optimization problems and analyses that we can perform with PowerModelsONM.

### Optimization Solvers

In order to actually solve any of the optimization problems within PowerModelsONM, you will need to initialize some optimization solvers.

PowerModelsONM has several solvers built-in in case you don't want to create your own, and can be created with `build_solver_instances`, which will ouput a Dictionary with

- `"nlp_solver"`: Ipopt
- `"mip_solver"`: Cbc
- `"minlp_solver"`: Alpine with Ipopt and Cbc
- `"misocp_solver"`: Juniper with Ipopt and Cbc

"""

# ╔═╡ c733df10-79b1-4b72-8c74-fe1fabfead44
solvers = build_solver_instances()


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
optimal_switching_results = optimize_switches(network_events_settings, solvers["mip_solver"]; algorithm="iterative")


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
network_events_settings_osw = apply_switch_solutions(network_events_settings, optimal_switching_results)


# ╔═╡ be5a2e83-51a8-4676-a6e0-8aac6640e5a4
begin
	for (n,nw) in network_events_settings_osw["nw"]
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
faults = parse_faults(joinpath(data_dir, "ieee13_faults.json"))


# ╔═╡ 8ea1a7a5-b515-494b-86b8-584c8243d7f1
md"""
To run a fault study we simply use `run_fault_studies`
"""

# ╔═╡ 13adb9f5-ded7-4674-b789-60bdca8bccf0
fault_studies_results = run_fault_studies(network_events_settings_osw, solvers["nlp_solver"]; faults=faults)


# ╔═╡ 3a8bab18-14e7-4c61-a304-390ae1e5d535
md"""
### Small signal stability Analysis

Small signal stability analysis is brought to PowerModelsONM courtesy of PowerModelsStability

Currently PowerModelsStability is quite limited and may not work on more complex networks, but here we demonstrate the basic usage of this feature

For stability analysis, we need to define some inverter properties, which we have included in the unit test data
"""

# ╔═╡ 8fb0fb4d-3b6c-4e76-907f-7d03d7ac0601
inverters = parse_inverters(joinpath(data_dir, "ieee13_inverters.json"))


# ╔═╡ 9bbf0909-218b-4ba8-bd49-93d839fd1c35
md"""
To run a stability analysis we simply use `run_stability_analysis`
"""

# ╔═╡ b87dbbf3-2326-48fb-8d45-9a407ca2ed82
stability_results = run_stability_analysis(network_events_settings_osw, inverters, solvers["nlp_solver"])


# ╔═╡ 74e7866b-fdf5-49af-aeda-e02f67047b74
md"""
## Statistics and Outputs

In this section we will cover the different built-in statistical analysis functions included in PowerModelsONM.

The various results dictionaries can all be used in different ways, and you should not feel limited to the analyses included in PowerModelsONM.

### Action Statistics

First up are statistics about the actions taken during the MLD optimization. For this we have two primary functions, `get_timestep_device_actions`, which will get a full list of the switch configurations and loads shed at each timestep
"""

# ╔═╡ 35f58253-d264-4da2-aa09-d48f306984b1
get_timestep_device_actions(network_events_settings_osw, optimal_switching_results)


# ╔═╡ a9664398-0ca3-40d7-92b7-5b11796a5c1b
md"""
and `get_timestep_switch_changes`, which is a list of switches whose `state` has changed since the last timestep.
"""

# ╔═╡ 21a22427-88c2-49d1-9d9c-a93be0cb1ebf
get_timestep_switch_changes(network_events_settings_osw)


# ╔═╡ 9b999688-6f02-49e6-8835-15d97a38095f
md"""
`get_timestep_switch_changes` is especially useful for seeing at a glance if the actions at each timestep make sense, particular for larger networks where there are a lot of dispatchable switches.

### Dispatch Statistics

The next category of statistics is related to the optimal dispatch problem. Again, there are two primary analysis functions, `get_timestep_voltage_statistics`, which will get the voltages minimum, maximum, and mean for each timestep, in per-unit representation,
"""

# ╔═╡ a9e2b5d0-d5a1-47c6-b692-00a468be245d
get_timestep_voltage_statistics(optimal_dispatch_results["solution"], network_events_settings_osw)


# ╔═╡ da1a0fed-b9f7-47ef-b633-e2b76aa05225
md"""
and `get_timestep_dispatch`, which will collect the dispatch information about the generation assets, and all voltages at buses in SI units
"""

# ╔═╡ d73f0289-7c23-4a74-8601-cbd7e61caff7
get_timestep_dispatch(optimal_dispatch_results["solution"], network_events_settings)


# ╔═╡ eff4b469-eb16-4126-91cf-a6b4b6c9ed18
md"""
### Microgrid Statistics

This next category of statistics is related to the microgrids, and has three primary analysis functions. First, `get_timestep_load_served` collects information about what percentage of load is supported by the grid vs microgrids
"""

# ╔═╡ bc0ab54b-9bfd-46f4-a424-235ff15dbc1f
get_timestep_load_served(optimal_dispatch_results["solution"], network_events_settings_osw)


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
get_timestep_storage_soc(optimal_dispatch_results["solution"], network_events_settings_osw)


# ╔═╡ 7cf3e0fd-355a-4b80-b6ab-4903c318a71f
md"""
### Fault Statistics

In the fault analysis category, there is only one function for analysis, `get_timestep_fault_currents`, which will collect

- information about the fault
- fault currents and voltages at the protection devices

"""

# ╔═╡ b1d28290-61eb-482d-9279-6f8f616c3cf5
get_timestep_fault_currents(fault_studies_results, faults, network_events_settings_osw)


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
	"network" => joinpath(data_dir, "ieee13_feeder.dss"),
	"events" => joinpath(data_dir, "ieee13_events.json"),
	"settings" => joinpath(data_dir, "ieee13_settings.json"),
	"inverters" => joinpath(data_dir, "ieee13_inverters.json"),
	"faults" => joinpath(data_dir, "ieee13_faults.json"),
	"opt-switch-algorithm" => "iterative",
	"opt-switch-solver" => "mip_solver",
	"voltage-lower-bound" => 0.8,
	"voltage-upper-bound" => 1.2,
	"voltage-angle-difference" => 5,
	"max-switch-actions" => 1,
)


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
PowerModelsONM = "~2.1.1"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.2"
manifest_format = "2.0"

[[deps.ASL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6252039f98492252f9e47c312c8ffda0e3b9e78d"
uuid = "ae81ac8f-d209-56e5-92de-9978fef736f9"
version = "0.1.3+0"

[[deps.ArgParse]]
deps = ["Logging", "TextWrap"]
git-tree-sha1 = "3102bce13da501c9104df33549f511cd25264d7d"
uuid = "c7e460c6-2fb9-53a9-8c5b-16f535851c63"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[deps.ArrayInterface]]
deps = ["Compat", "IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "c933ce606f6535a7c7b98e1d86d5d1014f730596"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "5.0.7"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "4c10eee4af024676200bc7752e536f858c6b8f93"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.3.1"

[[deps.BinaryProvider]]
deps = ["Libdl", "Logging", "SHA"]
git-tree-sha1 = "ecdec412a9abc8db54c0efc5548c64dfce072058"
uuid = "b99e7846-7c00-51b0-8f62-c81ae34c0232"
version = "0.5.10"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CEnum]]
git-tree-sha1 = "215a9aa4a1f23fbd05b92769fdd62559488d70e9"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.1"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings"]
git-tree-sha1 = "873fb188a4b9d76549b81465b1f75c82aaf59238"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.4"

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.Cbc]]
deps = ["BinaryProvider", "CEnum", "Cbc_jll", "Libdl", "MathOptInterface", "SparseArrays"]
git-tree-sha1 = "6656166f484075dd146c9f452b1428116eaf76d4"
uuid = "9961bab8-2fa3-5c5a-9d89-47fab24efd76"
version = "0.9.1"

[[deps.Cbc_jll]]
deps = ["ASL_jll", "Artifacts", "Cgl_jll", "Clp_jll", "CoinUtils_jll", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS32_jll", "Osi_jll", "Pkg"]
git-tree-sha1 = "a3c5986d7713bce4260d9826deead060a17c8e2d"
uuid = "38041ee0-ae04-5750-a4d2-bb4d0d83d27d"
version = "200.1000.501+0"

[[deps.Cgl_jll]]
deps = ["Artifacts", "Clp_jll", "CoinUtils_jll", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Osi_jll", "Pkg"]
git-tree-sha1 = "11eb7b7688925e9751b5d7a187aaa4291eae2664"
uuid = "3830e938-1dd0-5f3e-8b8e-b3ee43226782"
version = "0.6000.300+0"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "9950387274246d08af38f6eef8cb5480862a435f"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.14.0"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "bf98fa45a0a4cee295de98d4c1462be26345b9a1"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.2"

[[deps.Clp_jll]]
deps = ["Artifacts", "CoinUtils_jll", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "METIS_jll", "MUMPS_seq_jll", "OpenBLAS32_jll", "Osi_jll", "Pkg"]
git-tree-sha1 = "b1031dcfbb44553194c9e650feb5ab65e372504f"
uuid = "06985876-5285-5a41-9fcb-8948a742cc53"
version = "100.1700.601+0"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "2e62a725210ce3c3c2e1a3080190e7ca491f18d7"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.7.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.CoinUtils_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS32_jll", "Pkg"]
git-tree-sha1 = "44173e61256f32918c6c132fc41f772bab1fb6d1"
uuid = "be027038-0da8-5614-b30d-e42594cb92df"
version = "200.1100.400+0"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "96b0bc6c52df76506efc8a441c6cf1adcb1babc4"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.42.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "3daef5523dd2e769dad2365274f760ff5f282c7d"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.11"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.DiffResults]]
deps = ["StaticArrays"]
git-tree-sha1 = "c18e98cba888c6c25d1c3b048e4b3380ca956805"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.0.3"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "dd933c4ef7b4c270aacd4eb88fa64c147492acf0"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.10.0"

[[deps.Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "3258d0659f812acde79e8a74b11f17ac06d0ca04"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.7"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[deps.Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "129b104185df66e408edd6625d480b7f9e9823a0"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.18"

[[deps.FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Requires", "SparseArrays", "StaticArrays"]
git-tree-sha1 = "56956d1e4c1221000b7781104c58c34019792951"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.11.0"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "1bd6fc0c344fc0cbee1f42f8d2e7ec8253dda2d2"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.25"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.Glob]]
git-tree-sha1 = "4df9f7e06108728ebf00a0a11edee4b29a482bb2"
uuid = "c27321d9-0574-5035-807b-f59d2c89b15c"
version = "1.3.0"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "92243c07e786ea3458532e199eb3feee0e7e08eb"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.4.1"

[[deps.HTTP]]
deps = ["Base64", "Dates", "IniFile", "Logging", "MbedTLS", "NetworkOptions", "Sockets", "URIs"]
git-tree-sha1 = "0fa77022fe4b511826b39c894c90daf5fce3334a"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "0.9.17"

[[deps.Hwloc]]
deps = ["Hwloc_jll"]
git-tree-sha1 = "92d99146066c5c6888d5a3abc871e6a214388b91"
uuid = "0e44f5e4-bd66-52a0-8798-143a42290a1d"
version = "2.0.0"

[[deps.Hwloc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "303d70c961317c4c20fafaf5dbe0e6d610c38542"
uuid = "e33a78d0-f292-5ffc-b300-72abe9b543c8"
version = "2.7.1+0"

[[deps.IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[deps.Inflate]]
git-tree-sha1 = "f5fc07d4e706b84f72d54eedcc1c13d92fb0871c"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.2"

[[deps.InfrastructureModels]]
deps = ["JuMP", "Memento"]
git-tree-sha1 = "0c9ec48199cb90a6d1b5c6bdc0f9a15ce8a108b2"
uuid = "2030c09a-7f63-5d83-885d-db604e0e9cc0"
version = "0.7.4"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "61feba885fac3a407465726d0c330b3055df897f"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.1.2"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "91b5dcf362c5add98049e6c29ee756910b03051d"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.3"

[[deps.Ipopt]]
deps = ["BinaryProvider", "Ipopt_jll", "Libdl", "MathOptInterface"]
git-tree-sha1 = "68ba332ff458f3c1f40182016ff9b1bda276fa9e"
uuid = "b6b21f68-93f8-5de0-b562-5493be1d77c9"
version = "0.9.1"

[[deps.Ipopt_jll]]
deps = ["ASL_jll", "Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "MUMPS_seq_jll", "OpenBLAS32_jll", "Pkg"]
git-tree-sha1 = "e3e202237d93f18856b6ff1016166b0f172a49a8"
uuid = "9cc047cb-c261-5740-88fc-0cf96f7bdcc7"
version = "300.1400.400+0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

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
git-tree-sha1 = "2f49f7f86762a0fbbeef84912265a1ae61c4ef80"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "0.3.4"

[[deps.JuMP]]
deps = ["Calculus", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MathOptInterface", "MutableArithmetics", "NaNMath", "OrderedCollections", "Printf", "Random", "SparseArrays", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "fe0f87cc077fc6a23c21e469318993caf2947d10"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "0.22.3"

[[deps.Juniper]]
deps = ["Distributed", "JSON", "LinearAlgebra", "MathOptInterface", "MutableArithmetics", "Random", "Statistics"]
git-tree-sha1 = "6516abbfe736cbe5f4a43c5240c50249e11e4951"
uuid = "2ddba703-00a4-53a7-87a5-e8b9971dde84"
version = "0.8.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "Printf"]
git-tree-sha1 = "f27132e551e959b3667d8c93eae90973225032dd"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.1.1"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "58f25e56b706f95125dcb796f39e1fb01d913a71"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.10"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "dfeda1c1130990428720de0024d4516b1902ce98"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.7"

[[deps.METIS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "1d31872bb9c5e7ec1f618e8c4a56c8b0d9bddc7e"
uuid = "d00139f3-1899-568f-a2f0-47f597d42d70"
version = "5.1.1+0"

[[deps.MUMPS_seq_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "METIS_jll", "OpenBLAS32_jll", "Pkg"]
git-tree-sha1 = "29de2841fa5aefe615dea179fcde48bb87b58f57"
uuid = "d7ed1dd3-d0ae-5e8e-bfb4-87a502085b8d"
version = "5.4.1+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "JSON", "LinearAlgebra", "MutableArithmetics", "OrderedCollections", "Printf", "SparseArrays", "Test", "Unicode"]
git-tree-sha1 = "e8c9653877adcf8f3e7382985e535bb37b083598"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "0.10.9"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "Random", "Sockets"]
git-tree-sha1 = "1c38e51c3d08ef2278062ebceade0e46cefc96fe"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.0.3"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Memento]]
deps = ["Dates", "Distributed", "Requires", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "9b0b0dbf419fbda7b383dc12d108621d26eeb89f"
uuid = "f28f55f0-a522-5efc-85c2-fe41dfb9b2d9"
version = "1.3.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "842b5ccd156e432f369b204bb704fd4020e383ac"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "0.3.3"

[[deps.NLSolversBase]]
deps = ["DiffResults", "Distributed", "FiniteDiff", "ForwardDiff"]
git-tree-sha1 = "50310f934e55e5ca3912fb941dec199b49ca9b68"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "7.8.2"

[[deps.NLsolve]]
deps = ["Distances", "LineSearches", "LinearAlgebra", "NLSolversBase", "Printf", "Reexport"]
git-tree-sha1 = "019f12e9a1a7880459d0173c182e6a99365d7ac1"
uuid = "2774e3e8-f4cf-5e23-947b-6d7e65073b56"
version = "4.5.1"

[[deps.NaNMath]]
git-tree-sha1 = "b086b7ea07f8e38cf122f5016af580881ac914fe"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "0.3.7"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c6c2ed4b7acd2137b878eb96c68e63b76199d0f"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.17+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.Osi_jll]]
deps = ["Artifacts", "CoinUtils_jll", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS32_jll", "Pkg"]
git-tree-sha1 = "28e0ddebd069f605ab1988ab396f239a3ac9b561"
uuid = "7da25872-d9ce-5375-a4d3-7a845f58efdd"
version = "0.10800.600+0"

[[deps.PackageCompiler]]
deps = ["Libdl", "Pkg", "UUIDs"]
git-tree-sha1 = "85554feaaf12a784873077837397282bb894a625"
uuid = "9b87118b-4619-50d2-8e1e-99f35a4d4d9d"
version = "1.2.8"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "621f4f3b4977325b9128d5fae7a8b4829a0c2222"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.2.4"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PolyhedralRelaxations]]
deps = ["DataStructures", "ForwardDiff", "JuMP", "Logging", "LoggingExtras"]
git-tree-sha1 = "fc2d9132d1c7df35ae7ac00afedf6524288fd98d"
uuid = "2e741578-48fa-11ea-2d62-b52c946f73a0"
version = "0.3.4"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "28ef6c7ce353f0b35d0df0d5930e0d072c1f5b9b"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.1"

[[deps.PowerModels]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "NLsolve", "SparseArrays"]
git-tree-sha1 = "c680b66275025a7f3265ee356c95a9b644483150"
uuid = "c36e90e8-916a-50a6-bd94-075b64ef4655"
version = "0.19.5"

[[deps.PowerModelsDistribution]]
deps = ["CSV", "Dates", "FilePaths", "Glob", "InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Logging", "LoggingExtras", "PolyhedralRelaxations", "Statistics"]
git-tree-sha1 = "3d895c1ab35dd8f7eebaf4426352071463f23528"
uuid = "d7431456-977f-11e9-2de3-97ff7677985e"
version = "0.14.3"

[[deps.PowerModelsONM]]
deps = ["ArgParse", "Cbc", "Dates", "Distributed", "Graphs", "Hwloc", "InfrastructureModels", "Ipopt", "JSON", "JSONSchema", "JuMP", "Juniper", "LinearAlgebra", "Logging", "LoggingExtras", "PackageCompiler", "Pkg", "PolyhedralRelaxations", "PowerModelsDistribution", "PowerModelsProtection", "PowerModelsStability", "ProgressMeter", "Requires", "Statistics"]
git-tree-sha1 = "349f5bad362ead58e33402808eac23c822f1b1a9"
uuid = "25264005-a304-4053-a338-565045d392ac"
version = "2.1.1"

[[deps.PowerModelsProtection]]
deps = ["Graphs", "InfrastructureModels", "JuMP", "LinearAlgebra", "PowerModels", "PowerModelsDistribution", "Printf"]
git-tree-sha1 = "efa7aa12ff0f8cab4cf3ae274430a1c83d977412"
uuid = "719c1aef-945b-435a-a240-4c2992e5e0df"
version = "0.5.1"

[[deps.PowerModelsStability]]
deps = ["InfrastructureModels", "JSON", "JuMP", "LinearAlgebra", "Memento", "PowerModelsDistribution"]
git-tree-sha1 = "a7fad5a02e1d7fc548f18910f4c7988fb87f17b8"
uuid = "f9e4c324-c3b6-4bca-9c3d-419775f0bd17"
version = "0.3.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "d3538e7f8a790dc8903519090857ef8e1283eecd"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.5"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "d7a7aef8f8f2d537104f170139553b14dfe39fe9"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.7.2"

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
git-tree-sha1 = "4036a3bd08ac7e968e27c203d45f5fff15020621"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.1.3"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "6a2f7d70512d205ca8c7ee31bfa9f142fe74310c"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.12"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "5ba658aeecaaf96923dce0da9e703bd1fe7666f9"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.4"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "87e9954dfa33fd145694e42337bdd3d5b07021a6"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.6.0"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "4f6ec5d99a28e1a749559ef7dd518663c5eca3d5"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.4.3"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "c3d8ba7f3fa0625b062b82853a7d5229cb728b6b"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.2.1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "5ce79ce186cc678bbb5c5681ca3379d1ddae11a1"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.7.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TextWrap]]
git-tree-sha1 = "9250ef9b01b66667380cf3275b3f7488d0e25faf"
uuid = "b718987f-49a8-5099-9789-dcd902bef87d"
version = "1.0.1"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[deps.URIs]]
git-tree-sha1 = "97bbe755a53fe859669cd907f2d96aee8d2c1355"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.3.0"

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

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╟─ef2b5e56-d2d1-11eb-0686-51cf4afc8846
# ╠═d8124cac-293a-4a2d-ba70-bc75ec624712
# ╟─ae76a6e5-f114-476f-8c53-36e369586d0c
# ╠═0641c9b7-4cb2-48a7-985a-fea34175a635
# ╟─626cc32c-99b1-4383-a346-16538af31963
# ╠═4891479c-9eb5-494e-ad1f-9bd52a171c57
# ╟─e1f1b7cf-d8ad-432d-ac98-95860e1ec65d
# ╠═f7636969-d29b-415e-8fe4-d725b6fa97d0
# ╟─1b10ab40-5b24-4370-984d-cce1de0f95f5
# ╠═e941118d-5b63-4886-bacd-82291f4c01c4
# ╟─353e797c-6155-4d7b-bb79-440d7b8f8ae2
# ╠═05454fe0-2368-4c67-ad82-bec852c56b85
# ╟─8134f0d4-7719-42e0-8f72-6967115d6bb6
# ╠═b0f23e3a-3859-467f-a8d1-5bdcf05132f8
# ╟─c6dbd392-2269-4572-8b07-ff7f233b8c89
# ╠═e686d58d-50ea-4789-93e7-5f3c41ee53ad
# ╟─27fd182f-3cdc-4568-b6f5-cae1b5e2e1a2
# ╠═6c421881-9df0-42c3-bf15-a1d4665bcb84
# ╟─70b6075c-b548-44d2-b301-9621023e06e0
# ╟─438b71e6-aca2-49b4-ab15-e747d335f331
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
# ╠═32073778-e62a-46ee-9797-3988be5c8fba
# ╟─6b1d3355-11ff-4aec-b6b2-b0fe0183dca6
# ╠═d418b2bf-a01d-43bf-8cd0-ca53be431a9f
# ╟─5b3c882d-c7c0-4acc-9d05-fafde347e4ff
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
