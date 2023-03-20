### A Pluto.jl notebook ###
# v0.19.22

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
md"Next, to obtain the results for the case where radiality is not enforced, we need to set the option 'options/constraints/disable-radiality-constraint' to false, which we can do with the `set_setting!` helper function which will return the multinetwork data structure."

# ╔═╡ 02098b72-8d5c-46c3-b0b5-cfcbb4bcdead
ieee13_mn_rad_disabled = ONM.set_setting!(
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

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Gurobi = "2e9cd046-0924-5485-92f1-d5272153d98b"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
PowerModelsONM = "25264005-a304-4053-a338-565045d392ac"
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"

[compat]
CSV = "~0.10.9"
DataFrames = "~1.5.0"
Gurobi = "~0.11.5"
PlutoUI = "~0.7.50"
PowerModelsONM = "~3.3.0"
VegaLite = "~2.6.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.5"
manifest_format = "2.0"
project_hash = "fec3fbf24a375a84935264be93bfee65546b4854"

[[deps.ASL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6252039f98492252f9e47c312c8ffda0e3b9e78d"
uuid = "ae81ac8f-d209-56e5-92de-9978fef736f9"
version = "0.1.3+0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

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

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

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

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "e8119c1a33d267e16108be441a287a6981ba1630"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.14.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SnoopPrecompile", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "aa51303df86f8626a962fccb878430cdb0a97eee"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.5.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

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

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "7be5f99f7d15578798f338f5433b6c432ea8037b"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.0"

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

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

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

[[deps.Gurobi]]
deps = ["LazyArtifacts", "Libdl", "MathOptInterface"]
git-tree-sha1 = "82a44a86f4dc4fa4510c9d49b0a74d3d73914d5c"
uuid = "2e9cd046-0924-5485-92f1-d5272153d98b"
version = "0.11.5"

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

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

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

[[deps.InvertedIndices]]
git-tree-sha1 = "82aec7a3dd64f4d9584659dc0b62ef7db2ef3e19"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.2.0"

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

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

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

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

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

[[deps.NodeJS]]
deps = ["Pkg"]
git-tree-sha1 = "905224bbdd4b555c69bb964514cfa387616f0d3a"
uuid = "2bd173c7-0d6d-553b-b6af-13a54713934c"
version = "1.3.0"

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

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "5bb5129fdd62a2bbbe17c2756932259acf467386"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.50"

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

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "LaTeXStrings", "Markdown", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "96f6db03ab535bdb901300f88335257b0018689d"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.2.2"

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

[[deps.StringManipulation]]
git-tree-sha1 = "46da2434b41f41ac3594ee9816ce5541c6096123"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.0"

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

[[deps.TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "78fecfe140d7abb480b53a44f3f85b6aa373c293"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.2"

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

[[deps.Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[deps.URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

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

[[deps.Vega]]
deps = ["DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "JSONSchema", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "Setfield", "TableTraits", "TableTraitsUtils", "URIParser"]
git-tree-sha1 = "c6bd0c396ce433dce24c4a64d5a5ab6dc8e40382"
uuid = "239c3e63-733f-47ad-beb7-a12fde22c578"
version = "2.3.1"

[[deps.VegaLite]]
deps = ["Base64", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "TableTraits", "TableTraitsUtils", "URIParser", "Vega"]
git-tree-sha1 = "3e23f28af36da21bfb4acef08b144f92ad205660"
uuid = "112f6efa-9a02-5b7d-90c0-432ed331239a"
version = "2.6.0"

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
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
