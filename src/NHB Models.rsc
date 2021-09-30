/*
These models generate and distribute NHB trips based on the results of the HB
models.
*/

Macro "NonHomeBased" (Args)

    RunMacro("NHB Generation", Args)
    RunMacro("NHB DC", Args)
    return(1)
endmacro

/*

*/

Macro "NHB Generation" (Args)

    param_dir = Args.[Input Folder] + "/resident/nhb/generation"
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_tables"
    periods = Args.periods
    se_file = Args.SE
    calib_fac_file = Args.NHBGenCalibFacs
    trip_types = RunMacro("Get NHB Trip Types", Args)
    modes = {"sov", "hov2", "hov3", "auto_pay", "walkbike", "t"}

    // Create the output table with initial fields
    out_file = out_dir + "/resident/nhb/generation.bin"
    if GetFileInfo(out_file) <> null then do
        DeleteFile(out_file)
        DeleteFile(Substitute(out_file, ".bin", ".dcb", ))
    end
    out_vw = CreateTable("out", out_file, "FFB", {
        {"TAZ", "Integer", 10, , , "Zone ID"},
        {"access_nearby_sov", "Real", 10, 2, , "sov accessibility"},
        {"access_transit", "Real", 10, 2, , "transit accessibility"},
        {"access_walk", "Real", 10, 2, , "walk accessibility"}
    })
    se_vw = OpenTable("se", "FFB", {se_file})
    taz = GetDataVector(se_vw + "|", "TAZ", )
    n = GetRecordCount(se_vw, )
    AddRecords(out_vw, , , {"empty records": n})
    SetDataVector(out_vw + "|", "TAZ", taz, )
    jv = JoinViews("jv", out_vw + ".TAZ", se_vw + ".TAZ", )
    // store accessibilities for use later in this macro but also include
    // them in the table
    access.access_nearby_sov = GetDataVector(jv + "|", se_vw + ".access_nearby_sov", )
    access.access_transit = GetDataVector(jv + "|", se_vw + ".access_transit", )
    access.access_walk = GetDataVector(jv + "|", se_vw + ".access_walk", )
    SetDataVector(jv + "|", out_vw + ".access_nearby_sov", access.access_nearby_sov, )
    SetDataVector(jv + "|", out_vw + ".access_transit", access.access_transit, )
    SetDataVector(jv + "|", out_vw + ".access_walk", access.access_walk, )
    CloseView(jv)
    CloseView(se_vw)
    CloseView(out_vw)

    // Get calibration factors
    calib_facs = RunMacro("Read Parameter File", {
        file: calib_fac_file,
        names: "type",
        values: "factor"
    })

    // Create a summary table by tour type and mode. This is used in calibration,
    // but may also be helpful for future debugging.
    summary_file = Substitute(out_file, ".bin", "_summary.bin", )
    CopyFile(out_file, summary_file)
    CopyFile(
        Substitute(out_file, ".bin", ".dcb", ),
        Substitute(summary_file, ".bin", ".dcb", )
    )

    for trip_type in trip_types do
        tour_type = Left(trip_type, 1)

        for mode in modes do
            // Get the generation parameters for this type+mode combo
            file = param_dir + "/" + trip_type + "_" + mode + ".csv"
            if GetFileInfo(file) = null then continue
            params = RunMacro("Read Parameter File", {
                file: file,
                names: "term",
                values: "estimate"
            })
            alpha = params.alpha
            gamma = params.gamma
            // Remove params so that only generation coefficients remain
            params.alpha = null
            params.gamma = null
            params.r_sq = null

            // Create period-specific generation fields
            for period in periods do
                field_name = trip_type + "_" + mode + "_" + period
                fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, ""}}
                
                for i = 1 to params.length do
                    param = params[i][1]
                    coef = params.(param)

                    {hb_trip_type, hb_mode} = RunMacro("Separate type and mode", param)
                    if hb_mode = "walkbike" then do
                        hb_mtx_file = out_dir + "/resident/nonmotorized/nm_gravity.mtx"
                        hb_core = hb_trip_type + "_" + period
                    end else do
                        hb_mtx_file = trip_dir + "/pa_per_trips_" + hb_trip_type + "_" + period + ".mtx"
                        hb_core = hb_mode
                    end
                    if hb_mode = "lb" then hb_core = "all_transit"
                    hb_mtx = CreateObject("Matrix", hb_mtx_file)
                    v = hb_mtx.GetVector(hb_core, {Marginal: "Column Sum"})
                    v.rowbased = "true"
                    data.(field_name) = nz(data.(field_name)) + nz(v) * coef
                end

                // Boosting
                access_field = if mode = "walkbike" then "access_walk"
                    else if mode = "t" then "access_transit"
                    else "access_nearby_sov"
                if alpha <> null then do
                    boost_factor = pow(access.(access_field), gamma) * alpha
                    data.(field_name) = data.(field_name) * boost_factor
                end
                // Transit models are not boosted, but set generation to
                // zero for zones with no transit access
                if mode = "t" then do
                    data.(field_name) = if access.(access_field) = 0
                        then 0
                        else data.(field_name)
                end

                // Apply calibration factor
                calib_fac = calib_facs.(tour_type + "_" + mode)
                data.(field_name) = data.(field_name) * calib_fac

                // Sum up data by tour type and mode
                summary.(tour_type + "_" + mode) = nz(summary.(tour_type + "_" + mode)) +
                    nz(data.(field_name))
            end
        end
    end

    // Fill in the raw output table
    out_vw = OpenTable("out", "FFB", {out_file})
    RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
    SetDataVectors(out_vw + "|", data, )
    CloseView(out_vw)

    // Fill in summary info
    summary_vw = OpenTable("summary", "FFB", {summary_file})
    fields_to_add = null
    for i = 1 to summary.length do
        field_name = summary[i][1]
        fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, ""}}
    end
    RunMacro("Add Fields", {view: summary_vw, a_fields: fields_to_add})
    SetDataVectors(summary_vw + "|", summary, )
    CloseView(summary_vw)
