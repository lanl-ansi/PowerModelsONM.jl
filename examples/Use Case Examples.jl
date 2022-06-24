### A Pluto.jl notebook ###
# v0.19.9

#> [frontmatter]
#> title = "PowerModelsONM Use-Case Examples"

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 701604a7-f004-4a2c-94a0-249993bf0ea0
# ╠═╡ show_logs = false
begin
	using Pkg
	Pkg.activate(; temp=true)
	Pkg.add([
		Pkg.PackageSpec(; name="PowerModelsONM", rev="v3.0-rc"),
		Pkg.PackageSpec(; name="PowerModelsDistribution", version="0.14.4"),
		Pkg.PackageSpec(; name="VegaLite", version="2.6.0"),
		Pkg.PackageSpec(; name="DataFrames", version="1.3.4"),
		Pkg.PackageSpec(; name="CSV", version="0.10.4"),
		Pkg.PackageSpec(; name="PlutoUI", version="0.7.39")
	])

	# Pluto Notebook features
	using PlutoUI

	# Plotting
	import VegaLite as VL

	# Data Frames, CSV Parsing
	import DataFrames as DF
	import CSV
end

# ╔═╡ bc824edf-8b1d-47b3-8183-d2ec7032f500
html"""
<style>
	main {
		margin: 0 auto;
		max-width: 2000px;
    	padding-left: max(160px, 20%);
    	padding-right: max(160px, 20%);
	}
</style>
"""

# ╔═╡ 861f564c-8408-48fd-8cf2-d6e12915176a
md"""# ONM Use Cases

In this Pluto notebook, we present several use cases that are used to study the basics of the ONM library.

We use three different data sets, described in more detail below, consisting of

- a modified version of the ieee13 disitribution feeder, which is also used in PowerModelsONM's unit tests,
- a modified version of the iowa-240 distribution feeder, and
- a feeder provided by a utility partner, whose raw data is not included here for privacy reasons.
"""

# ╔═╡ 7a915f37-a7f5-4b85-ba15-42a9712832f7
md"""
## Environment

Here we setup the appropriate environment that was originally used to study the use cases in this notebook.
"""

# ╔═╡ 9fdad25d-fb6c-48b2-9b6a-d2ea11b6c3a0
md"""
### Use Gurobi?

Originally, these results were obtained using Gurobi, and are not guaranteed to be exactly reproduced with other solvers, although experimentation with HiGHS suggested that results are very close, it not identical.

In order to use the Gurobi solver, you must already have Gurobi binaries on your system, a valid license, and the `ENV` variables correctly populated.

Use Gurobi? $(@bind use_gurobi CheckBox())
"""

# ╔═╡ b70631b1-5eb6-42ac-a7ec-358222633b62
if use_gurobi
	Pkg.add(Pkg.PackageSpec(; name="Gurobi", version="0.11.3"))
	import Gurobi
end

# ╔═╡ 62288458-90ff-4fa2-bae6-6f7216304b45
md"""## Import PowerModelsONM

In this notebook we import PowerModelsONM as `ONM`, which gives a clearer picture to the user from where each function originates.
"""

# ╔═╡ 5baf2811-6b63-4edb-9dda-840bff0f1004
# ╠═╡ show_logs = false
import PowerModelsONM as ONM

# ╔═╡ 36f20393-54d1-4566-9d07-afaa5f83fc8c
md"The following is the path to the data used in this notebook"

# ╔═╡ 03c51d46-3314-48bb-8039-f04780773ad3
onm_path = joinpath(dirname(pathof(ONM)), "..", "examples", "data")

