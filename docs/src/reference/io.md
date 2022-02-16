# [IO](@id IOAPI)

## Parsers

```@docs
parse_network
parse_events
parse_settings
parse_faults
parse_inverters
get_protection_network_model
get_protection_network_model!
get_timestep_bus_types
get_timestep_bus_types!
```

## Builders

```@docs
build_events_file
build_settings_file
```

## Applicators

```@docs
apply_events
apply_events!
apply_settings
apply_settings!
initialize_output
get_protection_network_model
get_protection_network_model!
get_timestep_bus_types
get_timestep_bus_types!
```

## Writers

```@docs
write_json
build_settings_file
build_events_file
```

## JSON Schema

```@docs
load_schema
```

```@autodocs
Modules = [PowerModelsONM]
Private = false
Order = [:function]
Pages = ["checks.jl"]
```
