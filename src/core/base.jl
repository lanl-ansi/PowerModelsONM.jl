"lower_bound helper function for constant values"
JuMP.lower_bound(x::Number) = x

"upper_bound helper function for constant values"
JuMP.upper_bound(x::Number) = x

"variable_domain helper function for constant values"
_IM.variable_domain(var::Number) = (var, var)

"has_lower_bound helper function for constant values"
JuMP.has_lower_bound(x::Number) = true

"has_upper_bound helper function for constant values"
JuMP.has_upper_bound(x::Number) = true

"is_binary helper function for constant values"
JuMP.is_binary(x::Number) = false

"""
    JuMP.lower_bound(x::JuMP.AffExpr)

lower_bound helper function for Affine Expression variables
"""
function JuMP.lower_bound(x::JuMP.AffExpr)
    lb = []
    for (k, v) in x.terms
        push!(lb, JuMP.lower_bound(k) * v)
    end
    return sum(lb)
end

"""
    JuMP.upper_bound(x::JuMP.AffExpr)

upper_bound helper function for Affine Expression variables
"""
function JuMP.upper_bound(x::JuMP.AffExpr)
    ub = []
    for (k, v) in x.terms
        push!(ub, JuMP.upper_bound(k) * v)
    end
    return sum(ub)
end

"has_lower_bound helper function for Affine Expression variables"
JuMP.has_lower_bound(x::JuMP.AffExpr) = all(JuMP.has_lower_bound(k) for (k, _) in x.terms)

"has_upper_bound helper function for Affine Expression variables"
JuMP.has_upper_bound(x::JuMP.AffExpr) = all(JuMP.has_upper_bound(k) for (k, _) in x.terms)

"is_binary helper function for Affine Expression variables"
JuMP.is_binary(x::JuMP.AffExpr) = false

"""
    _IM.variable_domain(var::JuMP.AffExpr)

Computes the valid domain of a given JuMP variable taking into account bounds
and the varaible's implicit bounds (e.g., binary).
"""
function _IM.variable_domain(var::JuMP.AffExpr)
    lb = -Inf
    if JuMP.has_lower_bound(var)
        lb = JuMP.lower_bound(var)
    end
    if JuMP.is_binary(var)
        lb = max(lb, 0.0)
    end

    ub = Inf
    if JuMP.has_upper_bound(var)
        ub = JuMP.upper_bound(var)
    end
    if JuMP.is_binary(var)
        ub = min(ub, 1.0)
    end

    return (lower_bound=lb, upper_bound=ub)
end

"""
    _IM.relaxation_product(m::JuMP.Model, x::JuMP.AffExpr, y::JuMP.VariableRef, z::JuMP.VariableRef;
        default_x_domain::Tuple{Real,Real}=(-Inf, Inf),
        default_y_domain::Tuple{Real,Real}=(-Inf, Inf)
    )

general relaxation of binlinear term (McCormick) for Affine Expressions and VariableRefs

```julia
z >= JuMP.lower_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.lower_bound(x)*JuMP.lower_bound(y)
z >= JuMP.upper_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.upper_bound(x)*JuMP.upper_bound(y)
z <= JuMP.lower_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.lower_bound(x)*JuMP.upper_bound(y)
z <= JuMP.upper_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.upper_bound(x)*JuMP.lower_bound(y)
```
"""
function _IM.relaxation_product(m::JuMP.Model, x::JuMP.AffExpr, y::JuMP.VariableRef, z::JuMP.VariableRef;
                                default_x_domain::Tuple{Real,Real}=(-Inf, Inf),
                                default_y_domain::Tuple{Real,Real}=(-Inf, Inf))
    x_lb, x_ub = _IM.variable_domain(x)
    y_lb, y_ub = _IM.variable_domain(y)

    x_lb = !isfinite(x_lb) ? default_x_domain[1] : x_lb
    x_ub = !isfinite(x_ub) ? default_x_domain[2] : x_ub
    y_lb = !isfinite(y_lb) ? default_y_domain[1] : y_lb
    y_ub = !isfinite(y_ub) ? default_y_domain[2] : y_ub

    JuMP.@constraint(m, z >= x_lb * y + y_lb * x - x_lb * y_lb)
    JuMP.@constraint(m, z >= x_ub * y + y_ub * x - x_ub * y_ub)
    JuMP.@constraint(m, z <= x_lb * y + y_ub * x - x_lb * y_ub)
    JuMP.@constraint(m, z <= x_ub * y + y_lb * x - x_ub * y_lb)
