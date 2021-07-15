/*
Calculates aggregate mode choice probabilities between zonal ij pairs
*/

Macro "Calculate MC Probabilities" (Args)

    RunMacro("Create MC Features", Args)
    RunMacro("Calculate MC", Args)

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
    hh_fields = {
        {"HiIncome", "Integer", 10, ,,,, "IncomeCategory > 2"},
        {"HHSize1", "Integer", 10, ,,,, "HHSize = 1"},
        {"LargeHH", "Integer", 10, ,,,, "HHSize > 2"}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: hh_fields})
    se_fields = {
        {"HiIncomePct", "Real", 10, 2,,,, "Percentage of households where IncomeCategory > 2"},
        {"HHSize1Pct", "Real", 10, 2,,,, "Percentage of households where HHSize = 1"},
        {"LargeHHPct", "Real", 10, 2,,,, "Percentage of households where HHSize > 1"}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: se_fields})

    {v_inc_cat, v_size} = GetDataVectors(hh_vw + "|", {"IncomeCategory", "HHSize"}, )
    data.HiIncome = if v_inc_cat > 2 then 1 else 0
    data.HHSize1 = if v_size = 1 then 1 else 0
    data.LargeHH = if v_size > 2 then 1 else 0
    SetDataVectors(hh_vw + "|", data, )
    grouped_vw = AggregateTable(
        "grouped_vw", hh_vw + "|", "FFB", GetTempFileName(".bin"), "ZoneID", 
        {{"HiIncome", "AVG", }, {"HHSize1", "AVG", }, {"LargeHH", "AVG"}}, 
        {"Missing As Zero": "true"}
    )
    jv = JoinViews("jv", se_vw + ".TAZ", grouped_vw + ".ZoneID", )
    v = nz(GetDataVector(jv + "|", "Avg HiIncome", ))
    SetDataVector(jv + "|", "HiIncomePct", v, )
    v = nz(GetDataVector(jv + "|", "Avg HHSize1", ))
    SetDataVector(jv + "|", "HHSize1Pct", v, )
    v = nz(GetDataVector(jv + "|", "Avg LargeHH", ))
    SetDataVector(jv + "|", "LargeHHPct", v, )

    CloseView(jv)
    CloseView(grouped_vw)
    CloseView(se_vw)
    CloseView(hh_vw)
endmacro

/*
Loops over purposes and preps options for the "MC" macro
*/

Macro "Calculate MC" (Args)

    scen_dir = Args.[Scenario Folder]
    skims_dir = scen_dir + "\\output\\skims\\"
    input_dir = Args.[Input Folder]
    input_mc_dir = input_dir + "/resident/mode"
    output_dir = Args.[Output Folder] + "/resident/mode"
    periods = Args.periods

    // Determine trip purposes
    prod_rate_file = input_dir + "/resident/generation/production_rates.csv"
    rate_vw = OpenTable("rate_vw", "CSV", {prod_rate_file})
    trip_types = GetDataVector(rate_vw + "|", "trip_type", )
    trip_types = SortVector(trip_types, {Unique: "true"})

    opts = null
    opts.segments = {"v0", "vi", "vs"}
    for trip_type in trip_types do
        opts.trip_type = trip_type
        opts.util_file = input_mc_dir + "/" + trip_type + ".csv"
        nest_file = input_mc_dir + "/" + trip_type + "_nest.csv"
        if GetFileInfo(nest_file) <> null then opts.nest_file = nest_file

        for period in periods do
            opts.period = period
            
            // Determine which sov & hov skim to use
            if period = "MD" or period = "NT" then do
                tour_type = "All"
                homebased = "All"
            end else do
                tour_type = Upper(Left(trip_type, 1))
                homebased = "HB"
            end
            sov_skim = skims_dir + "roadway\\avg_skim_" + period + "_" + tour_type + "_" + homebased + "_sov.mtx"
            hov_skim = skims_dir + "roadway\\avg_skim_" + period + "_" + tour_type + "_" + homebased + "_hov.mtx"
            
            // Set sources
            opts.tables = {
                se: {file: scen_dir + "\\output\\sedata\\scenario_se.bin", id_field: "TAZ"},
                parking: {file: scen_dir + "\\output\\resident\\parking\\ParkingLogsums.bin", id_field: "TAZ"}
            }
            opts.matrices = {
                sov_skim: {file: sov_skim},
                hov_skim: {file: hov_skim},
                w_lb_skim: {file: skims_dir + "transit\\skim_" + period + "_w_lb.mtx"},
                w_eb_skim: {file: skims_dir + "transit\\skim_" + period + "_w_eb.mtx"},
                pnr_lb_skim: {file: skims_dir + "transit\\skim_" + period + "_pnr_lb.mtx"},
                pnr_eb_skim: {file: skims_dir + "transit\\skim_" + period + "_pnr_eb.mtx"},
                knr_lb_skim: {file: skims_dir + "transit\\skim_" + period + "_knr_lb.mtx"},
                knr_eb_skim: {file: skims_dir + "transit\\skim_" + period + "_knr_eb.mtx"}
            }
            opts.output_dir = output_dir
            RunMacro("MC", Args, opts)
        end
    end
endmacro