"gen connections adaptation of min fuel cost polynomial linquad objective"
function objective_switch(pm::PMD._PM.AbstractPowerModel; report::Bool=true)
    gen_cost = Dict()
    for (n, nw_ref) in PMD.nws(pm)
        for (i,gen) in nw_ref[:gen]
            pg = sum( PMD.var(pm, n, :pg, i)[c] for c in gen["connections"] )

            if length(gen["cost"]) == 1
                gen_cost[(n,i)] = gen["cost"][1]
            elseif length(gen["cost"]) == 2
                gen_cost[(n,i)] = gen["cost"][1]*pg + gen["cost"][2]
            elseif length(gen["cost"]) == 3
                if gen["cost"][1] == 0
                    gen_cost[(n,i)] = gen["cost"][2]*pg + gen["cost"][3]
                else
                    gen_cost[(n,i)] = gen["cost"][1]*pg^2 + gen["cost"][2]*pg + gen["cost"][3]
                end
            else
                gen_cost[(n,i)] = 0.0
            end
        end
    end

    return PMD.JuMP.@objective(pm.model, Min,
        sum(
            sum( gen_cost[(n,i)] for (i,gen) in nw_ref[:gen] ) +
            sum( PMD.var(pm, n, :switch_state, l) for l in PMD.ids(pm, n, :switch_dispatchable))
        for (n, nw_ref) in PMD.nws(pm))
    )
end
