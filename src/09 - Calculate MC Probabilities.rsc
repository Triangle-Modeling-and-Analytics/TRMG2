/*
Calculates aggregate mode choice probabilities between zonal ij pairs
*/

Macro "Calculate MC Probabilities" (Args)

    RunMacro("Create MC Features", Args)

    return(1)
endmacro

/*
Creates any additional fields/cores needed by the mode choice models
*/

Macro "Create MC Features" (Args)

    se_file = Args.SE
    hh_file = Args.Households

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    se_vw = OpenTable("se", "FFB", {se_file})
    hh_fields = {{"HiIncome", "Integer", 10, ,,,, "IncomeCategory > 2"}}
    RunMacro("Add Fields", {view: hh_vw, a_fields: hh_fields})
    se_fields = {{"HiIncomePct", "Real", 10, 2,,,, "Percentage of households with IncomeCategory > 2"}}
    RunMacro("Add Fields", {view: se_vw, a_fields: se_fields})

    v_inc_cat = GetDataVector(hh_vw + "|", "IncomeCategory", )
    v_hi = if v_inc_cat > 2 then 1 else 0
    SetDataVector(hh_vw + "|", "HiIncome", v_hi, )
    grouped_vw = AggregateTable(
        "grouped_vw", hh_vw + "|", "FFB", GetTempFileName(".bin"), "ZoneID", 
        {{"HiIncome", "AVG", }}, {"Missing As Zero": "true"}
    )
    jv = JoinViews("jv", se_vw + ".TAZ", grouped_vw + ".ZoneID", )
    v = nz(GetDataVector(jv + "|", "Avg HiIncome", ))
    SetDataVector(jv + "|", "HiIncomePct", v, )

    CloseView(jv)
    CloseView(grouped_vw)
    CloseView(se_vw)
    CloseView(hh_vw)
endmacro