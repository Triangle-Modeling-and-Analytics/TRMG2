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

    input_dir = Args.[Input Folder]
    input_mc_dir = input_dir + "/resident/mode"
    output_dir = Args.[Output Folder] + "/resident/mode"
    periods = Args.periods

    // Determine trip purposes
    prod_rate_file = input_dir + "/resident/generation/production_rates.csv"
    rate_vw = OpenTable("rate_vw", "CSV", {prod_rate_file})
    trip_types = GetDataVector(rate_vw + "|", "trip_type", )
    trip_types = SortVector(trip_types, {Unique: "true"})

    for trip_type in trip_types do
        opts = null
        opts.trip_type = trip_type
        opts.util_file = input_mc_dir + "/" + trip_type + ".csv"
        nest_file = input_mc_dir + "/" + trip_type + "_nest.csv"
        if GetFileInfo(nest_file) <> null then opts.alts_file = nest_file
        opts.Segments = {"v0", "vi", "vs"}
        opts.Periods = periods
        opts.output_dir = output_dir
        RunMacro("MC", Args, opts)
    end

endmacro

/*
Performs MC calculations for a given purpose. Loops over segments and time
periods.
*/

Macro "MC" (Args, Opts)
    scen_dir = Args.[Scenario Folder]
    output_dir = Opts.output_dir
    trip_type = Opts.trip_type
    util_file = Opts.util_file
    alts_file = Opts.alts_file
    segments = Opts.Segments
    periods = Opts.Periods
    skims_dir = scen_dir + "\\output\\skims\\"

    // Import csv files into an options array
    util = RunMacro("Import MC Spec", util_file)
    
    if alts_file <> null then alt_tree = RunMacro("Import MC Spec", alts_file)

    for seg in segments do
        for period in periods do
            tag = trip_type + "_" + seg + "_" + period

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

            // Set up and run model. Cleaner to create the object within the loop.
            obj = CreateObject("PMEChoiceModel", {ModelName: tag})
            obj.Segment = seg
            obj.OutputModelFile = output_dir + "\\model_files\\" + tag + ".mdl"
            
            // Add sources
            obj.AddTableSource({SourceName: "se",           File: scen_dir + "\\output\\sedata\\scenario_se.bin", IDField: "TAZ"})
            obj.AddTableSource({SourceName: "parking",      File: scen_dir + "\\output\\resident\\parking\\ParkingLogsums.bin", IDField: "TAZ"})
            obj.AddMatrixSource({SourceName: "sov_skim",    File: sov_skim})
            obj.AddMatrixSource({SourceName: "hov_skim",    File: hov_skim})
            obj.AddMatrixSource({SourceName: "w_lb_skim",   File: skims_dir + "transit\\skim_" + period + "_w_lb.mtx"})
            obj.AddMatrixSource({SourceName: "w_eb_skim",   File: skims_dir + "transit\\skim_" + period + "_w_eb.mtx"})
            obj.AddMatrixSource({SourceName: "pnr_lb_skim", File: skims_dir + "transit\\skim_" + period + "_pnr_lb.mtx"})
            obj.AddMatrixSource({SourceName: "pnr_eb_skim", File: skims_dir + "transit\\skim_" + period + "_pnr_eb.mtx"})
            obj.AddMatrixSource({SourceName: "knr_lb_skim", File: skims_dir + "transit\\skim_" + period + "_knr_lb.mtx"})
            obj.AddMatrixSource({SourceName: "knr_eb_skim", File: skims_dir + "transit\\skim_" + period + "_knr_eb.mtx"})
            
            // Add alternatives, utility and specify the primary source
            if alt_tree <> null then
                obj.AddAlternatives({AlternativesTree: alt_tree})
            obj.AddUtility({UtilityFunction: util})
            obj.AddPrimarySpec({Name: "w_lb_skim"})
            
            // Specify outputs. 
            output_opts = {Probability: output_dir + "\\probabilities\\probability_" + tag + ".mtx",
                          Logsum: output_dir + "\\logsums\\logsum_" + tag + ".mtx"}
            // The matrices take up a lot of space, so don't write the utility 
            // matrices except for debugging/development. Uncomment the line
            // below to write them.
            // output_opts = output_opts + {Utility: output_dir + "\\utilities\\utility_" + tag + ".mtx"}
            obj.AddOutputSpec(output_opts)
            
            //obj.CloseFiles = 0 // Uncomment to leave files open, so you can save a workspace
            ret = obj.Evaluate()
            if !ret then
                Throw("Running mode choice model failed for: " + tag)
            obj = null
        end
    end
endMacro

/*
Helper for "MC" macro
*/

Macro "Import MC Spec"(file)
    vw = OpenTable("Spec", "CSV", {file,})
    {flds, specs} = GetFields(vw,)
    vecs = GetDataVectors(vw + "|", flds, {OptArray: 1})
    
    util = null
    for fld in flds do
        util.(fld) = v2a(vecs.(fld))
    end
    CloseView(vw)
    Return(util)
endMacro