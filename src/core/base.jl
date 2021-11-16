"helper function for constant pd/qd variables"
function JuMP.lower_bound(x::Float64)
    return x
end


"helper function for constant pd/qd variables"
function JuMP.upper_bound(x::Float64)
    return x
end

_IM.variable_domain(var::Float64) = (var, var)

JuMP.has_lower_bound(x::Float64) = true
JuMP.has_upper_bound(x::Float64) = true
JuMP.is_binary(x::Float64) = false


"helper function for Affine Expression pd/qd variables"
function JuMP.lower_bound(x::JuMP.AffExpr)
    lb = []
    for (k,v) in x.terms
        push!(lb, JuMP.lower_bound(k) * v)
    end
    sum(lb)
end


"helper function for Affine Expression pd/qd variables"
function JuMP.upper_bound(x::JuMP.AffExpr)
    ub = []
    for (k,v) in x.terms
        push!(ub, JuMP.upper_bound(k) * v)
    end
    sum(ub)
end


JuMP.has_lower_bound(x::JuMP.AffExpr) = all(JuMP.has_lower_bound(k) for (k,_) in x.terms)
JuMP.has_upper_bound(x::JuMP.AffExpr) = all(JuMP.has_upper_bound(k) for (k,_) in x.terms)
JuMP.is_binary(x::JuMP.AffExpr) = false


"""
Computes the valid domain of a given JuMP variable taking into account bounds
and the varaible's implicit bounds (e.g. binary).
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
general relaxation of binlinear term (McCormick)
```
z >= JuMP.lower_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.lower_bound(x)*JuMP.lower_bound(y)
z >= JuMP.upper_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.upper_bound(x)*JuMP.upper_bound(y)
z <= JuMP.lower_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.lower_bound(x)*JuMP.upper_bound(y)
z <= JuMP.upper_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.upper_bound(x)*JuMP.lower_bound(y)
```
"""
function _IM.relaxation_product(m::JuMP.Model, x::JuMP.AffExpr, y::JuMP.VariableRef, z::JuMP.VariableRef; default_x_domain::Tuple{Real,Real}=(-Inf,Inf), default_y_domain::Tuple{Real,Real}=(-Inf,Inf))
    x_lb, x_ub = _IM.variable_domain(x)
    y_lb, y_ub = _IM.variable_domain(y)

    x_lb = !isfinite(x_lb) ? default_x_domain[1] : x_lb
    x_ub = !isfinite(x_ub) ? default_x_domain[2] : x_ub
    y_lb = !isfinite(y_lb) ? default_y_domain[1] : y_lb
    y_ub = !isfinite(y_ub) ? default_y_domain[2] : y_ub

    JuMP.@constraint(m, z >= x_lb*y + y_lb*x - x_lb*y_lb)
    JuMP.@constraint(m, z >= x_ub*y + y_ub*x - x_ub*y_ub)
    JuMP.@constraint(m, z <= x_lb*y + y_ub*x - x_lb*y_ub)
    JuMP.@constraint(m, z <= x_ub*y + y_lb*x - x_ub*y_lb)
end


"""
general relaxation of binlinear term (McCormick)
```
z >= JuMP.lower_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.lower_bound(x)*JuMP.lower_bound(y)
z >= JuMP.upper_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.upper_bound(x)*JuMP.upper_bound(y)
z <= JuMP.lower_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.lower_bound(x)*JuMP.upper_bound(y)
z <= JuMP.upper_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.upper_bound(x)*JuMP.lower_bound(y)
```
"""
function _IM.relaxation_product(m::JuMP.Model, x::Float64, y::JuMP.VariableRef, z::JuMP.VariableRef)
    x_lb, x_ub = _IM.variable_domain(x)
    y_lb, y_ub = _IM.variable_domain(y)

    JuMP.@constraint(m, z >= x_lb*y + y_lb*x - x_lb*y_lb)
    JuMP.@constraint(m, z >= x_ub*y + y_ub*x - x_ub*y_ub)
    JuMP.@constraint(m, z <= x_lb*y + y_ub*x - x_lb*y_ub)
    JuMP.@constraint(m, z <= x_ub*y + y_lb*x - x_ub*y_lb)
end
