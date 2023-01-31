# PowerModelsONM Changelog

## staged

- Added robust mld problem formulation using scenario-based approach
- Added draft schema for robust partitions outputs
- Fixed Dockerfile to work with julia-buildpkg:latest
- Deprecates "switch" in power flow outputs in favor of "protection"
- Adds "protection" to the power flow outputs which adds voltage magnitudes and angles, and real and reactive power flows for each device that is referenced by a protection device (e.g., fuse, recloser, relay)

## v3.2.0

- Added `constraint_energized_blocks_strictly_increasing` to `mld_block` and `mld_traditional` multinetwork problems, which can be enabled with option `enable-strictly-increasing-restoration-constraint`
- Fixed `run_fault_studies` to use `build_mc_sparse_fault_study` if faults are `missing`
- Added `"theta (deg)"` as output in fault currents, representing the phase angle of the current on the from-side of the switch/line
- Updated version of Julia in Dockerfile to v1.8.2

## v3.1.0

- Fixed bug in transformer tap variable creation in JuMP by-hand example
- Updated documentation and JuMP by-hand example to match latest version of constraints
- Fixed bug in `constraint_grid_forming_inverter_per_cc_{block|traditional}` where exactly one DER was not strictly required
- Fixed bug in fault current output where if protection objects were not switches, their fault currents were not included in output
- Fixed bug in protection model where `location` is missing, and `monitoredobj` is used instead
- Added line impedances `rs` and `xs` to the protection network model
- Added `"phi (deg)"` as output in fault currents, representing the bus voltage angle at the f-bus of the switch
- Fixed bug in objective functions where if no storage was present, calculating `total_energy_ub` would result in error
- Fixed bug in `build_graphml_document` where some values were `SubString` instead of `String`
- Fixed bug in `get_timestep_load_served` to convert `NaN` into zeros
- Fixed bug in `constraint_grid_forming_inverter_per_cc` that was causing infeasibilities in cases where there were no grid-forming inverters in a block
- Refactored `constraint_grid_forming_inverter_per_cc` into `constraint_grid_forming_inverter_per_cc_block` and `constraint_grid_forming_inverter_per_cc_traditional`
- Added helper function `check_switch_state_feasibility` to help users determine if the default switch states are feasible (assuming radiality constraints)
- Fixed bug where `"gen_model"` from PowerModelsProtection was not being passed to the `MATHEMATICAL` model on transformation
- Added `_dss2eng_gen_model!` from PowerModelsProtection to `parse_file`

## v3.0.1

- Fixed bug in `apply_settings` where settings for ENGINEERING data model object were getting written even if they did not exist in the original data model
- Updated Pluto notebooks PowerModelsONM version to `3.0.0`

## v3.0.0

