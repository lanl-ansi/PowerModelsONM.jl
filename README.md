# PowerModelsONM

An Optmization library for the operation and restoration of electric power distribution feeders featuring networked microgrids

|                                      **Documentation**                                       |                                          **Build Status**                                          |
| :------------------------------------------------------------------------------------------: | :------------------------------------------------------------------------------------------------: |
| [![docs-stable][docs-stable-img]][docs-stable-url] [![docs-dev][docs-dev-img]][docs-dev-url] | [![github-actions][github-actions-img]][github-actions-url] [![codecov][codecov-img]][codecov-url] |

This package combines various packages in the [InfrastructureModels.jl](https://github.com/lanl-ansi/InfrastructureModels.jl) optimization library ecosystem, particularly those related to electric power distribution.

PowerModelsONM focuses on optimizing the operations and restoration of phase unbalanced (multiconductor) distribution feeders that feature multiple grid-forming generation assets such as solar PV, deisel generators, energy storage, etc. Phase unbalanced modeling is achieved using [PowerModelsDistribution](https://github.com/lanl-ansi/PowerModelsDistribution.jl). This library features a custom implementation of an optimal switching / load shedding (mld) problem. See [documentation][docs-stable-url] for more details.

## Installation

To install PowerModelsONM, use the built-in Julia package manager

```julia
pkg> add PowerModelsONM
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add("PowerModelsONM")
```

or to develop the package,

```julia
julia> import Pkg; Pkg.develop(Pkg.PackageSpec(; name="PowerModelsONM", url="https://github.com/lanl-ansi/PowerModelsONM.jl"))
```

## Questions and contributions

Usage questions can be posted on the [Github Discussions forum][discussions-url].

Contributions, feature requests, and suggestions are welcome; please open an [issue][issues-url] if you encounter any problems. The [contributing page][contrib-url] has guidelines that should be followed when opening pull requests and contributing code.

This software was supported by the Resilient Operations of Networked Microgrids project funded by the U.S. Department of Energy's Microgrid Research and Development Program.

## R&D100 2023 Winner

PowerModelsONM won an R&D100 Award in 2023

| **Award**                                                                                                                                              | **Entry**                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [<img src="https://lanl-ansi.github.io/PowerModelsONM.jl/dev/assets/RD100_2023_Winner_Logo.png" width=200 alt="R&D100 2023 Winner Logo" />][rd100-url] | **PowerModelsONM: Optimizing Operations of Networked Microgrids for Resilience** <br />Los Alamos National Laboratory, National Renewable Energy Laboratory, Sandia National Laboratories, National Rural Electric Cooperative Association |

You can find a YouTube video that accompanied our entry below for more information on PowerModelsONM:

[![R&D 100 - PowerModels ONM](https://img.youtube.com/vi/D5k-lMicMPM/0.jpg)](https://www.youtube.com/watch?v=D5k-lMicMPM)

## Citing PowerModelsONM

If you find PowerModelsONM useful for your work, we kindly request that you cite the following [publication](https://doi.org/10.1109/TSG.2022.3208508):

```bibtex
@ARTICLE{9897093,
  author={Fobes, David M. and Nagarajan, Harsha and Bent, Russell},
  journal={IEEE Transactions on Smart Grid},
  title={Optimal Microgrid Networking for Maximal Load Delivery in Phase Unbalanced Distribution Grids: A Declarative Modeling Approach},
  year={2023},
  volume={14},
  number={3},
  pages={1682-1691},
  doi={10.1109/TSG.2022.3208508}
}
```

## License

This code is provided under a BSD license as part of the Multi-Infrastructure Control and Optimization Toolkit (MICOT) project, LA-CC-13-108.

[docs-dev-img]: https://github.com/lanl-ansi/PowerModelsONM.jl/workflows/Documentation/badge.svg
[docs-dev-url]: https://lanl-ansi.github.io/PowerModelsONM.jl/dev
[docs-stable-img]: https://github.com/lanl-ansi/PowerModelsONM.jl/workflows/Documentation/badge.svg
[docs-stable-url]: https://lanl-ansi.github.io/PowerModelsONM.jl/stable
[github-actions-img]: https://github.com/lanl-ansi/PowerModelsONM.jl/workflows/CI/badge.svg
[github-actions-url]: https://github.com/lanl-ansi/PowerModelsONM.jl/actions/workflows/ci.yml
[codecov-img]: https://codecov.io/gh/lanl-ansi/PowerModelsONM.jl/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/lanl-ansi/PowerModelsONM.jl
[contrib-url]: https://lanl-ansi.github.io/PowerModelsONM.jl/stable/developer/contributing.html
[discussions-url]: https://github.com/lanl-ansi/PowerModelsONM.jl/discussions
[issues-url]: https://github.com/lanl-ansi/PowerModelsONM.jl/issues
[rd100-url]: https://www.rdworldonline.com/rd-100-winners-for-2023-are-announced-2/
