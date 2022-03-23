/*
These models generate and distribute NHB trips based on the results of the HB
models.
*/

Macro "NHB Generation by Mode" (Args)
    RunMacro("NHB Generation", Args)
    return(1)
endmacro

Macro "NHB Destination Choice" (Args)
    RunMacro("NHB DC", Args)
    return(1)
endmacro

/*
Generate NHB trips based on HB trip attraction ends
*/

Macro "NHB Generation" (Args)

    param_dir = Args.[Input Folder] + "/resident/nhb/generation"
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_matrices"
    nhb_dir = out_dir + "/resident/nhb/generation"
    periods = RunMacro("Get Unconverged Periods", Args)
    se_file = Args.SE
    tod_fac_file = Args.NHBTODFacs
    trip_types = RunMacro("Get NHB Trip Types", Args)
    modes = {"sov", "hov2", "hov3", "auto_pay", "walkbike", "t"}
    iteration = Args.FeedbackIteration

    // Create the output table (first iteration only)
    out_file = nhb_dir + "/generation.bin"
    if iteration = 1 then do
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
        CloseView(se_vw)
        CloseView(out_vw)
    end

    // Add initial fields
    out_vw = OpenTable("out", "FFB", {out_file})
    se_vw = OpenTable("se", "FFB", {se_file})
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

    // Get tod factors
    tod_facs = RunMacro("Read Parameter File", {
        file: tod_fac_file,
        names: "type",
        values: "factor"
    })

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
                if Left(field_name, 1) = "N"
                    then desc = "NHB trips on non-work tours"
                    else desc = "NHB trips on work tours"
                fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, desc}}
                
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
                    v = hb_mtx.GetVector({"Core": hb_core, Marginal: "Column Sum"})
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

                // Apply TOD factors
                tod_fac = tod_facs.(tour_type + "_" + mode + "_" + period)
                if tod_fac = null then Throw("NHB TOD factor not found")
                data.(field_name) = data.(field_name) * tod_fac
            end
        end
    end

    // Fill in the raw output table
    out_vw = OpenTable("out", "FFB", {out_file})
    RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
    SetDataVectors(out_vw + "|", data, )
    CloseView(out_vw)
endmacro


/* Macro runs the destination choice models for NHB purposes
    ** Step 1: Combine the columns of the NHB trip gen outputs into 10 main categories:
               (Work Tour, NonWork Tour) X (sov, hov2, hov3 & auto_pay), Transit and WalkBike
               Retain columns by time period

    ** Step 2: Run DC model for 10*4(periods) = 40 sub models. Use appropriate skim wherever applicable
               Generate applied totals matrices as part of the DC process
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
    
    Spec.SubModels = {'w_sov', 'w_hov2', 'w_hov3', 'w_auto_pay', 
                      'n_sov', 'n_hov2', 'n_hov3', 'n_auto_pay', 
                      'walkbike', 
                      'transit'}
    // Step 1: Combine Trips
    RunMacro("Combine NHB trips for DC", Args, Spec)

    // Step 2: Run DC
    RunMacro("Evaluate NHB DC", Args, Spec)
endMacro


// Create a table of NHB productions for the DC model
// Collapses the NHB trips by purpose and mode into 10 categories ('W_Auto', 'N_Auto') X (sov, hov2, hov3, auto_pay), 'Transit', 'WalkBike')
Macro "Combine NHB trips for DC"(Args, Spec)
    periods = Args.periods
    trip_types = RunMacro("Get NHB Trip Types", Args)

    // Create output table
    out_dir = Args.[Output Folder]
    out_file = out_dir + "/resident/nhb/dc/NHBTripsForDC.bin"
    spec = {{"TAZ", "Integer", 10, , , "Zone ID"}}
    categories = Spec.SubModels
    for category in categories do
        for period in periods do
            spec = spec + {{"NHB_" + category + "_" + period, "Real", 12, 2}}
        end
    end
    out_vw = CreateTable("out", out_file, "FFB", spec)

    // Obtain values from NHB trip generation table
    tgenFile = out_dir + "/resident/nhb/generation/generation.bin"
    tgen_vw = OpenTable("out", "FFB", {tgenFile})
    {flds, specs} = GetFields(tgen_vw,)
    vecs = GetDataVectors(tgen_vw + "|", flds, {OptArray: 1})
    CloseView(tgen_vw)
    
    // Fill output table
    vecsSet = null
    vecsSet.TAZ = vecs.TAZ
    for fld in flds do
        fld = Lower(fld)
        tour_type = Left(fld, 1)
        if tour_type <> "w" and tour_type <> "n" then // Non trip fields
            continue
        
        period = Right(fld,2)
        {mainMode, subMode} = RunMacro("Get Mode Info", fld)
        if mainMode = "auto" then // Append tour type to field name
            outfld = "NHB_" + tour_type + "_" + subMode + "_" + period    
        else
            outfld = "NHB_" + subMode + "_" + period

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
Macro "Evaluate NHB DC"(Args, Spec)
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

    intraClusterMtx = skims_folder + "IntraCluster.mtx"

    // Run DC Loop over categories and time periods
    periods = RunMacro("Get Unconverged Periods", Args)
    categories = Spec.SubModels
    for category in categories do
        {mainMode, subMode} = RunMacro("Get Mode Info", category)
        
        fName = mainMode
        if mainMode = "auto" then // Append w_ or n_
            fName = Left(category,2) + fName // "w_auto" or "n_auto"

        coeffFile = in_folder + "nhb_" + fName + "_dc.csv" // One of "nhb_w_auto_dc.csv", "nhb_n_auto_dc.csv", "nhb_transit_dc.csv", "nhb_walkbike_dc.csv"
        util = RunMacro("Import MC Spec", coeffFile)
        
        for period in periods do
            tag = "NHB_" + category + "_" + period

            if subMode = 'walkbike' then
                skimFile = skims_folder + "nonmotorized/walk_skim.mtx"
            else if subMode = 'transit' then
                skimFile = skims_folder + "transit/skim_" + period + "_w_all.mtx"
            else if subMode = 'sov' then
                skimFile = skims_folder + "roadway/skim_sov_" + period + ".mtx"
            else // auto_pay, hov2 or hov3
                skimFile = skims_folder + "roadway/skim_hov_" + period + ".mtx"
            
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

            // Convert any nulls to zero in the resulting trip matrix
            mtx = CreateObject("Matrix", trips_folder + tag + ".mtx")
            core_names = mtx.GetCoreNames()
            for core_name in core_names do
                core = mtx.GetCore(core_name)
                core := nz(core)
            end
        end
    end
endMacro

Macro "Get Mode Info"(category)
    categoryL = Lower(category)
    if categoryL contains "transit" or categoryL contains "_t_" then do
        mainMode = "transit"
        subMode = "transit"
    end
    else if categoryL contains "walkbike" then do
        mainMode = "walkbike"
        subMode = "walkbike"
    end
    else do
        mainMode = "auto"
        if categoryL contains "sov" then
            subMode = "sov"
        if categoryL contains "hov2" then
            subMode = "hov2"
        if categoryL contains "hov3" then
            subMode = "hov3"
        if categoryL contains "auto_pay" then
            subMode = "auto_pay"
    end
    Return({mainMode, subMode})    
endMacro