# ╔═╡ 3ddafef5-26e9-405e-bf3b-81a1f2c5af27
md"""
## Modified IEEE13 Use Case (ieee13-onm-mod)

In the following Section, we will utilize the modified IEEE13 distribution feeder case. This case has been modified to include new switches, DER, including solar PV, energy storage, and traditional generation, and some additional loads, to create new load blocks and microgrids. The purpose behind the creation of this modified network was primarily for unit testing of the various features of PowerModelsONM.

### Single-line diagram of ieee13-onm-mod

Below is the single-line diagram of the modified IEEE13 distribution feeder. This was created by exporting the network data to the `graphml` format and useing yEd for layout and visualization.

The legend is as follows:

- Black dots are buses,
- red star is the substation,
- orange solid lines are transformers,
- black solid lines are lines,
- dashed green lines are normally-closed switches,
- dotted red lines are normally-open tie switches,
- yellow triangles are loads,
- blue circles are generators,
- blue trapezoids are solar PV, and
- blue rectangles are battery storage.

"""

# ╔═╡ d5b09fa0-32a1-42b0-824e-a19392ee3d9b
# ╠═╡ show_logs = false
begin
	ieee13_svg = open(joinpath(onm_path, "ieee13.svg"), "r") do io
		read(io, String)
	end

	HTML("""<div style="position:relative">$(ieee13_svg)</div>""")
end

# ╔═╡ 88f865e8-ac92-4ec5-a791-7f7802c1b731
md"""### Instantiate ieee13-onm-mod data, settings, events

In PowerModelsONM, there are several standard input files besides the network definition in DSS format.

In particular, we often define *settings*, which can contain additional parameters, such as solver settings or options used to easily control which default constraints, objective terms, variables, etc. are used in a problem, or overwrites of the DSS parameters, in the syntax of the PowerModelsDistribution ENGINEERING data model. These *settings* apply across all time steps.

We can also define *events*, which are a time-series of switching events, and apply to the time steps at which they are defined, **and all later timesteps**.

Below, we load the base data set for ieee13-onm-mod by defining a `Dict` with paths to the relevant files, and parsing it with the `prepare_data!` function.
"""

# ╔═╡ b11b3d8d-bb1e-433d-a97d-dc1eb0b29fd7
# ╠═╡ show_logs = false
ieee13_data = ONM.prepare_data!(
	Dict{String,Any}(
		"network" => joinpath(onm_path, "network.ieee13.dss"),
		"settings" => joinpath(onm_path, "settings.ieee13.json"),
		"events" => joinpath(onm_path, "events.ieee13.json"),
	)
)

# ╔═╡ 9174e419-e5d2-462f-9d04-d7d7067fa984
ieee13_mn = deepcopy(ieee13_data["network"])

# ╔═╡ 917f902c-2f59-4a35-97e0-ccd1a6bd384a
md"""### Instantiate solvers for ieee13-onm-mod use cases
"""

# ╔═╡ b0d134fb-aea8-41aa-a533-f1a45eb86c38
md"If `use_gurobi`, set appropriate option before instantiating solvers"

# ╔═╡ 596407b3-e534-47fb-913e-57ac634c7061
ieee13_data["settings"]["solvers"]["useGurobi"] = use_gurobi

# ╔═╡ 29872a21-ea5e-4875-8c61-8c1c1f55d34f
md"For the use-case utilizing ieee13-onm-mod data, we will only need a MIP solver"

# ╔═╡ 1138de8e-6aaa-4fd3-9805-0632e819f74b
ieee13_mip_solver = ONM.build_solver_instances(; solver_options=ieee13_data["settings"]["solvers"])["mip_solver"]

# ╔═╡ 00b34495-c18d-45f8-aa20-ced51dd91231
md"""### Use-Case I: Radiality constraint comparison

In the following use-case, we explore the effect of the radiality constraint on the number of loads shed throughout the time-series.

The radiality constraint implemented by default in PowerModelsONM is based on a multi-commodity flow formulation as defined in **S. Lei, C. Chen, Y. Song, and Y. Hou, “Radiality constraints for resilient reconfiguration of distribution systems: Formulation and application to microgrid formation,” IEEE Transactions on Smart Grid, vol. 11, no. 5, pp. 3944–3956, 2020.**


"""

# ╔═╡ 48b6664b-3512-4344-9ae3-12c8527f4726
md"First we obtain the results for the case where radiality is enforced, which is the default state"

