# PowerModelsONM Changelog

## staged

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
