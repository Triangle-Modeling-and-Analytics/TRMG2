/*
Calculates aggregate mode choice logsums/probabilities between zonal ij pairs
Probability matrices will be used in 'Mode Choices' if the model run is aggregate
*/

Macro "Mode Logsums" (Args)
    if Args.FeedbackIteration = 1 then 
        RunMacro("Create MC Features", Args)
    
    RunMacro("Calculate MC", Args)
    RunMacro("Post Process Logsum", Args)
    return(1)
endmacro


/*
Call aggregate or disaggregate mode choice models based on model flag
If aggregate, simply apply probabilities (like the regualr model)
If disaggregate, calculate choices
*/
Macro "Mode Choices"(Args)
    if Args.DisaggregateRun = 1 then
        RunMacro("Mode Choices Disagg", Args)
    else
        RunMacro("Application of Probabilities", Args)
    
    return(1)
endMacro


/*
Calculates disaggregate mode choices
*/

Macro "Mode Choices Disagg" (Args)
    RunMacro("Calculate Disagg MC", Args)
    RunMacro("Disagg Directionality", Args)
    RunMacro("Aggregate HB Trip Tables", Args)
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
                tag = trip_type + "_" + segment + "_" + period
                mtx_file = ls_dir + "/logsum_" + tag + ".mtx"
                mtx = CreateObject("Matrix", mtx_file)
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
                RenameMatrix(mtx.GetMatrixHandle(), "Logsum_" + tag)
                mtx = null
            end
        end
    end
endmacro


/*
Loops over purposes and preps options for the "MC" macro
*/

Macro "Calculate Disagg MC" (Args)

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
    pbar = CreateObject("G30 Progress Bar", "Disaggregate MC Model by purpose and period", false, trip_types.length*periods.length)
    for trip_type in trip_types do
        opts.trip_type = trip_type
        opts.util_file = input_mc_dir + "/" + trip_type + "_disagg.csv"
        nest_file = input_mc_dir + "/" + trip_type + "_nest.csv"
        if GetFileInfo(nest_file) <> null then opts.nest_file = nest_file

        trip_file = Args.[Output Folder] + "/resident/trip_tables/" + trip_type + ".bin"
        // Add choice field to trip file
        tObj = CreateObject("Table", trip_file)
        fields = {{FieldName: "Mode", Type: "string"},
                  {FieldName: "One", Type: "short"}}
        tObj.AddFields({Fields: fields})
        tObj.One = 1
        vwTrips = ExportView(tObj.GetView() + "|", "MEM", "Trips",,)
        tObj = null

        for period in periods do
            opts.period = period
            opts.primary_spec = {Name: "trips", Filter: "TOD = '" + period + "'", OField: "HHTAZ", DField: "DestTAZ"}
            
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
                parking: {File: scen_dir + "\\output\\resident\\parking\\ParkingLogsums.bin", IDField: "TAZ"},
                //trips: {File: trip_file, IDField: "TripID"}
                trips: {View: vwTrips, IDField: "TripID"}
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
            opts.choice_field = "Mode"
            opts.random_seed = 999*trip_types.position(trip_type) + 99*periods.position(period)
            
            // RunMacro("Parallel.SetMaxEngines", 3)
            // task = CreateObject("Parallel.Task", "MC", GetInterface())
            // task.Run(opts)
            // tasks = tasks + {task}
            // If running in series use the following and comment out the task/monitor lines
            RunMacro("Disagg MC", opts)
            pbar.Step()
        end
        ExportView(vwTrips + "|", "FFB", trip_file,,)
        CloseView(vwTrips)
    end
    pbar.Destroy()

    // monitor = CreateObject("Parallel.TaskMonitor", tasks)
    // monitor.DisplayStatus()
    // monitor.WaitForAll()
    // if monitor.IsFailed then Throw("MC Failed")
    // monitor.CloseStatusDbox()
endmacro

/*
Apply directional factors to the trip table directly and use
monte carlo to determine whether or not to flip a trip. This approach
(instead of doing directionality after aggregation) maintains integer trip
matrices.
*/