# ╔═╡ 0d23be40-d3cf-4cb3-9976-1a3de0769be7
# ╠═╡ show_logs = false
result_rad_enabled = ONM.optimize_switches(
	ieee13_mn,
	ieee13_mip_solver;
	formulation=ONM.LPUBFDiagPowerModel,
	algorithm="rolling-horizon",
	problem="block"
)

# ╔═╡ f6aba3cc-4cbb-42bb-bfb2-a8bfb89090f2
md"Next, to obtain the results for the case where radiality is not enforced, we need to set the option 'options/constraints/disable-radiality-constraint' to false, which we can do with the `set_option!` helper function which will return the multinetwork data structure."

# ╔═╡ 02098b72-8d5c-46c3-b0b5-cfcbb4bcdead
ieee13_mn_rad_disabled = ONM.set_option!(
	deepcopy(ieee13_data),
	("options","constraints","disable-radiality-constraint"),
	true
)

# ╔═╡ ea73ea65-c4a7-4934-9900-2d815e1075f7
# ╠═╡ show_logs = false
result_rad_disabled = ONM.optimize_switches(
	ieee13_mn_rad_disabled,
	ieee13_mip_solver;
	formulation=ONM.LPUBFDiagPowerModel,
	algorithm="rolling-horizon",
	problem="block"
)

# ╔═╡ 7c974201-7a25-4f08-aed9-6d6e28824e01
md"Below is a plot of the number of load shed at each timestep for radiality constrained and unconstrained."

# ╔═╡ 28adbe85-4e82-4fcd-8e8f-28421ad56c36
begin
	rad_enabled_dat = ONM.get_timestep_device_actions(ieee13_mn, result_rad_enabled)
	rad_disabled_dat = ONM.get_timestep_device_actions(ieee13_mn, result_rad_disabled)

	ieee13_rad_df = DF.DataFrame(
		loads_shed = [
			[length(r["Shedded loads"]) for r in rad_enabled_dat]...,
			[length(r["Shedded loads"]) for r in rad_disabled_dat]...
		],
		radiality = [
			fill("constrained", length(rad_enabled_dat))...,
			fill("unconstrained", length(rad_disabled_dat))...
		],
		simulation_time_steps = [
			sort(collect(values(ieee13_data["network"]["mn_lookup"])))...,
			sort(collect(values(ieee13_data["network"]["mn_lookup"])))...
		]
	)

	ieee13_rad_df |> VL.@vlplot(
		autosize = {
	    	type ="fit",
	    	contains= "padding"
		},
		mark = "bar",
		encoding = {
			x = {
				field = ":radiality",
				type = "nominal",
				axis = {
					title = "",
					labels = false
				}
			},
			y = {
				field = ":loads_shed",
				type = "quantitative",
				axis = {
					title = "# Loads Shed",
					grid = true
				}
			},
			column = {
				field = ":simulation_time_steps",
				type = "nominal",
				axis = {
					title = "Time Step (hr)"
				}
			},
			color = {
				field = ":radiality",
				type = "nominal",
				axis = {
					title = "Radiality"
				}
			}
		},
		config={
	        view={stroke="transparent"},
	        axis={domainWidth=1, titleFontSize=18, labelFontSize=18},
	        legend={titleFontSize=18, labelFontSize=18},
	        header={titleFontSize=18, labelFontSize=18},
	        mark={titleFontSize=18, labelFontSize=18},
	        title={titleFontSize=18, labelFontSize=18},
	    }
	)
end