endmacro


/* Macro runs the destination choice models for NHB purposes
    ** Step 1: Combine the columns of the NHB trip gen outputs into 4 main categories:
               Work Auto, NonWork Auto, Transit and WalkBike
               Retain columns by time period
               For example: For N_Auto combine 'SOV', 'HOV2', 'HOV3' for N_NH_K12, N_NH_OME and N_NH_O purposes and 'auto_pay' for N_NH_O

    ** Step 2: Run DC model for 4*4(periods) = 16 sub models. Use appropriate skim whereever applicable
               Generate applied totals matrices as part of the DC process

    ** Step 3: Produce combined matrix file for NHB trip with 12 cores
               Combination of (Auto, WalkBike, Transit) by period (AM, PM, MD, NT)

*/
Macro "NHB DC"(Args)
    // Create Folders
    out_folder = Args.[Output Folder]
    mdl_dir = out_folder + "/resident/nhb/dc/model_files"
    if GetDirectoryInfo(mdl_dir, "All") = null then CreateDirectory(mdl_dir)
    prob_dir = out_folder + "/resident/nhb/dc/probabilities"
    if GetDirectoryInfo(prob_dir, "All") = null then CreateDirectory(prob_dir)
    totals_dir = out_folder + "/resident/nhb/dc/trip_matrices"
    if GetDirectoryInfo(totals_dir, "All") = null then CreateDirectory(totals_dir)
    
    // Step 1: Combine Trips
    RunMacro("Combine NHB trips for DC", Args)

    // Step 2: Run DC
    RunMacro("Evaluate NHB DC", Args)

    // Step 3: Final NHB Matrix
    RunMacro("Create NHB Trip Matrix", Args)
endMacro


// Create a table of NHB productions for the DC model
// Collapses the NHB trips by purpose and mode into 4 categories: 'WorkAuto', 'NonWorkAuto', 'WalkBike', 'Transit'
Macro "Combine NHB trips for DC"(Args)
    periods = Args.periods
    trip_types = RunMacro("Get NHB Trip Types", Args)

    // Create output table
    out_dir = Args.[Output Folder]
    out_file = out_dir + "/resident/nhb/dc/NHBTripsForDC.bin"
    spec = {{"TAZ", "Integer", 10, , , "Zone ID"}}
    categories = {'W_Auto', 'N_Auto', 'WalkBike', 'Transit'}
    for category in categories do
        for period in periods do
            spec = spec + {{"NHB_" + category + "_" + period, "Real", 12, 2}}
        end
    end
    out_vw = CreateTable("out", out_file, "FFB", spec)

    // Obtain values from NHB trip generation table
    tgenFile = out_dir + "/resident/nhb/generation.bin"
    tgen_vw = OpenTable("out", "FFB", {tgenFile})
    {flds, specs} = GetFields(tgen_vw,)
    vecs = GetDataVectors(tgen_vw + "|", flds, {OptArray: 1})
    CloseView(tgen_vw)
    
    // Fill output table
    vecsSet = null
    vecsSet.TAZ = vecs.TAZ
    for fld in flds do
        tour_type = Left(fld, 1)
        if Lower(tour_type) <> "w" and Lower(tour_type) <> "n" then // Non trip fields
            continue
        
        period = Right(fld,2)
        if Lower(fld) contains "walkbike" then
            outfld = "NHB_WalkBike_" + period
        else if Lower(fld) contains "_t_" then
            outfld = "NHB_Transit_" + period
        else if Lower(tour_type) = "w" then // Auto and Work
            outfld = "NHB_W_Auto_" + period
        else
            outfld = "NHB_N_Auto_" + period

        vecsSet.(outfld) = nz(vecsSet.(outfld)) + nz(vecs.(fld))   
    end
    AddRecords(out_vw,,,{"Empty Records": vecsSet.TAZ.length})
    SetDataVectors(out_vw + "|", vecsSet,)
    CloseView(out_vw)
endMacro


