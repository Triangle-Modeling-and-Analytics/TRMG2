/*

*/

Macro "Accessibility" (Args)

    RunMacro("Gini-Simpson Diversity Index", Args)

    return(1)
endmacro

/*

*/

Macro "Gini-Simpson Diversity Index" (Args)

    se_file = Args.SE
    rate_file = Args.[GS Rates]

    rate_vw = OpenTable("rates", "CSV", {rate_file})
    {v_fields, v_rates} = GetDataVectors(
        rate_vw + "|",
        {"Field", "Value"},
    )
    CloseView(rate_vw)

    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"GSIndex", "Real", 10, 2, , , , "Gini-Simpson Diversity Index|(Measures mixed use)"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    SetView(se_vw)
    internal_set = CreateSet("internal")
    SelectByQuery(internal_set, "several", "Select * where Type = 'Internal'")
    // Calculate g and total g for each zone
    g = null
    for i = 1 to v_fields.length do
        field = v_fields[i]
        rate = v_rates[i]

        v = nz(GetDataVector(se_vw + "|" + internal_set, field, ))
        g.(field) = v * rate
        if i = 1 then total_g = Vector(v.length, "real", {Constant: 0})
        total_g = total_g + g.(field)
    end
    total_g = if total_g = 0 then -1 else total_g
    // Calculate the sum of the ratios squared: Sum((g/total_g)^2)
    sum_ratio_squared = Vector(total_g.length, "real", {Constant: 0})
    for i = 1 to v_fields.length do
        field = v_fields[i]
        rate = v_rates[i]

        sum_ratio_squared = sum_ratio_squared + pow(g.(field) / total_g, 2)
    end
    sum_ratio_squared = if sum_ratio_squared = 0 then .5 else sum_ratio_squared
    // Calculate final index value for each zone
    v_index = 1 - sum_ratio_squared
    SetDataVector(se_vw + "|" + internal_set, "GSIndex", v_index, )

    CloseView(se_vw)
endmacro