# ╔═╡ c9b3f06f-e323-4b3e-9c7f-bf2fffc147ba
md"""
## Modified Iowa-240 Use Cases (iowa240-onm-mod)

The modified Iowa-240 disitribution feeder case was dervied from the [Iowa Distribution Test Systems](http://wzy.ece.iastate.edu/Testsystem.html) developed by F. Bu *et al.*, published originally in **F. Bu, Y. Yuan, Z. Wang, K. Dehghanpour, and A. Kimber, "A Time-series Distribution Test System based on Real Utility Data." 2019 North American Power Symposium (NAPS), Wichita, KS, USA, 2019, pp. 1-6.**

Again, like with ieee13-onm-mod, the goal with the modification of the Iowa-240 system was to create microgrids. In this case, the primary changes were to add DER, solar PV and energy storage in this case, and to equivalence out the distribution level transformers to simplify the case.

### Single-line Diagram of iowa240-onm-mod

Below is the single-line diagram for the modified Iowa-240 feeder, again made by exporting the network data to a `graphml` file and using yEd to perform layout and visualization.

The legend is identical to the one noted for [Single-line diagram of ieee13-onm-mod](#single-line-diagram-of-ieee13-onm-mod)
"""

# ╔═╡ 52e269ec-bb85-4bd7-a20b-2d74d8dc45d0
begin
	iowa240_svg = open(joinpath(onm_path, "iowa240.svg"), "r") do io
		read(io, String)
	end
	HTML("""<div style="position:relative">$(iowa240_svg)</div>""")
end

# ╔═╡ 9bdccc20-c648-4eef-b9c6-4b00879175ec
md"""### Load base iowa240-onm-mod data, settings, events
"""

# ╔═╡ 3da0e6c8-4723-405a-9028-b689af65bbd2
# ╠═╡ show_logs = false
iowa240_data = ONM.prepare_data!(
	Dict{String,Any}(
		"network" => joinpath(onm_path, "network.iowa240.dss"),
		"settings" => joinpath(onm_path, "settings.iowa240.json"),
		"events" => joinpath(onm_path, "events.iowa240.json"),
	)
)

# ╔═╡ b2c44bdf-7460-4330-a97b-984dbea8e0be
iowa240_mn = iowa240_data["network"]

# ╔═╡ 46670d95-c4c5-4a3b-adce-f9637ce1daba
md"""### Instantiate iowa240-onm-mod solvers

If `use_gurobi` is `false`, we need to disable the Gurobi solver before solvers are instantiated
"""

# ╔═╡ f5dbdad4-f919-4b34-a7b6-5c479148528f
iowa240_data["settings"]["solvers"]["useGurobi"] = use_gurobi

# ╔═╡ 3d3049c4-9363-4c52-b14b-9f41e14657d2
iowa240_mip_solver = ONM.build_solver_instances(; solver_options=iowa240_data["settings"]["solvers"])["mip_solver"]

# ╔═╡ e37c48ba-f0ba-4138-8677-d21ed1be4992
iowa240_nlp_solver = ONM.build_solver_instances(; solver_options=iowa240_data["settings"]["solvers"])["nlp_solver"]

# ╔═╡ 60378675-075f-427c-909c-602bdd34e15c
md"""### Use-Case II: Algorithm Comparison between Rolling-Horizon and Full-Lookahead

In this use-case we utilize the iowa240-onm-mod case to explore the differences when using the two algorithms currently available in PowerModelsONM: `"rolling-horizon"`, which optimizes the feeder topology sequentially one timestep at a time, and `"full-lookahead"`, which optimizes the feeder topology for all timesteps all at once.

For this use-case we need to run two optimizations, one using `"rolling-horizon"` (`result_iowa240_rolling`), and one using `"full-lookahead"` (`result_iowa240_lookahead`).

Note that in each case the ACR formulation is utilized after the switch optimization to obtain the optimal dispatch results, which requires some additional time, so these cases will take between 300-500 seconds to run, each.
"""

# ╔═╡ 2bb9deea-580f-4614-9bc4-c4a804a7a69e
# ╠═╡ show_logs = false
result_iowa240_rolling = ONM.optimize_dispatch(
	iowa240_mn,
	ONM.ACRUPowerModel,
	iowa240_nlp_solver;
	switching_solutions=ONM.optimize_switches(
		iowa240_mn,
		iowa240_mip_solver;
		formulation=ONM.LPUBFDiagPowerModel,
		algorithm="rolling-horizon",
		problem="block"
	)
)

