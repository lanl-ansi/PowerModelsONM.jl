# [Variables and Constraints](@id VarConAPI)

## Variables

```@autodocs
Modules = [PowerModelsONM]
Private = false
Order = [:function]
Pages = ["variable.jl", "form/acp.jl", "form/acr.jl", "form/apo.jl", "form/lindistflow.jl", "form/shared.jl"]
Filter = t -> startswith(string(t), "variable_")
```

## Constraints

```@autodocs
Modules = [PowerModelsONM]
Private = false
Order = [:function]
Pages = ["constraint_template.jl", "constraint.jl", "form/acp.jl", "form/acr.jl", "form/apo.jl", "form/lindistflow.jl", "form/shared.jl"]
Filter = t -> startswith(string(t), "constraint_")
```

## Objectives

```@autodocs
Modules = [PowerModelsONM]
Private = false
Order = [:function]
Pages = ["objective.jl"]
```

## Ref extensions

```@autodocs
Modules = [PowerModelsONM]
Private = false
Order = [:function]
Pages = ["ref.jl"]
```
