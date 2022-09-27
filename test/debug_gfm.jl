using PowerModelsONM

import Gurobi

GRB_ENV = Gurobi.Env()
solver = optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV), settings["solvers"]["Gurobi"]...)

eng = parse_file("test/data/ieee13_feeder.dss")

settings = parse_settings("test/data/ieee13_settings.json")
settings["solvers"]["Gurobi"]["OutputFlag"] = 1
settings["solvers"]["useGurobi"] = true

eng_s = apply_settings(eng, settings)

eng_s["time_elapsed"] = 1.0
eng_s["switch_close_actions_ub"] = Inf

for sw in values(eng_s["switch"])
    sw["state"] = OPEN
    sw["dispatchable"] = NO
end

r = solve_block_mld(eng_s, PMD.LPUBFDiagPowerModel, solver)