# ╔═╡ f058abdf-714a-4044-bcb9-85dde7f75190
# ╠═╡ show_logs = false
result_iowa240_lookahead = ONM.optimize_dispatch(
	iowa240_mn,
	ONM.ACRUPowerModel,
	iowa240_nlp_solver;
	switching_solutions=ONM.optimize_switches(
		iowa240_mn,
		iowa240_mip_solver;
		formulation=ONM.LPUBFDiagPowerModel,
		algorithm="full-lookahead",
		problem="block"
	)
)

# ╔═╡ 0a311867-ac57-472a-93ec-4de35aff3036
md"""
Below is a plot of the comparison between the Storage State of Charge (SOC) in percent of total available stored energy, and the Total load served, as a percent of total load in the feeder, as a function of time in hours.
"""

# ╔═╡ bbb3028f-e812-4caf-b859-a3b9814a34ec
begin
	iowa240_rolling_total_served = ONM.get_timestep_load_served(
		result_iowa240_rolling["solution"],
		iowa240_mn)["Total load (%)"]
	iowa240_rolling_soc_stats = ONM.get_timestep_storage_soc(
		result_iowa240_rolling["solution"],
		iowa240_mn
	)

	iowa240_lookahead_total_served = ONM.get_timestep_load_served(
		result_iowa240_lookahead["solution"],
		iowa240_mn)["Total load (%)"]
	iowa240_lookahead_soc_stats = ONM.get_timestep_storage_soc(
		result_iowa240_lookahead["solution"],
		iowa240_mn
	)

	iowa240_algorithm_df = DF.DataFrame(
		simulation_time_steps = [
			sort(collect(values(iowa240_mn["mn_lookup"])))...,
			sort(collect(values(iowa240_mn["mn_lookup"])))...,
			sort(collect(values(iowa240_mn["mn_lookup"])))...,
			sort(collect(values(iowa240_mn["mn_lookup"])))...,
		].+1.0,
		data = [
			iowa240_rolling_soc_stats...,
			iowa240_rolling_total_served...,
			iowa240_lookahead_soc_stats...,
			iowa240_lookahead_total_served...,
		],
		data_type = [
			fill("Storage SOC (%)", length(iowa240_rolling_soc_stats))...,
			fill("Total Load Served (%)", length(iowa240_rolling_total_served))...,
			fill("Storage SOC (%)", length(iowa240_lookahead_soc_stats))...,
			fill("Total Load Served (%)", length(iowa240_lookahead_total_served))...,
		],
		algorithm = [
			fill("Rolling Horizon", length(iowa240_rolling_soc_stats)*2)...,
			fill("Decomposition", length(iowa240_rolling_soc_stats)*2)...,
		]
	)

	iowa240_algorithm_df |> VL.@vlplot(
	    mark="line",
		autosize = {
	    	type ="fit",
	    	contains= "padding"
		},
		encoding={
	        row={
				field=":data_type",
				type="nominal",
				axis={
					title="",
					labels=false
				}
			},
	        x={
				field=":simulation_time_steps",
				type="nominal",
				axis={
					title="Time Step (hr)",
					grid=true,
					values=collect([i for i in iowa240_algorithm_df[!,:simulation_time_steps] if i%2==0])
				}
			},
	        y={
				field=":data",
				type="quantitative",
				axis={
					grid=true,
					title=""
				},
				scale={
					domain=[0,100]
				}
			},
	        color={
				field=":algorithm",
				type="nominal",
				legend={
					orient="right",
					fillColor="white"
				},
				axis={
					title="Algorithm"
				}
			},
	    },
	    config={
	        axis={titleFontSize=14, labelFontSize=14},
	        legend={titleFontSize=14, labelFontSize=14},
	        header={titleFontSize=14, labelFontSize=14},
	        mark={titleFontSize=14, labelFontSize=14},
	        title={titleFontSize=14, labelFontSize=14},
	    }
	)
end

