# PowerModelsONM Changelog

## staged

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
