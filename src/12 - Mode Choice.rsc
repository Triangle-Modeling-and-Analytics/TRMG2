/*
Calculates aggregate mode choice probabilities between zonal ij pairs
*/

Macro "Mode Probabilities" (Args)

    if Args.FeedbackIteration = 1 then RunMacro("Create MC Features", Args)
    RunMacro("Calculate MC", Args)
    RunMacro("Post Process Logsum", Args)
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
    periods = RunMacro("Get Unconverged Periods", Args)
    mode_table = Args.TransModeTable
    transit_modes = RunMacro("Get Transit Modes", mode_table)
    access_modes = Args.access_modes

    // Determine trip purposes
    prod_rate_file = input_dir + "/resident/generation/production_rates.csv"
    rate_vw = OpenTable("rate_vw", "CSV", {prod_rate_file})
    trip_types = GetDataVector(rate_vw + "|", "trip_type", )
    trip_types = SortVector(trip_types, {Unique: "true"})
    CloseView(rate_vw)

    opts = null
    opts.primary_spec = {Name: "w_lb_skim"}
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_w_all"
            then opts.segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
            else opts.segments = {"v0", "vi", "vs"}
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
                se: {File: scen_dir + "\\output\\sedata\\scenario_se.bin", IDField: "TAZ"},
                parking: {File: scen_dir + "\\output\\resident\\parking\\ParkingLogsums.bin", IDField: "TAZ"}
            }
            opts.matrices = {
                sov_skim: {File: sov_skim},
                hov_skim: {File: hov_skim}
            }
            // Transit skims depend on which modes are present in the scenario
            for transit_mode in transit_modes do
                for access_mode in access_modes do
                    source_name = access_mode + "_" + transit_mode + "_skim"
                    file_name = skims_dir + "transit\\skim_" + period + "_" + access_mode + "_" + transit_mode + ".mtx"
                    if GetFileInfo(file_name) <> null then opts.matrices.(source_name) = {File: file_name}
                end
            end

            opts.output_dir = output_dir
            
            // RunMacro("Parallel.SetMaxEngines", 3)
            // task = CreateObject("Parallel.Task", "MC", GetInterface())
            // task.Run(opts)
            // tasks = tasks + {task}
            // If running in series use the following and comment out the task/monitor lines
            RunMacro("MC", opts)
        end
    end

    // monitor = CreateObject("Parallel.TaskMonitor", tasks)
    // monitor.DisplayStatus()
    // monitor.WaitForAll()
    // if monitor.IsFailed then Throw("MC Failed")
    // monitor.CloseStatusDbox()
endmacro

/*
Transforms the mc logsums used in destination choice to all be positive values.
This is only necessary because we are using nest-level logsums rather than
ultimate/root logsums (which are all positive already)
*/

Macro "Post Process Logsum" (Args)
    
    ls_dir = Args.[Output Folder] + "/resident/mode/logsums"
    periods = RunMacro("Get Unconverged Periods", Args)

    trip_types = RunMacro("Get HB Trip Types", Args)
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_w_all"
            then segments = {"v0", "ilvi", "ihvi", "ilvs", "ihvs"}
            else segments = {"v0", "vi", "vs"}
        for period in periods do
            for segment in segments do
                mtx_file = ls_dir + "/logsum_" + trip_type + "_" + segment + "_" + period + ".mtx"
                mtx = CreateObject("Matrix")
                mtx.LoadMatrix(mtx_file)
                core_names = mtx._GetCoreNames()
                if ArrayPosition(core_names, {"nonhh_auto"},) > 0 then do
                    mtx.AddCores({"NonHHAutoComposite"})
                    mtx.NonHHAutoComposite := log(1 + nz(exp(mtx.nonhh_auto)))
                end
                if ArrayPosition(core_names, {"transit"},) > 0 then do
                    mtx.AddCores({"TransitComposite"})
                    mtx.TransitComposite := log(1 + nz(exp(mtx.transit)))
                end
                if segment <> "v0" and ArrayPosition(core_names, {"auto"},) > 0 then do
                    mtx.AddCores({"AutoComposite"})
                    mtx.AutoComposite := log(1 + nz(exp(mtx.auto)))
                end
                mtx = null
            end
        end
    end
endmacro