# ╔═╡ bba41d8f-5a27-4b82-8613-ab0dc532db76
md"""### Use-Case III: Formulation Comparison, LinDist3Flow vs Network Flow Approximation

In this use case we compare the results of the standard LinDist3Flow formulation versus the results from the network flow approximation, otherwise known as the transportation model.
"""

# ╔═╡ 67a23f8c-862f-4578-957f-4cfd82d20e89
# ╠═╡ show_logs = false
result_iowa240_ldf = ONM.optimize_dispatch(
	iowa240_mn,
	ONM.LPUBFDiagPowerModel,
	iowa240_nlp_solver;
	switching_solutions=ONM.optimize_switches(
		iowa240_mn,
		iowa240_mip_solver;
		formulation=ONM.LPUBFDiagPowerModel,
		algorithm="full-lookahead",
		problem="block"
	)
)

# ╔═╡ 93647124-a64e-4ee0-a6ac-0c975b231a3e
# ╠═╡ show_logs = false
result_iowa240_nfa = ONM.optimize_dispatch(
	iowa240_mn,
	ONM.NFAUPowerModel,
	iowa240_nlp_solver;
	switching_solutions=ONM.optimize_switches(
		iowa240_mn,
		iowa240_mip_solver;
		formulation=ONM.NFAUPowerModel,
		algorithm="full-lookahead",
		problem="block"
	)
)

# ╔═╡ 775a2d77-2c72-4601-8600-6e60c71077fa
md"Below is a plot of the dispatch profiles for the LinDistFlow and Transportation models separated by the source of the dispatch, as a function of time"

# ╔═╡ 2d5f4134-514f-442a-ae22-ae363e749382
begin
	profile_types = ["Solar DG (kW)", "Diesel DG (kW)", "Grid mix (kW)", "Energy storage (kW)"]

	iowa240_ldf_dispatch_stats = ONM.get_timestep_generator_profiles(result_iowa240_ldf["solution"])
	iowa240_nfa_dispatch_stats = ONM.get_timestep_generator_profiles(result_iowa240_nfa["solution"])

	iowa240_formulation_df = DF.DataFrame(
		simulation_time_steps = [
			[j for n in 1:length(profile_types) for j in sort(collect(values(iowa240_mn["mn_lookup"])))]...,
			[j for n in 1:length(profile_types) for j in sort(collect(values(iowa240_mn["mn_lookup"])))]...
		],
		data = [
			[j for item in profile_types for j in iowa240_nfa_dispatch_stats[item]]...,
			[j for item in profile_types for j in iowa240_ldf_dispatch_stats[item]]...
		],
	    data_type = [
			[j for item in profile_types for j in fill(item, length(iowa240_mn["nw"]))]...,
			[j for item in profile_types for j in fill(item, length(iowa240_mn["nw"]))]...
		],
	    formulation = [
			fill("Transportation", length(iowa240_mn["nw"])*length(profile_types))...,
			fill("LinDistFlow", length(iowa240_mn["nw"])*length(profile_types))...
		]
	)

	iowa240_formulation_df |> VL.@vlplot(
	    	autosize = {
	    	type ="fit",
	    	contains= "padding"
		},
		mark="line",
	    encoding={
	        row={
				field=":data_type",
				type="nominal",
				axis={
					title="",
				    labels=false
				}
			},
	        x={
				field=":simulation_time_steps",
				type="nominal",
				axis={
					title="Time Step (hr)",
					grid=true,
					values=collect([i for i in iowa240_formulation_df[!,:simulation_time_steps] if i%2==0])
				}
			},
	        y={
				field=":data",
				type="quantitative",
				axis={
					grid=true,
					title=""
				}
			},
	        color={
				field=":formulation",
				type="nominal",
				legend={
					orient="right",
					fillColor="white"
				},
				axis={
					title="Formulation"
				}
			},
	    },
	    resolve={
			scale={
				y="independent"
			}
		},
	    config={
	        axis={titleFontSize=14, labelFontSize=14},
	        legend={titleFontSize=14, labelFontSize=14},
	        header={titleFontSize=14, labelFontSize=14},
	        mark={titleFontSize=14, labelFontSize=14},
	        title={titleFontSize=14, labelFontSize=14},
	    }
	)
