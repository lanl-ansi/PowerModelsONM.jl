# PowerModelsONM

This package will combine various parts of the PowerModelsDistribution ecosystem to support the operation of networked microgrids.

Currently, only PowerModelsDistribution is being used in this prototype, so no actions are being performed other than generator dispatch (opf), and `"Device action timeline"` in the output specification will not be populated yet. Also, no additional inputs are needed yet other than a network case.

Also, note that Manifest.toml is currently needed in the repository because we are using a development branch of PowerModelsDistribution, but it will not be needed in the future.

## Running ONM

To run this code, execute from the command line:

```bash
julia --project="path/to/PowerModelsONM" path/to/PowerModelsONM/cli/entrypoint.jl -n "path/to/Master.dss" -o "path/to/output.json"
```

This will execute with the following defaults:

- `"lindistflow"` formulation (LPUBFDiagPowerModel / LinDist3FlowPowerModel)
- `"opf"` problem (Optimal Power Flow)
- `1e-6` tolerance for Ipopt

### Options

- `-n` : path to network case (Master.dss)
- `-o` : path to output file (json)
- `-p` : problem type
  - optimal power flow ("opf": default, recommended),
  - maximal load delivery ("mld": will load shed, for debugging networks),
  - power flow ("pf": no multinetwork equivalent, not for time series data)
- `-f` : formulation
  - LinDistFlow approximation (`"lindistflow"`: default, recommended for speed, medium accuracy),
  - AC-rectangular (`"acr"`: slow, most accurate),
  - AC-polar (`"acp"`: slow, most accurate), or
  - network flow approximation (`"nfa"`: recommended for debugging, very fast, no voltages)
- `-v` : verbose output to command line
- `-solver-tolerance` : default `1e-6`, for debugging, shouldn't need to change
- `--e` : exports the full results dict to the specified path

### Recommended networks

From PowerModelsRONMLib, use the following networks:

- `iowa240/high_side_equiv` (no time series, for testing)
- `iowa240/der` (time series for solar only)
- `iowa240/time_series/03_05` (full time series, loads and PV)
- `iowa240/time_series/03_06` (full time series, loads and PV)
- `iowa240/time_series/03_15` (full time series, loads and PV)

## Output format

The current output format is the follow, which gets written to a json file:

```julia
Dict{String,Any}(
    "Simulation time steps" => Vector{String}(["$t" for t in timestamps]]),
    "Load served" => Dict{String,Vector{Real}}(
        "Feeder load (%)" => Vector{Real}([]),
        "Microgrid load (%)" => Vector{Real}([]),
        "Bonus load via microgrid (%)" => Vector{Real}([]),
    ),
    "Generator profiles" => Dict{String,Vector{Real}}(
        "Grid mix (kW)" => Vector{Real}([]),
        "Solar DG (kW)" => Vector{Real}([]),
        "Energy storage (kW)" => Vector{Real}([]),
        "Diesel DG (kW)" => Vector{Real}([]),
    ),
    "Voltages" => Dict{String,Vector{Real}}(
        "Min voltage (p.u.)" => Vector{Real}([]),
        "Mean voltage (p.u.)" => Vector{Real}([]),
        "Max voltage (p.u.)" => Vector{Real}([]),
    ),
    "Storage SOC (%)" => Vector{Real}([]),
    "Device action timeline" => Vector{Dict{String,Any}}([]),
    "Powerflow output" => Dict{String,Dict{String,Dict{String,Vector{Real}}}}(
        "$timestamp" => Dict{String,Dict{String,Vector{Real}}}(
            id => Dict{String,Vector{Real}}(
                "voltage (V)" => 0.0
            ) for (id,_) in buses
        ) for timestamp in timestampes
    ),
    "Summary statistics" => Dict{String,Any}(
        "Additional stats" => "TBD"
    ),
)
```

## Notes

The following warning messages can be ignored, these will be fixed in a later update to the base PowerModelsDistribution code:

```
WARNING: Method definition _objective_min_fuel_cost_polynomial_linquad(PowerModels.AbstractPowerModel) in module PowerModels at /Users/dfobes/.julia/packages/PowerModels/72tBz/src/core/objective.jl:334 overw
ritten in module PowerModelsDistribution at /Users/dfobes/.julia/packages/PowerModelsDistribution/WfxKs/src/core/objective.jl:115.
  ** incremental compilation may be fatally broken for this module **

WARNING: Method definition _objective_min_fuel_cost_polynomial_linquad##kw(Any, typeof(PowerModels._objective_min_fuel_cost_polynomial_linquad), PowerModels.AbstractPowerModel) in module PowerModels at /Users/dfobes/.julia/packages/PowerModels/72tBz/src/core/objective.jl:334 overwritten in module PowerModelsDistribution at /Users/dfobes/.julia/packages/PowerModelsDistribution/WfxKs/src/core/objective.jl:115.
  ** incremental compilation may be fatally broken for this module **
```

## License

This code is provided under a BSD license as part of the Multi-Infrastructure Control and Optimization Toolkit (MICOT) project, LA-CC-13-108.