Macro "Disagg Directionality" (Args)
    
    trip_tbl_dir = Args.[Output Folder] + "/resident/trip_tables"
    dir_file = Args.DirectionFactors
    trip_types = RunMacro("Get HB Trip Types", Args)
    periods = RunMacro("Get Unconverged Periods", Args)

    dir_tbl = CreateObject("Table", dir_file)

    for trip_type in trip_types do
        trip_tbl = CreateObject("Table", trip_tbl_dir + "/" + trip_type + ".bin")
        trip_tbl.AddFields({Fields: {
            {FieldName: "PA", Description: "If the trip will remain in the PA direction"},
            {FieldName: "o_taz", Type: "integer", Description: "Origin TAZ (after accounting for directionality)"},
            {FieldName: "d_taz", Type: "integer", Description: "Destination TAZ (after accounting for directionality)"}
        }})
        dir_tbl.SelectByQuery({
            SetName: "trip_type",
            Query: "trip_type = '" + trip_type + "'"
        })
        sub_tbl = dir_tbl.Export({
            ViewName: "sub_tbl",
            FieldNames: {"tod", "pa_fac"}
        })
        join = trip_tbl.Join({
            Table: sub_tbl,
            LeftFields: "TOD",
            RightFields: "tod"
        })
        data = join.GetDataVectors({
            FieldNames: {"pa_fac", "HHTAZ", "DestTAZ"}
        })
        v_rand = RandSamples(data.pa_fac.length, "Uniform", )
        set = null
        set.PA = if v_rand < data.pa_fac then 1 else 0
        set.o_taz = if set.PA = 1 then data.HHTAZ else data.DestTAZ
        set.d_taz = if set.PA = 1 then data.DestTAZ else data.HHTAZ
        join.SetDataVectors({FieldData: set})
        
        join = null
        sub_tbl = null
        trip_tbl = null
    end
endmacro

/*

*/

Macro "Aggregate HB Trip Tables" (Args)
    trip_tbl_dir = Args.[Output Folder] + "/resident/trip_tables"
    trip_mtx_dir = Args.[Output Folder] + "/resident/trip_matrices"
    mc_dir = Args.[Output Folder] + "/resident/mode"
    periods = RunMacro("Get Unconverged Periods", Args)
    trip_types = RunMacro("Get HB Trip Types", Args)
    mtx_types = {'pa', 'od'}

    for trip_type in trip_types do

        // Get the unique modes in the table and create the `cols` argument
        // for UpdateMatrixFromView().
        trip_tbl_file = trip_tbl_dir + "/" + trip_type + ".bin"
        trip_tbl = CreateObject("Table", trip_tbl_file)

        for period in periods do
            // Create a set of trips in the current period
            trip_tbl.SelectByQuery({
                SetName: "period",
                Query: "TOD = '" + period + "'"
            })

            for type in mtx_types do // Generate both PA and OD matrices, the former used for NHB models
                if type = 'pa' then do
                    oTAZ = 'HHTAZ'
                    dTAZ = 'DestTAZ'
                end 
                else do
                    oTAZ = 'o_taz'
                    dTAZ = 'd_taz'
                end

                // Create matrix to update
                out_mtx_file = trip_mtx_dir + "/" + type + "_per_trips_" + trip_type + "_" + period + ".mtx"
                mc_mtx_file = mc_dir + "/probabilities/probability_" + trip_type + "_v0_" + period + ".mtx"
                CopyFile(mc_mtx_file, out_mtx_file)
                mtx = CreateObject("Matrix", out_mtx_file)
                mh = mtx.GetMatrixHandle()
                RenameMatrix(mh, Upper(type) + " Per Trips " + trip_type + " " + period)

                // Zero out all cores
                core_names = mtx.GetCoreNames()
                for core in core_names do
                    mtx.(core) := 0
                end

                // Update matrix from the person table
                // TODO: use Matrix.UpdateFromTable() when we move to latest TC 10
                viewset = trip_tbl.GetView() + "|period"
                UpdateMatrixFromView(
                    mh, viewset, oTAZ, dTAZ, "Mode", {"One"}, "Add", 
                    {"Missing is zero": "true"}
                )

                // Create an extra core the combines all transit modes together
                // This is not assigned, but is used in the NHB trip generation
                // model. Needed only for PA matrices.
                if type = 'pa' then do
                    access_modes = Args.access_modes
                    core_names = mtx.GetCoreNames()
                    mtx.AddCores({"all_transit"})
                    cores = mtx.GetCores()
                    cores.all_transit := 0
                    for core_name in core_names do
                        parts = ParseString(core_name, "_")
                        access_mode = parts[1]
                        // skip non-transit cores
                        if access_modes.position(access_mode) = 0 then continue
                        cores.all_transit := nz(cores.all_transit) + nz(cores.(core_name))
                    end
                    cores.all_transit := if cores.all_transit = 0 then null else cores.all_transit
                end
            end

        end
    end
endmacro