end

# ╔═╡ 26a7c89c-2fdf-4657-b970-9e036f569504
md"""
## Practical Use Case

**Note that the input data for the practical use-case are propriatary, and we therefore only include some general details of the feeder, and some aggregate results from the optimization, with some explanation, to ensure compliance with the non-disclosure aggreement.**

To demonstrate algorithmic scalability and highlight a practical use case enabled by our approach, we utilize a utility-provided feeder model featuring 374 buses (981 nodes), 40 dispatchable switches, and 25 DER. The DER include a mix of solar PV, battery storage, and traditional generation, split between 5 microgrids. This scenario considers 48 7.5-minute time steps over a 6-hour time horizon during the day, where solar PV irradiance is always non-zero, and the feeder is isolated throughout, and the microgrids are all operating independently in the initial time step.

### Use-Case IV: Microgrid Networking, Enabled vs Disabled

We ran two scenarios, "Enabled" one where microgrids were allowed to expand and network with one-another, and "Disabled" another where microgrids were allowed to expand, but not allowed to network with one-another. This is achieved by setting the option "options/constraints/disable-microgrid-networking" to `true`.

Below is a plot that compares the percent of load served, separated by category, where total load is a percent of all possible load in the system supported, microgrid load is a percent of the total load contained only within microgrids, bonus load via MG is a percent of the total possible load *outside* the microgrids that are supported by microgrid resources, and feeder served is the total load outside the Microgrid that is supported by the feeder (substation).
"""

# ╔═╡ 4bf3ca39-e55d-4ca8-9bfa-27b143a1c99e
begin
	practical_case_stats = CSV.read(joinpath(onm_path, "practical-case-stats.csv"), DF.DataFrame)


	practical_case_stats |> VL.@vlplot(
		autosize = {
	    	type ="fit",
	    	contains= "padding"
		},
	    facet = {row={field=":type", title="Microgrid Networking"}},
	    spec = {
	        encoding = {
	            x = {
	                field = ":simulation_time_steps",
	                type = "nominal",
	                axis = {
	                    title = "Time Step (Min)",
	                    values = [0, 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195],
	                    grid = true
	                }
	            },
	        },
	        layer = [
	            {
	                mark = "line",
	                encoding = {
	                    y = {
	                        field = ":Total Load Served",
	                        type = "quantitative",
	                        title = "Load Served (%)"
	                    },
	                    color = {
	                        datum = "Total Load",
	                        legend = {
	                            orient = "right",
	                            fillColor = "white"
	                        }
	                    }
	                }
	            },
	            {
	                mark = "line",
	                encoding = {
	                    y = {
	                        field = ":Microgrid Load Served",
	                        type = "quantitative",
	                        title = "Load Served (%)"
	                    },
	                    color = {
	                        datum = "Microgrid Load"
	                    }
	                }
	            },
	            {
	                mark = "line",
	                encoding = {
	                    y = {
	                        field = ":Bonus Load Served via Microgrid",
	                        type = "quantitative",
	                        title = "Load Served (%)"
	                    },
	                    color = {
	                        datum = "Bonus Load via MG"
	                    }
	                }
	            },
	            {
	                mark = "line",
	                encoding = {
	                    y = {
	                        field = ":Feeder Load Served",
	                        type = "quantitative",
	                        title = "Load Served (%)"
	                    },
	                    color = {
	                        datum = "Feeder Served"
	                    }
	                }
	            }
	        ],
	    },
	    config = {
	        axis = {titleFontSize = 18, labelFontSize = 18},
	        legend = {titleFontSize = 18, labelFontSize = 18},
	        header = {titleFontSize = 18, labelFontSize = 18},
	        mark = {titleFontSize = 18, labelFontSize = 18},
	        title = {titleFontSize = 18, labelFontSize = 18},
	    }
	)