/*
    Evaluate NHB Destination Choice model using all zones
    16 models one for each category and time period
    4 categories: Auto_Work, Auto_NonWork, Transit and WalkBike
    4 time periods
*/
Macro "Evaluate NHB DC"(Args)
    // Folders
    in_folder = Args.[Input Folder] + "/resident/nhb/dc/"
    out_folder = Args.[Output Folder]
    skims_folder = out_folder + "/skims/"
    nhb_folder = out_folder + "/resident/nhb/dc/"
    mdl_folder = nhb_folder + "model_files/"
    prob_folder = nhb_folder + "probabilities/"
    trips_folder = nhb_folder + "trip_matrices/"
    pa_file = nhb_folder + "NHBTripsForDC.bin"

    // Compute Size Terms
    se_file = Args.SE
    sizeSpec = {DataFile: se_file, CoeffFile: Args.NHBDCSizeCoeffs}
    RunMacro("Compute Size Terms", sizeSpec)

    // Create IntraCluster matrix
    RunMacro("Create Intra Cluster Matrix", Args)
    intraClusterMtx = skims_folder + "IntraCluster.mtx"

    // Run DC Loop over categories and time periods
    periods = Args.periods
    categories = {'W_Auto', 'N_Auto', 'WalkBike', 'Transit'}
    for category in categories do
        coeffFile = in_folder + "nhb_" + category + "_dc.csv"
        util = RunMacro("Import MC Spec", coeffFile) 
        
        for period in periods do
            tag = "NHB_" + category + "_" + period

            if category = 'WalkBike' then
                skimFile = skims_folder + "nonmotorized/walk_skim.mtx"
            else if category = 'Transit' then
                skimFile = skims_folder + "transit/skim_" + period + "_w_lb.mtx"
            else // Auto
                skimFile = skims_folder + "roadway/skim_sov_" + period + ".mtx"
            
            obj = CreateObject("PMEChoiceModel", {ModelName: tag})
            obj.OutputModelFile = mdl_folder + tag + "_zone.dcm"
            
            // Add sources (skim, parkingLS, SE, PATrips, IntraCluster Matrix)
            obj.AddMatrixSource({SourceName: 'skim', File: skimFile})
            obj.AddMatrixSource({SourceName: 'IntraCluster', File: intraClusterMtx})
            obj.AddTableSource({SourceName: 'se', File: se_file, IDField: "TAZ"})
            obj.AddTableSource({SourceName: 'Parking', File: Args.[Parking Logsums Table], IDField: "TAZ"})
            obj.AddTableSource({SourceName: 'PA', File: pa_file, IDField: "TAZ"})

            // Add primary spec
            obj.AddPrimarySpec({Name: "IntraCluster"})

            // Add destinations source and index
            obj.AddDestinations({DestinationsSource: "IntraCluster", DestinationsIndex: "All Zones"})

            // Add utility
            obj.AddUtility({UtilityFunction: util})
            
            // Add PA for applied totals
            obj.AddTotalsSpec({Name: "PA", ZonalField: tag})

            // Add output spec
            outputSpec = {"Probability": prob_folder + "Prob_" + tag + ".mtx",
                          "Totals": trips_folder + tag + ".mtx"}
            obj.AddOutputSpec(outputSpec)
            
            ret = obj.Evaluate()
            if !ret then
                Throw("Running '" + tag + "' destination choice model failed.")
        end
    end
endMacro


Macro "Create NHB Trip Matrix"(Args)
    out_folder = Args.[Output Folder]
    trips_folder = out_folder + "/resident/nhb/dc/trip_matrices/"

    // Create output matrix
    modes = {"Auto", "Transit", "WalkBike"}
    categories = {'W_Auto', 'N_Auto', 'WalkBike', 'Transit'}
    periods = Args.periods

    se = Args.SE
    se_vw = OpenTable("SE", "FFB", {se})
    vTAZ = GetDataVector(se_vw + "|", "TAZ",)
    CloseView(se_vw)

    cores = null
    for mode in modes do
        for period in periods do
            cores = cores + {mode + "_" + period}
        end
    end
    outMtx = out_folder + "/resident/trip_tables/" + "pa_per_trips_NHB.mtx"

    obj = CreateObject("Matrix") 
    obj.SetMatrixOptions({Compressed: 1, DataType: "Double", FileName: outMtx, MatrixLabel: "NHBTrips"})
    opts.RowIds = v2a(vTAZ) 
    opts.ColIds = v2a(vTAZ)
    opts.MatrixNames = cores
    opts.RowIndexName = "Origin"
    opts.ColIndexName = "Destination"
    mat = obj.CreateFromArrays(opts)
    obj = null

    // Fill matrix
    obj = CreateObject("Matrix", mat)
    mcsOut = obj.GetCores()
    for category in categories do
        for period in periods do
            if category contains "Auto" then
                mode = "Auto"
            else
                mode = category

            totals_mtx = trips_folder + "NHB_" + category + "_" + period + ".mtx"
            objC = CreateObject("Matrix", totals_mtx)
            mcs = objC.GetCores()
            mc = mcs[1][2]  // Matrix has only one core with applied totals 

            outCore = mode + "_" + period
            mcsOut.(outCore) := nz(mcsOut.(outCore)) + nz(mc)
            objC = null
        end
    end
    mat = null
endMacro