end

@doc raw"""
    _IM.relaxation_product(m::JuMP.Model, x::Real, y::JuMP.VariableRef, z::JuMP.VariableRef)

general relaxation of binlinear term (McCormick) for Constants and VariableRefs

```julia
z >= JuMP.lower_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.lower_bound(x)*JuMP.lower_bound(y)
z >= JuMP.upper_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.upper_bound(x)*JuMP.upper_bound(y)
z <= JuMP.lower_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.lower_bound(x)*JuMP.upper_bound(y)
z <= JuMP.upper_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.upper_bound(x)*JuMP.lower_bound(y)
```
"""
function _IM.relaxation_product(m::JuMP.Model, x::Real, y::JuMP.VariableRef, z::JuMP.VariableRef)
    x_lb, x_ub = _IM.variable_domain(x)
    y_lb, y_ub = _IM.variable_domain(y)

    JuMP.@constraint(m, z >= x_lb * y + y_lb * x - x_lb * y_lb)
    JuMP.@constraint(m, z >= x_ub * y + y_ub * x - x_ub * y_ub)
    JuMP.@constraint(m, z <= x_lb * y + y_ub * x - x_lb * y_ub)
    JuMP.@constraint(m, z <= x_ub * y + y_lb * x - x_ub * y_lb)
end

"recursive dictionary merge, similar to update data"
recursive_merge_including_vectors(x::AbstractDict...) = merge(recursive_merge_including_vectors, x...)

"recursive vector merge, similar to update data"
recursive_merge_including_vectors(x::AbstractVector...) = cat(x...; dims=1)

"recursive other merge"
recursive_merge_including_vectors(x...) = x[end]

"recursive dictionary merge, similar to update data, with vectors getting overwritten instead of appended"
recursive_merge(x::AbstractDict...) = merge(recursive_merge, x...)

"recursive other merge, with vectors getting overwritten instead of appended"
recursive_merge(x...) = x[end]

"""
    recursive_merge_timesteps(x::T, y::U)::promote_type(T,U) where {T<: AbstractVector,U<: AbstractVector}

helper function to recursively merge timestep vectors (e.g., of dictionaries)
"""
function recursive_merge_timesteps(x::T, y::U)::promote_type(T, U) where {T<:AbstractVector,U<:AbstractVector}
    if !isempty(x)
        @assert length(x) == length(y) "cannot combine vectors of different lengths"
        new = promote_type(T, U)()
        for (_x, _y) in zip(x, y)
            push!(new, recursive_merge_including_vectors(_x, _y))
        end
        return new
    else
        return y
    end
end


"""
"""
function set_dict_value!(a::Dict, key::String, value::Any)
    a[key] = value
end


"""
"""
function set_dict_value!(a::T, path::Tuple{Vararg{String}}, value::Any) where T <: Dict
    if !haskey(a, first(path))
        a[first(path)] = T()
    end

    new_path = length(path) == 2 ? path[2] : path[2:end]

    set_dict_value!(a[first(path)], new_path, value)
end


"""
"""
function convert(value::Any, path::Tuple{Vararg{String}}=tuple())
    if haskey(settings_conversions, path)
        value = settings_conversions[path](value)
    end

    if isa(value, String) && startswith(value, ":")
        value = Symbol(value[2:end])
    end

    if isa(value, Vector) && all(isa.(value, String)) && all(startswith.(value,":"))
        value = Symbol[Symbol(v[2:end]) for v in value]
    end

    return value
end
