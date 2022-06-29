# GraphML Export

In PowerModelsONM we include a capability to export a network data structure as a graph, either nested, _i.e._, consisting of subgraphs of load blocks or unnested in the [GraphML format](http://graphml.graphdrawing.org/), which is an XML format.

We also include in the `examples/data` folder a suggested ["Configuration"](https://github.com/lanl-ansi/PowerModelsONM.jl/tree/main/examples/data/onm_suggested.cnfx) for use in the [yEd](https://www.yworks.com/products/yed/download) Properties Manager. This configuration was used to construct the examples below.

## Unnested Graph

To export an unnested graph

```julia
import PowerModelsONM as ONM
onm_path = joinpath(dirname(pathof(ONM)), "../examples/data")
eng = ONM.PMD.parse_file(joinpath(onm_path, "network.ieee13.dss"))
save_graphml("unnested_ieee13.graphml", eng; type="unnested")
```

Below is what this exported graphml looks like after being loaded in yEd, the ONM recommended properaties applied, and the Orthogonal - Classic layout applied.

![Unnested IEEE13 Graph](../assets/unnested_ieee13.svg)

## Nested Graph

To export an nested graph

```julia
import PowerModelsONM as ONM
onm_path = joinpath(dirname(pathof(ONM)), "../examples/data")
eng = ONM.PMD.parse_file(joinpath(onm_path, "network.ieee13.dss"))
save_graphml("nested_ieee13.graphml", eng; type="nested")
```

Below is what this exported graphml looks like after being loaded in yEd, the ONM recommended properaties applied, and the Orthogonal - Classic layout applied.

![Nested IEEE13 Graph](../assets/nested_ieee13.svg)