- Added documentation for GraphML export
- Updated process flow diagram for ONM
- Added helper functions to set options and get options from the different data structures used by ONM
- Explicitly exported a number of AbstractUnbalancedPowerModels from PowerModelsDistribution, for better user experience
- Switched to `import LongName as LN` pattern
- Updated `"iterative"` to `"rolling-horizon"` and `"global"` to `"full-lookahead"` (**breaking**)
- Deprecated many runtime arguments in favor of settings schema
- Updated default logger settings
- Added `build_settings_new` functions to match updated schema
- Refactored to use schemas directly to build Julia data structures, to make API maintanence easier
- Added `prepare_data!` function to quickly build the multinetwork `network` data from `network`, `settings` and `events` files
- Refactored settings functions to apply settings to base_network and then rebuild the multinetwork structure (**breaking**)
- Refactored settings schemas to allow for more options for user control of different parts of the entrypoint function (**breaking**)
- Added more documentation for new users to the examples folder, including use cases, basic usage of the Block-MLD problem, and how to build a JuMP model by hand
- Added support for exporting network data as a graph in the GraphML format
- Added EzXML as a dependency to support GraphML export
- Removed ProgressMeter dependency
- Added support for JuMP v1
- Added `transform_data_model` specific to ONM
- Added `instantiate_onm_model`, an ONM-specific version of `instantiate_mc_model` from PowerModelsDistribution
- Added `dss` settings schema for easier adding of inverter property by source id, e.g., "vsource.source", etc.
- Added `constraint_disable_networking` based on coloring model to enabled microgrids to expand but not network
- Updated events schema to allow for typical string values for certain switch fields
- Added disable-networking option to CLI for future implementation of feature
- Changed objective function term balances to ensure that restoring load is always the most critical term
- Fixed bug in `_prepare_fault_study_multinetwork_data` where `va` was not being used
- Added option to `get_timestep_fault_currents` to filter out switches from outputs that have no associated protection devices (i.e., relay, recloser, fuse)
- Changed instances of `Int64` to `Int`
- Fixed issue with transformer control constraints in dispatch optimization
- Added support for [JuMP](https://jump.dev) v0.23
- Changed built-in mip solver from [Cbc](https://github.com/jump-dev/Cbc.jl) to [HiGHS](https://github.com/jump-dev/HiGHS.jl)
- Added user option to disable presolvers in the built-in solvers `disable_presolver`
- Changed `@warn` to `@info` in `_find_switch_id_from_source_id`
- Updated radial topology constraint in `constraint_radial_topology` to be switch-direction-agnostic (previously required a strongly connected directed graph)
- Added constraint for reference buses that uses `inverter` state to set theta constraints, `constraint_mc_inverter_theta_ref`
- Added phase unbalance constraint for grid-following storage `constraint_mc_storage_phase_unbalance_grid_following`
- Added inverters to `_prepare_fault_study_multinetwork_data` and `_prepare_dispatch_data`
- Added user option to disable inverter constraint: `disable_inverter_constraint`
- Added constraint for identifying a single grid-forming inverter per connected component `constraint_grid_forming_inverter_per_cc_{block|traditional}`
- Added `get_timestep_inverter_states!` which adds inverter states to the `"Powerflow output"`
- Added `solution_inverter!`, which converts `inverter` variable value to `Inverter` enum
- Added `Inverter`, with `GRID_FOLLOWING` and `GRID_FORMING` enums to indicate what generation object is acting as grid-forming or following
- Fixed `constraint_mc_power_balance_shed_block`, wrong call to `PMD.diag`, should have been `LinearAlgebra.diag`
- Added `cost_pg_parameters` and `cost_pg_model` to settings schemas for generators, voltage sources, and storage and solar devices
- Added `opt-switch-problem` flag to runtime input to enable section of `block` or `traditional` optimal switching problems
- Removed `SwitchModel` types to realign software design with InfrastructureModels (**breaking**)
- Refactored problems to better delineate mld code from PMD (**breaking**)
- Added `traditional` mld problem
- Renamed problems, objective functions, and constraint functions to be more simple for users (**breaking**)
- Added solution processor function `solution_statuses!` to assist in converting solution statuses to `Status` enums
- Fixed `_prepare_dispatch_data` to account for new `traditional` mld problem type
- Disabled _indicator_ constraints (**breaking**)
- Fixed bug in `get_timestep_microgrid_networks`
- Introduced `block` and `traditional` versions of constraints to account for different `z` indicator variables (**breaking**)
- Renamed `constraint_switch_state_max_actions` to `constraint_switch_close_action_limit` to better reflect the nature of the constraint (**breaking**)
- Renamed `variable_mc_block_indicator` to `variable_block_indicator`, since it was not a multiconductor variable (**breaking**)
- Renamed `variable_mc_switch_state` to `variable_switch_state`, since it was not a multiconductor variable (**breaking**)
- Refactored `variable_mc_switch_fixed` to be called from inside `variable_switch_state` directly (**breaking**)
- Added `variable_mc_storage_power_mi_on_off`, which will not attempt to make its own `z_storage` indicator variable as in PowerModelsDistribution
- Added "traditional" indicator variable functions, `variable_bus_voltage_indicator`, `variable_generator_indicator`, `variable_storage_indicator`, and `variable_load_indicator`
- Fixed bug in `solution_reference_buses!`
- Added `solve_onm_model`
- Updated README
- Updated documentation
- Updated examples

## v2.1.2

- Fixed documentation build process

## v2.1.1

- Fixed bug in recursive merge for `build_settings_file`
- Fixed bug where `PMD.diag` should have been `LinearAlgebra.diag`
- Fixed bug in `build_settings_file` where the recursive merge was not overwriting the `settings` variable

## v2.1.0

- Refactored formulation types for better compatibility with PowerModelsDistribution constraints/variables
- Removed unused data functions and variables / constraints
- Refactored JSON schemas for easier versioning
- Updated to PowerModelsStability v0.3
- Updated to PowerModelsProtection v0.5
- Updated to PowerModelsDistribution v0.14.1
- Added `Microgrid networks` under analysis to be included in `Device action timeline`
- Added capability to control certain objective terms via settings schema / CLI runtime arguments: `apply_switch_scores` and `disable_switch_penalty`
- Added capability to control certain constraints via settings schema / CLI runtime arguments: `disable_radial_constraint` and `disable_block_isolation`
- Removed solution degeneracy in the switching problem by adjusting switch scores to include line losses from their respectively blocks
- Updated IEEE13 case to have more features, better microgrid networking
- Added nonlinear switching problems (ACPU, ACRU) (experimental)
- Added phase unbalance constraint for storage power input/output (experimental)
- Added schema for output data for use in protection optimization
- Fixed bug in stability analysis where there was an error if the inverter object was disabled (now filters out disabled inverters)
- Added constraint for radial topology
- Updated "global" objective to include generator cost
- Updated "global" algorithm to be the default
- Add `microgrid_network_timeline` for analyzing when microgrids network
- Separate global and iterative switching algorithm objective functions
- Updated to use Graphs instead of LightGraphs (LightGraphs was archived)
- Fixed bug in Distributed usage, where running on multiple workers but not intending to run distributed algorithm
- Added Distributed computing options for fault studies and stability analysis to significantly speed up these processes
- Updated minimum Julia version to 1.6 (LTS)
- Refactored imports to be better organized and explained
- Fixed bug in `build_settings_file` where voltage source buses where being assigned voltage bounds `0 < |V| < Inf`
- Added Hwloc.jl as dependency and `System metadata`, which includes information about the platform, cpu type, number of physical and logical cores, available threads, processors, and Julia version to output schema
- Added `Microgrid customers (%)`, `Bonus customers via microgrid (%)`, `Feeder customers (%)`, and `Total customers (%)` to `Load served` output schema
- Fixed bug in `get_timestep_voltage_statistics` where per-unit conversion was failing for voltages

## v2.0.0

- Fixed `get_timestep_storage_soc` to alway return a non-NaN value if storage exists in the system
- Updated stability problem data model preparation
- Linearized quadratic and on_off mixed integer constraints
- Added new on_off constraints for storage and transformers
- Refactored constraint functions into different files
- Added "Total load (%)" statistic to output schema
- Updated Fault currents schema to match faults input schema
- Added new microgrids statistics algorithm
- Updated fault problem to prune buses that are missing from problem to avoid data issues
- Tuned default solver instance settings for new problem definitions
- Added helper function `build_settings_file` to aid in building a settings file specific to a network
- Added helper function `build_events_file` to aid in building a (very) simple events file specific to a network
- Added helper function `count_faults`
- Added runtime argument `fix-small-numbers` which will prune lengths, impendances, and admittances that are especially small to improve solver performance
- Refactored to add new Switch formulation types and structs, to kept ONM better separated from PowerModelsDistribution
- Adjusted objective function and ref to zero out empty load blocks weights
- Added objective function to maximize storage input (charging)
- Refactored to explicitly import InfrastructureModels and PolyhedralRelaxation
- Refactored to explicitly import/export some PowerModelsDistribution functions
- Added `"mip_solver_tol"` to settings schema
- Added addition fields for storage in settings schema
- Added `"fault studies metadata"` to ONM output schema
- Added support for "settings" (e.g., `sbase_default`) in settings schema / parsing
- Updated `z_block` variable start
- Added `variable_mc_load_power_on_off` to ensure pd/qd variables include zeros in bounds
- Added support for OLTC and CAPC in switching problem
- Added `constraint_mc_transformer_power_yy_on_off` due to infeasibility from OLTC with controls
- Updated constraint functions to use consistent variable naming scheme
- Added `constraint_mc_switch_state_on_off` and `constraint_mc_switch_power_on_off` for `NFAUPowerModel`
- Updated `apply_settings` to use `set_time_elapsed!` from PowerModelsDistribution
- Fixed `_find_nw_id_from_timestep` for updates from PowerModelsDistribution
- Added `JuMP.lower_bound(x)` and `JuMP.upper_bound(x)` for `x::Float64`
- Updated `constraint_mc_power_balance_shed` to be LP using McCormick envelopes
- Updated `constraint_switch_max_actions` to be LP using McCormick envelopes
- Fixed network data preparation for optimal dispatch from switching results
- Remove storage conversion hack for PowerModelsProtection, which now includes support for storage
- Added support for load `priority`, bus `microgrid_id` to switching problem
- Added `mn_opf_oltc_capc` problem for dispatch step
- Added `variable_mc_storage_indicator` due to overlap of `z_storage` with `z_block`
- Added LinearAlgebra (stdlib) dependency
- Fixed order of parsing in `entrypoint` (events should go _after_ settings)
- Add support for `null` values in settings schema, and new objects / fields
- Updated power variables to be `bounded=false` in the switching problem, and use ampacity constraints only instead
- Updated `sbase_default` to `1e3` to avoid convergence issues
- Updated to PowerModelsDistribution v0.12.0
- Added support for CapControl in switching algorithm
- Fixed bug in `build_solver_instances!` where if `"settings"` was still a String, building solvers would fail
- Fixed bug in events parser to make all `affected_asset` values lowercase after validation
- Fixed bug in events schema, where `affected_asset` needed to match `line\..+`, which excluded any capital letters in `line`
- Updated `_prepare_dispatch_data` to correctly disable all relevant components in shed blocks
- Fixed bug in Powerflow output where if objects were disabled (`"status" => DISABLED`) in the dispatch problem, due to being shed, they would not appear in the output. Now all objects in network will apear, with zeros when missing from the solution.
- Updated to PowerModelsDistribution v0.11.10
- Fixed bug in `get_timestep_fault_currents` where if faults was still a string (not parsed, as in the case of using the `skip` argument) there would be an error
- Fixed bug in `apply_events!`, and in particular `entrypoint` where if events were not defined, the algorithm would error

## v1.1.0

- Updated to PowerModelsDistribution v0.11.8
- Fixed typo in return type of `get_timestep_dispatch_optimization_metadata!`
- Refactored block isolation to ensure switches are open if the block indicators of connected blocks are different
- Refactored max switch actions to allow for unlimited switch opens (to shed load in emergencies)
- Refactored objective function to be a balance of block weight, switch score, switch change penalty, and generation cost
- Refactored to remove indicator constraint problems, and use the Big-M formulation of the indicator constraints by default (more stable)
- Refactored to have a unified block indicator variable/constraint model, instead of having separate indicator variables for each of bus, load, shunt, gen, and storage
- Added switch weights for use in objective function (to support switching where there is no loads on an intermediate bus)
- Added storage to the IEEE13 unit test case
- Fixed bug where if opt-dispatch results were not obtained and/or merged into the network data, `convert_storage!` would fail
- Adjusted defaults for Juniper and Gurobi solvers
- Fixed reference to `FOTUPowerModel` (should be `FOTRUPowerModel`)
- Updated to PowerModelsDistribution v0.11.7
- Added `"mip_solver_gap"` user option in settings schema
- Added `"Optimal dispatch metadata"` and `"Optimal switching metadata"` to the output schema
- Added arguments `--opt-switch-algorithm`, `--opt-switch-solver`, `--opt-disp-algorithm`
- Changed `optimize_dispatch!` function to not overwrite base network data by default
- Added `"mip_gap"` to the results dictionary, if it exists
- Updated defaults for bundled solvers
- Fixed bug in `get_timestep_switch_changes` where switch changes in the first step were not shown
- Fixed bug in logic of `get_timestep_device_actions`, simplified algorithm
- Added LightGraphs as a dependency
- Added new linear formulations from PowerModelsDistribution, FOT (First Order Taylor) and FBS (Forward-Backward Sweep)
- Added Enum strings to settings schema as possible inputs to properties that accept them, e.g., status, dispatchable, state, etc.
- Added `"cm_ub"` and `"cm_ub_b"` properties to the settings schema under switches
- Fixed bug where ENUMs were not being converted when loading from settings file
- Fixed bug where when collecting generation statistics, if voltage source was missing from solution `get_timestep_load_served` would error
- Fixed bug where when running analysis functions if `"bus"` was missing from solution then functions would error. Changed to return `NaN` values

## v1.0.1

- Fixed bug in entrypoint.jl where if `--gurobi` option was used, Gurobi.jl needed to be imported _before_ PowerModelsONM, but it wasn't
- Refactored max switch actions constraint
- Added new ref extension `ref_add_max_switch_actions!`, which will default to `Inf` if no `max_switch_actions` data is available in data model.
- Fixed passing of `max_switch_actions` data from eng to math data model (req. PMD v0.11.5+)
- Added a `--pretty-print` commandline argument to toggle pretty-printed json outputs
- Added `switch` information to Powerflow output, including real and reactive power flow, voltages, and connections, all on the from-side
- Added `connections`/`terminals` to Powerflow schema / outputs to make it easier to look up which value corresponds to which terminal
- Fixed bug in `analyze_results!` functions where if some parts of the algorithm was not run, analyzing results would error
- Fixed stats unit test where expected variance was too close to the allowed tolerance
- Fixed bug in `get_timestep_fault_currents` where there was a typo in the variable name for phase currents
- Added commandline argument `opt-disp-solver` to select which solver to use for optimal dispatch
- Added commandline argument `skip`, to enable skipping of some parts of the entrypoint algorithm

## v1.0.0

- Complete refactor of PowerModelsONM API
- Documentation of all functions and tutorials on usage now included
- IEEE13 modified feeder added for unit testing
- Gurobi removed as requirement, use Requires.jl to manage Gurobi GRB_ENV initialization
- Requires PowerModelsDistribution v0.11.4+
- Requires PowerModelsStability v0.2.1+
- Requires PowerModelsProtection v0.3.0+
- Adds JSONSchema, JuMP, ProgressMeter, Requires as dependencies
- Removes DataFrames, Gurobi, Memento, XLSX as dependencies
- Documenter build requires Pluto, Gumbo
- Update Dockerfile for docker image builds
- Update Makefile for easy testing and docs building
- Added new "Fault currents" to output json schema
- Added new "faults" to input json schema
- Removed "Protection settings" from output json schema
- Removed Manifest.toml from repo
- Updated events input json schema to remove "pre_event_actions" and "post_event_actions" (revisit in future update)
- Added runtime_arguments json schema for easier validation of inputs
- Added inverters input json schema to validate inverters for stability analysis
- Added settings input json schema for increased flexibility in defining network settings
- Updated output json schema to be more restrictive
- Improved logging experience, added --quiet flag
- Reorganized code to be more managable, removed functions that are now in PowerModelsDistribution
- Converted everything to use ENGINEERING model, instead of switching back and forth between MATHEMATICAL and ENGINEERING manually, significantly improving the user experience
- Updated load block calculation algorithm
- Added json schema validation functions, and `load_schema` function to automatically adjust refs
- Simplified storage conversion for PowerModelsProtection calculations to use ENGINEERING model
- Fixed bounds for switch power and state constraints for big-M formulation of the constraints
- Depreciated runtime arguments in favor of more concise ones, and added warnings and conversions for old arguments via `sanitize_args!`
- Refactored built-in solver creation to use Ipopt, Cbc, Juniper, Alpine, and Gurobi (if available)
- Removed optimal switching problems (no MLD)
- Renamed optimal switching mld problems to indicate if using indicator constraints, all remaining problems are mixed integer
- Added examples for unit tests for faults, events, settings, inverters json files
- Fix events getting overwritten in iterative osw_mld problem

## v0.4.0

- Fix bug in osw_mld problems when using open-source solvers
- Add support for timesteps in events being specified as integers
- Updated weights in objective for osw_mld_mi problem
- Un-relax on/off switch constraints in osw_mld_mi problem
- Updated propagate_switch_changes! to black-out load block buses that are isolated
- Add "Switch changes" to output specification
- Update load shed update function to use status instead of pd/qd (only needed with continuous sheds)
- Add cli arguments for voltage bounds and clpu-factor
- Adjust default voltage magnitude (+-0.2) and voltage angle difference (+-5deg) bounds
- Fix switch map function (was grabbing wrong math id)
- Add helper function to adjust line limits
- Fix sign of storage outputs
- Updated output specification documentation
- Add initial support for cold-load-pickup, with helper functions for calculating load blocks
- Add constraint for maximum allowed switching actions per timestep
- Fix bug in load served stats function when no DER in network
- Add shedded loads to Device action timeline
- Add runtime arguments to output
- Add support for Gurobi solver (may break CI)
- mld problem upgrade, changes from "simple" mld problem to variant of full mld problem in PowerModelsDistribution
- mld+osw objective tuning: disincentivize switching from current configuration
- updated protections settings file parser for new format
- refactored Powerflow output to be list of dicts, like the other output formats
- added generation/storage setpoints to Powerflow output: "real power setpoint (kW)" and "reactive power setpoint (kVar)"

## v0.3.3

- fixed bug in fault studies algorithm where storage->gen objects were missing vbase and zx parameters
- switched back to PowerModelsProtection#master from dev branch
- updated log messages, and added LoggingExtras to control Juniper logging

## v0.3.2

- added voltage angle difference bounds on all lines
- added a storage->gen converter for fault analysis (storage not supported)
- updated to latest version of PowerModelsProtection

## v0.3.1

- fixed bug in argument parser where things with no defaults would default to `nothing`
- fixed bug in stability analysis loop that would cause error if no inverter file was specified

## v0.3.0

- added PowerModelsProtection fault studies
- added PowerModelsStability small signal stability analysis
- combined switching with load shed problem to perform simultaneously
- adjusted switching objective function to focus on load shed for now

## v0.2.0

- added optimal switching problem
- added protection settings loading and outputs

## v0.1.0

- Initial release
