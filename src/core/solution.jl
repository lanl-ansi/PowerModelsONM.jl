""
function transform_solutions(sol_math::Dict{String,Any}, data_math::Dict{String,Any})::Tuple{Dict{String,Any},Dict{String,Any}}
    sol_pu = PMD.transform_solution(sol_math, data_math; make_si=false)
sol_si = PMD.transform_solution(sol_math, data_math; make_si=true)

    return sol_pu, sol_si
end


""
function apply_load_shed!(mn_data_math::Dict{String,Any}, result::Dict{String,Any})
    for (n,nw) in result["solution"]["nw"]
        for (l, load) in get(nw, "load", Dict())
            mn_data_math["nw"][n]["load"][l]["pd_nom"] = load["pd"]
            mn_data_math["nw"][n]["load"][l]["qd_nom"] = load["qd"]

            mn_data_math["nw"][n]["load"][l]["pd"] = load["pd"]
            mn_data_math["nw"][n]["load"][l]["qd"] = load["qd"]
        end
    end
end
