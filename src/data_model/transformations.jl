# TODO: Remove once storage supported in IVRU in PMP
"""
    convert_storage!(nw::Dict{String,Any})

Helper function for PowerModelsProtection fault studies to convert storage to generators in a subnetwork;
PowerModelsProtection currently does not support storage object constraints / variables, so this is a
workaround until those constraints/variables are added.

This works on `ENGINEERING` subnetworks (not multinetworks).
"""
function convert_storage!(nw::Dict{String,Any})
    for (i, strg) in get(nw, "storage", Dict())
        nw["generator"]["storage.$i"] = Dict{String,Any}(
            "bus" => strg["bus"],
            "connections" => strg["connections"],
            "configuration" => strg["configuration"],
            "control_mode" => get(strg, "control_mode", PMD.FREQUENCYDROOP),
            "status" => strg["status"],

            "pg_lb" => -strg["ps"] .- 1e-9,
            "pg_ub" => -strg["ps"] .+ 1e-9,
            "qg_lb" => -strg["qs"] .- 1e-9,
            "qg_ub" => -strg["qs"] .+ 1e-9,

            "source_id" => strg["source_id"],
            "zx" => zeros(length(strg["connections"])),
        )
        delete!(nw["storage"], i)
    end
    delete!(nw, "storage")
end