end

# ╔═╡ Cell order:
# ╟─bc824edf-8b1d-47b3-8183-d2ec7032f500
# ╟─861f564c-8408-48fd-8cf2-d6e12915176a
# ╟─7a915f37-a7f5-4b85-ba15-42a9712832f7
# ╠═701604a7-f004-4a2c-94a0-249993bf0ea0
# ╟─9fdad25d-fb6c-48b2-9b6a-d2ea11b6c3a0
# ╠═b70631b1-5eb6-42ac-a7ec-358222633b62
# ╟─62288458-90ff-4fa2-bae6-6f7216304b45
# ╠═5baf2811-6b63-4edb-9dda-840bff0f1004
# ╟─36f20393-54d1-4566-9d07-afaa5f83fc8c
# ╠═03c51d46-3314-48bb-8039-f04780773ad3
# ╟─3ddafef5-26e9-405e-bf3b-81a1f2c5af27
# ╟─d5b09fa0-32a1-42b0-824e-a19392ee3d9b
# ╟─88f865e8-ac92-4ec5-a791-7f7802c1b731
# ╠═b11b3d8d-bb1e-433d-a97d-dc1eb0b29fd7
# ╠═9174e419-e5d2-462f-9d04-d7d7067fa984
# ╟─917f902c-2f59-4a35-97e0-ccd1a6bd384a
# ╟─b0d134fb-aea8-41aa-a533-f1a45eb86c38
# ╠═596407b3-e534-47fb-913e-57ac634c7061
# ╟─29872a21-ea5e-4875-8c61-8c1c1f55d34f
# ╠═1138de8e-6aaa-4fd3-9805-0632e819f74b
# ╟─00b34495-c18d-45f8-aa20-ced51dd91231
# ╟─48b6664b-3512-4344-9ae3-12c8527f4726
# ╠═0d23be40-d3cf-4cb3-9976-1a3de0769be7
# ╟─f6aba3cc-4cbb-42bb-bfb2-a8bfb89090f2
# ╠═02098b72-8d5c-46c3-b0b5-cfcbb4bcdead
# ╠═ea73ea65-c4a7-4934-9900-2d815e1075f7
# ╟─7c974201-7a25-4f08-aed9-6d6e28824e01
# ╟─28adbe85-4e82-4fcd-8e8f-28421ad56c36
# ╟─c9b3f06f-e323-4b3e-9c7f-bf2fffc147ba
# ╟─52e269ec-bb85-4bd7-a20b-2d74d8dc45d0
# ╟─9bdccc20-c648-4eef-b9c6-4b00879175ec
# ╠═3da0e6c8-4723-405a-9028-b689af65bbd2
# ╠═b2c44bdf-7460-4330-a97b-984dbea8e0be
# ╟─46670d95-c4c5-4a3b-adce-f9637ce1daba
# ╠═f5dbdad4-f919-4b34-a7b6-5c479148528f
# ╠═3d3049c4-9363-4c52-b14b-9f41e14657d2
# ╠═e37c48ba-f0ba-4138-8677-d21ed1be4992
# ╟─60378675-075f-427c-909c-602bdd34e15c
# ╠═2bb9deea-580f-4614-9bc4-c4a804a7a69e
# ╠═f058abdf-714a-4044-bcb9-85dde7f75190
# ╟─0a311867-ac57-472a-93ec-4de35aff3036
# ╟─bbb3028f-e812-4caf-b859-a3b9814a34ec
# ╟─bba41d8f-5a27-4b82-8613-ab0dc532db76
# ╠═67a23f8c-862f-4578-957f-4cfd82d20e89
# ╠═93647124-a64e-4ee0-a6ac-0c975b231a3e
# ╟─775a2d77-2c72-4601-8600-6e60c71077fa
# ╟─2d5f4134-514f-442a-ae22-ae363e749382
# ╟─26a7c89c-2fdf-4657-b970-9e036f569504
# ╟─4bf3ca39-e55d-4ca8-9bfa-27b143a1c99e
