Macro "Parking Model"(Args)

    RunMacro("Parking Availability", Args)
    RunMacro("Parking Destination Choice", Args)
    RunMacro("Parking Destination Logsums", Args)
    RunMacro("Parking Mode Choice", Args)
    Return(1)

endMacro


/*
    Macro that computes a matrix of parking availbaility.
    Parking only allowed for zones within the same parking district
    Parking district indicated by ParkDistrict field in SE Data
*/
Macro "Parking Availability"(Args)
    output_dir = Args.[Output Folder]

    se_vw = OpenTable("SE", "FFB", {Args.SE})
    v = GetDataVector(se_vw + "|", "ParkDistrict",)
    arrDists = SortArray(v2a(v), {Unique: 'True'})

    // Create output matrix
    walkSkim = output_dir + "/skims/nonmotorized/walk_skim.mtx"
    parkAvailMtx = output_dir + "/resident/parking/ParkAvailability.mtx"
    m = OpenMatrix(walkSkim,)
    mc = CreateMatrixCurrency(m,,,,)
    matOpts = {"File Name": parkAvailMtx, Label: "ParkingAvailability", Tables: {"Availability"}}
    mOut = CopyMatrixStructure({mc}, matOpts)
    mc = null
    m = null

    // Fill output matrix
    mcOut = CreateMatrixCurrency(mOut,,,,)
    mcOut := 0
    for dist in arrDists do
        if dist = 0 or dist = null then
            continue

        // Build matrix index and fill matrix
        idxName = "ParkDistrict" + string(dist) 
        SetView(se_vw)
        n = SelectByQuery("Selection", "several", "Select * where ParkDistrict = " + string(dist),)
        CreateMatrixIndex(idxName, mOut, "Both", se_vw + "|Selection", "TAZ", "TAZ")
        mcOut = CreateMatrixCurrency(mOut,,idxName, idxName,)
        mcOut := 1
    end
    mcOut = null

    // Create CBD and Univ index for ease of model application
    types = {"CBD", "Univ"}
    qrys = {"ParkDistrict > 0 and ParkCostU = 0", "ParkDistrict > 0 and ParkCostU > 0"}
    for i = 1 to types.length do
        SetView(se_vw)
        n = SelectByQuery("Selection", "several", "Select * where " + qrys[i],)
        CreateMatrixIndex(types[i], mOut, "Both", se_vw + "|Selection", "TAZ", "TAZ")
    end
    mOut = null
    CloseView(se_vw)
endMacro


/*
    Macro that calls destination choice models for a combination of:
    Mode:
        A. Park and Walk
        B. Park and Shuttle

    Destination Type:
        A. CBD
        B. Univ

    Tour Type:
        A. Work
        B. NonWork (Other)

    Macro fills a utility matrix and a probability matrix (each matrix has eight cores). 
    Each core is a combination of mode, destination type and tour type
*/
Macro "Parking Destination Choice"(Args)
    output_dir = Args.[Output Folder]
    modes = {'Walk', 'Shuttle'}
    destTypes = {'CBD', 'Univ'}
    tourTypes = {'Work', 'NonWork'}

    // Create empty utility and probability matrix
    parkAvailMtx = output_dir + "/resident/parking/ParkAvailability.mtx"
    m = OpenMatrix(parkAvailMtx,)
    mc = CreateMatrixCurrency(m,,,,)
    
    parkUtilMtx = Args.[Parking DC Util Matrix]
    matOpts = {"File Name": parkUtilMtx, Label: "Parking DC Utility"}
    mUtil = CopyMatrix(mc, matOpts)

    parkProbMtx = Args.[Parking DC Prob Matrix]
    matOpts = {"File Name": parkProbMtx, Label: "Parking DC Probability"}
    mProb = CopyMatrix(mc, matOpts)
    mc = null
    m = null

    // Add temporary field to se data
    se_vw = OpenTable("scenario_se", "FFB", {Args.SE})
    modify = CreateObject("CC.ModifyTableOperation", se_vw)
    modify.FindOrAddField("ParkCost", "Real", 12, 2, )
    modify.FindOrAddField("ParkSize", "Real", 12, 2, )
    modify.Apply()

    // Loop over, run DC model and write to utility matrix
    pbar = CreateObject("G30 Progress Bar", "Running Parking DC Model for combination of (Walk, Shuttle), (CBD, Univ), (Work, NonWork)", true, 8)
    for mode in modes do
        for destType in destTypes do
            for tourType in tourTypes do
                // Fill appropriate parking cost field in 'ParkCost' field
                RunMacro("Parking: Fill Fields", {View: se_vw, DestType: destType, TourType: tourType})

                // Modify template model and run DC model (Note SE View is assumed to be open here)
                retDC = RunMacro("Parking: Evaluate DC", Args, {Mode: mode, DestType: destType, TourType: tourType})

                // Update utility and probability matrix
                modelTag = mode + "_" + destType + "_" + tourType
                RunMacro("Parking: Update Util and Prob", {ModelTag: modelTag, UtilMtx: mUtil, ProbMtx: mProb, DCOutput: retDC})

                if pbar.Step() then
                    Return()
            end
        end
    end
    pbar.Destroy()

    // Remove temp field from se_table
    modify.DropField("ParkCost")
    modify.DropField("ParkSize")
    modify.Apply()

    CloseView(se_vw)
    mProb = null
    mUtil = null
endMacro


/*
    Macro that fill the appropriate park cost field into the common field called 'ParkCost' before running the destination choice model
*/
Macro "Parking: Fill Fields"(spec)
    // Get appropriate parking cost field
    if spec.TourType = 'Work' then do// 'CBD' + 'Work' or 'Univ' + 'Work'
        parkCost = 'ParkCostW'
        spacesFld = 'EmpSpaces'
    end
    else if spec.DestType = 'Univ' then do     // 'Univ' + 'NonWork')
        parkCost = 'ParkCostU'
        spacesFld = 'StudSpaces'
    end
    else do                               // 'CBD' + 'NonWork'
        parkCost = 'ParkCostO'
        spacesFld = 'OtherSpaces'
    end

    // Copy case specific parking cost values into temporary 'ParkCost' field in SE Data
    se_vw = spec.View
    vecs = GetDataVectors(se_vw + "|", {parkCost, spacesFld},)

    vecsSet = null
    vecsSet.ParkCost = i2r(vecs[1])/100
    vecsSet.ParkSize = if vecs[2] > 0 then log(vecs[2]) else -99
    SetDataVectors(se_vw + "|", vecsSet,)
endMacro


/*
    Macro that updates the template model and runs destination choice for parking
    Macro called for a particular segment (e.g. Park-Walk for CBD Work Tour)
    
    Updates to template model include:
    A. Changing the base index of the matrix ('CBD' or 'Univ')
    B. Updating walk time and parking cost coefficients from the specified parameters

    The DC model is run and the resulting probability and utility matrix are returned
*/
Macro "Parking: Evaluate DC"(Args, spec)
    mode = spec.Mode
    destType = spec.DestType
    tourType = spec.TourType
    modelTag = mode + "_" + destType + "_" + tourType
    output_dir = Args.[Output Folder]

    // Create DC Model file from template
    dcmFile = RunMacro("Parking: Create DCM File", Args, spec)
    
    // Matrices (input and output)
    parkAvailMtx = output_dir + "/resident/parking/ParkAvailability.mtx"
    walkSkimMtx = output_dir + "/skims/nonmotorized/walk_skim.mtx"
    probMtx = GetRandFileName("Prob*.mtx")
    utilMtx = GetRandFileName("Util*.mtx")
    
    // Run DC
    o = CreateObject("Choice.Destination")
    o.ModelFile = dcmFile
    o.OpenMatrixSource({SourceName: "ParkingZones", FileName: parkAvailMtx})
    o.OpenMatrixSource({SourceName: "WalkSkim", FileName: walkSkimMtx})
    o.ProbabilityMatrix({MatrixFile: probMtx, MatrixLabel: "Parking Prob: " + modelTag})
    o.UtilityMatrix({MatrixFile: utilMtx, MatrixLabel: "Parking Utility: " + modelTag})
    res = o.Run()

    Return({ProbabilityMatrix: probMtx, UtilityMatrix: utilMtx})
endMacro


/*
    Macro that takes the appropriate template mode; and create an output model
    Updates to template model include:
        A. Changing the base index of the matrix ('CBD' or 'Univ')
        B. Updating walk time and parking cost coefficients from the specified parameters
    Returns output dcm model file name
*/
Macro "Parking: Create DCM File"(Args, spec)
    mode = spec.Mode
    destType = spec.DestType
    tourType = spec.TourType
    modelTag = mode + "_" + destType + "_" + tourType
    
    // Make a copy of the template file for modification
    templateFile = Args.[Input Folder] + "/resident/parking/ParkAnd" + mode + ".dcm"
    dcmFile = Args.[Output Folder] + "/resident/parking/ParkAnd" + modelTag + ".dcm"
    CopyFile(templateFile, dcmFile)

    // Open DCM file and change certain paramters
    model = CreateObject("NLM.Model")
    model.Read(dcmFile, true)

    // Change row and col index of primary source
    primarySrc = model.GetDataSource("ParkingZones")
    primarySrc.RowIdx = destType // "CBD" or "Univ"
    primarySrc.ColIdx = destType

    // Change label of transit Skim Source (only for park and shuttle)
    if tourType = "Work" then
        tSkim = Args.[Output Folder] + "\\skims\\transit\\skim_AM_w_lb.mtx"
    else
        tSkim = Args.[Output Folder] + "\\skims\\transit\\skim_MD_w_lb.mtx"
    
    m = OpenMatrix(tSkim,)
    label = GetMatrixName(m)
    m = null

    tSkimSrc = model.GetDataSource("TransitSkim")
    if tSkimSrc <> null then do     // Note tSkimSrc = null for the Park and Walk model
        tSkimSrc.FileName = tSkim
        tSkimSrc.FileLabel = label
    end

    // Change destination index of the composite alternative
    seg = model.GetSegment("*")
    alt = seg.GetAlternative("ParkingZones")
    alt.DestIdx = destType
    
    // Update walk time and parking cost coefficients
    parkingCoeffs = Args.("Park" + mode + "Coeffs")
    coeffNames = parkingCoeffs.[Coefficient Name]
    coeffCol = destType + " " + tourType
    coeffs = parkingCoeffs.(coeffCol)
    for i = 1 to coeffNames.length do
        coeffName = coeffNames[i]
        term = seg.GetTerm(coeffName)
        term.Coeff = coeffs[i]
    end
    model.Write(dcmFile)
    model.Clear()
    Return(dcmFile)
endMacro


/*
    Macro that updates the main utility and probability matrix
    - One core for each segment
    - Updated from temporary matrices produced by the DC evaluation
*/
Macro "Parking: Update Util and Prob"(spec)
    coreName = spec.ModelTag
    retDC = spec.DCOutput

    // Utility Matrix Update
    mtxHandles = {spec.UtilMtx, spec.ProbMtx}
    DCMtxs = {retDC.UtilityMatrix, retDC.ProbabilityMatrix}
    for i = 1 to mtxHandles.length do
        m = mtxHandles[i]
        cores = GetMatrixCoreNames(m)
        if ArrayPosition(cores, {coreName},) = 0 then
            AddMatrixCore(m, coreName)
        
        mc = CreateMatrixCurrency(m, coreName,,,)
        mTemp = OpenMatrix(DCMtxs[i],)
        mcTemp = CreateMatrixCurrency(mTemp,,,,)
        MergeMatrixElements(mc, {mcTemp},,,)
        mcTemp = null
        mTemp = null
        mc = null
    end
endMacro


/*
    Create the logsums table from the destination choice utility matrices
    - One field for each category (e.g. ParkWalk_CBD_Work)
*/
Macro "Parking Destination Logsums"(Args)
    // Create output logsum table
    outputTable = Args.[Parking Logsums Table]
    se_vw = OpenTable("SE", "FFB", {Args.SE})
    expOpts = { "Row Order": {{"TAZ", "Ascending"}} }
    ExportView(se_vw + "|", "FFB", outputTable, {"TAZ", "ParkDistrict", "ParkCostW", "ParkCostO", "ParkCostU"}, expOpts)
    CloseView(se_vw)
    
    // Open utility matrix
    parkUtilMtx = Args.[Parking DC Util Matrix]
    mUtil = OpenMatrix(parkUtilMtx,)
    cores = GetMatrixCoreNames(mUtil)
    if ArrayPosition(cores, {"Scratch"},) = 0 then  // Add temporary core for calculating exp(util)
        AddMatrixCore(mUtil, "Scratch")

    // Run through each combination of mode, destination type and tour type and compute logsums using appropriate utility matrix
    vecsSet = null
    for core in cores do
        if core contains "CBD" then
            dType = "CBD"
        else if core contains "Univ" then
            dType = "Univ"
        else
            continue // For the 'Availability' core

        mc = CreateMatrixCurrency(mUtil, core, dType, dType,)           // Use index to simplify calculation
        mcT = CreateMatrixCurrency(mUtil, "Scratch", dType, dType,)
        mcT := exp(mc)

        {baseRIdx, baseCIdx} = GetMatrixBaseIndex(mUtil)
        mcOut = CreateMatrixCurrency(mUtil, "Scratch", baseRIdx, baseCIdx,)  // Use with default indices (all zones)
        v = GetMatrixVector(mcOut, {Marginal: "Row Sum"})
        vecsSet.(core) = if v = 0 then null else log(v)
        mcT := null // So as not to affect the next computation

        mcT = null
        mc = null
    end

    // Add fields to logsum table and write it out
    vwOut = OpenTable("Logsums", "FFB", {outputTable})
    modify = CreateObject("CC.ModifyTableOperation", vwOut)
    for core in cores do
        modify.FindOrAddField(core, "Real", 12, 2, )
    end
    modify.Apply()
    SetDataVectors(vwOut + "|", vecsSet,)
    CloseView(vwOut)
    
    // Drop the temp matrix core
    SetMatrixCore(mUtil, cores[1])
    DropMatrixCore(mUtil, "Scratch")
    mUtil = null
endMacro


/* 
    Run the parking mode choice model to determine probability between Park-Walk and Park-Shuttle
    This is run for a combination of destination type (CBD/Univ) and tour type (Work/NonWork)
    
    The utility equation for a combination is
    Util_Walk = Logsum_Walk
    Util_Shuttle = Logsum_Shuttle + alpha 

    The value of alpha is read from a specified table in the interface

    The macro generates probability vectors (4 of them) and adds them to the logsums table
    Each vector is the probability of Walk (i.e., Park and Walk) mode. 
    There is one vector for each combination of destination type and tour type
    Note that P_ParkandShuttle = 1.0 - P_ParkandWalk

    Probabilities computed using vector manipulation directly
*/
Macro "Parking Mode Choice"(Args)

    outputTable = Args.[Parking Logsums Table]
    vwOut = OpenTable("Output", "FFB", {outputTable})
    modify = CreateObject("CC.ModifyTableOperation", vwOut)

    vecsSet = null
    destTypes = {'CBD', 'Univ'}
    tourTypes = {'Work', 'NonWork'}
    for destType in destTypes do
        for tourType in tourTypes do
            // Get ASC for 'ParkandShuttle' mode for a given combination of destType and tourType
            coeffColName = destType + " " + tourType
            coeffCol = Args.ParkMCCoeffs.(coeffColName)
            ascVal = coeffCol[1]
            
            // Get Logsum fields from table for 'ParkandWalk' and 'ParkandShuttle' for a given combination of destType and tourType
            flds = {"Walk_" + destType + "_" + tourType, "Shuttle_" + destType + "_" + tourType}
            vecs = GetDataVectors(vwOut + "|", flds,)
            
            // Calculate binary logit probability of 'ParkAndShuttle' mode
            vUtilWalk = vecs[1]
            vUtilShuttle = vecs[2] + ascVal
            vProb = exp(vUtilShuttle)/(exp(vUtilShuttle) + exp(vUtilWalk))
            vLS = log(exp(vUtilShuttle) + exp(vUtilWalk))
            
            outFld = "Prob_Shuttle_" + destType + "_" + tourType
            lsFld = "MC_LS_" + destType + "_" + tourType
            modify.FindOrAddField(outFld, "Real", 12, 2, )
            modify.FindOrAddField(lsFld, "Real", 12, 2, )
            vecsSet.(outFld) = vProb
            vecsSet.(lsFld) = vLS
        end
    end

    // Add fields and fill output vector
    modify.Apply()
    SetDataVectors(vwOut + "|", vecsSet,)

    // Post process
    // Get default MC Logsum
    se_vw = OpenTable("SE", "FFB", {Args.SE})
    vEmp = GetDataVector(se_vw + "|", "EmpSpaces",)
    maxSpaces = VectorStatistic(vEmp, "Max",)
    defaultMCLS = log(2.5*maxSpaces*6)
    RunMacro("PostProcess Logsum Table", vwOut, defaultMCLS)
    CloseView(vwOut)
endMacro


/*
Collapse logsum and probabilty fields
E.g. Merge logsum fields 'Walk_CBD_Work' and 'Walk_Univ_Work' into new fields 'LS_Walk_Work'
Note that univ and CBD zones are mutually exclusive. 
Therefore at least one of the fields 'Walk_CBD_Work' and 'Walk_Univ_Work' is always null
*/
Macro "PostProcess Logsum Table"(vwOut, defaultMCLS)

    modes = {'Walk', 'Shuttle'}
    tourTypes = {'Work', 'NonWork'}
    // LS Fields
    for mode in modes do
        for tourType in tourTypes do
            RunMacro("Update Fields", {View: vwOut, 
                                       CBDField: mode + "_CBD_" + tourType, 
                                       UnivField: mode + "_Univ_" + tourType, 
                                       OutputField: "DC_LS_" + mode + "_" + tourType})
        end
    end

    // Prob and MC LS Fields
    for tourType in tourTypes do
        RunMacro("Update Fields", {View: vwOut, 
                                   CBDField: "Prob_Shuttle_CBD_" + tourType, 
                                   UnivField: "Prob_Shuttle_Univ_" + tourType, 
                                   OutputField: "Prob_Shuttle_" + tourType})

        
        RunMacro("Update Fields", {View: vwOut, 
                                   CBDField: "MC_LS_CBD_" + tourType, 
                                   UnivField: "MC_LS_Univ_" + tourType, 
                                   OutputField: "MC_LS_" + tourType,
                                   DefaultValue: defaultMCLS})
    end 
endMacro


Macro "Update Fields"(spec)
    vwOut = spec.View
    modify = CreateObject("CC.ModifyTableOperation", vwOut)
    vecs = GetDataVectors(vwOut + "|", {spec.CBDField, spec.UnivField},)
    outFld = spec.OutputField
    vOut = if vecs[1] <> null then vecs[1]
           else if vecs[2] <> null then vecs[2]
           else spec.DefaultValue
    modify.FindOrAddField(outFld, "Real", 12, 2, )
    modify.DropField(spec.CBDField)
    modify.DropField(spec.UnivField)
    modify.Apply()
    modify = null

    SetDataVector(vwOut + "|", outFld, vOut,)
endMacro

/*
This macro splits auto trip matrices into those who walk from their car
and those who take a shuttle.
*/

Macro "Apply Parking Mode Probabilities" (Args)

    out_dir = Args.[Output Folder]
    parking_dir = out_dir + "/output/resident/parking"
    trip_dir = out_dir + "/resident/trip_matrices"
    logsum_file = parking_dir + "/ParkingLogsums.bin"
    parking_prob_file = parking_dir + "/ParkingDCProbability.mtx"

    trip_types = RunMacro("Get HB Trip Types", Args)
    periods = RunMacro("Get Unconverged Periods", Args)

    for period in periods do
        for trip_type in trip_types do
            trip_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
            if Lower(Left(trip_type, 1)) = "w"
                then park_type = "work"
                else park_type = "nonwork"

            opts.parking_prob_file = parking_prob_file
            opts.logsum_file = logsum_file
            opts.trip_file = trip_file
            opts.park_type = park_type
            opts.auto_cores = {
                "sov",
                "hov2",
                "hov3",
                "auto_pay",
                "other_auto"
            }
            RunMacro("Separate Parking Trips")
        end
    end
endmacro

/*

*/

Macro "Separate Parking Trips" (MacroOpts)
    
    parking_prob_file = MacroOpts.parking_prob_file
    logsum_file = MacroOpts.logsum_file
    trip_file = MacroOpts.trip_file
    park_type = MacroOpts.park_type
    auto_cores = MacroOpts.auto_cores

    // Get walk/shuttle split from logsum file
    logsum_vw = OpenTable("logsums", "FFB", {logsum_file})
    if Lower(park_type) = "work"
        then prob_field = "Prob_Shuttle_Work"
        else prob_field = "Prob_Shuttle_NonWork"
    v_prob_shuttle = GetDataVector(logsum_vw + "|", prob_field, )
    v_prob_shuttle = nz(v_prob_shuttle)
    CloseView(logsum_vw)

    // // Create a temp copy of the trip matrix
    // {drive, path, name, ext} = SplitPath(trip_file)
    // trip_file_copy = drive + path + name + "_copy.mtx"
    // CopyFile(trip_file, trip_file_copy)

    trip_mtx = CreateObject("Matrix", trip_file)
    prob_mtx = CreateObject("Matrix", parking_prob_file)
    park_modes = {"Walk", "Shuttle"}
    for auto_core in auto_cores do
        for park_mode in park_modes do
            // Holds trips by parking mode (walk or shuttle)
            park_mode_core =  auto_core + "_park" + park_mode
            // Holds trips after multiplying by parking DC %s
            mult_core = park_core + "_multi"
            trip_mtx.AddCores({park_mode_core})
            cores = trip_mtx.GetCores()
            
            if park_mode = "Shuttle"
                then cores.(park_mode_core) := cores.(auto_core) * v_prob_shuttle
                else cores.(park_mode_core) := cores.(auto_core) * (1 - v_prob_shuttle)
        end
    end

endmacro

Macro "Parking Convolution" (MacroOpts)

    trip_mtx_file = MacroOpts.trip_mtx_file
    trip_core_name = MacroOpts.trip_core_name
    parking_mtx_file = MacroOpts.parking_mtx_file
    parking_core_name = MacroOpts.parking_core_name

    // For any parking matrix rows with null total probabilities,
    // put a 1 on the diagonal.
    prk_mtx = CreateObject("Matrix", parking_mtx_file)
    v_row_sum = prk_mtx.GetVector({Core: parking_core_name, Marginal: "Row Sum"})
    v_row_sum.rowbased = true
    v_diag = prk_mtx.GetVector({Core: parking_core_name, Diagonal: "Row"})
    v_diag = if v_row_sum = 0 then 1 else v_diag
    prk_mtx.SetVector({Core: parking_core_name, Vector: v_diag, Diagonal: true})
    prk_core = prk_mtx.GetCore(parking_core_name)
    prk_core := nz(prk_core)

    // Calculate Origin-to-Parking matrix
    // Multiply trips with parking probabilities
    trip_mtx = CreateObject("Matrix", trip_mtx_file)
    trip_core = trip_mtx.GetCore(trip_core_name)
    {drive, path, name, ext} = SplitPath(trip_mtx_file)
    topark_mtx_file = drive + path + name + "_toparking.mtx"
    mh = MultiplyMatrix(trip_core, prk_core, {
        "File Name": topark_mtx_file
    })
    temp_mtx = CreateObject("Matrix", mh)
    result_cur = temp_mtx.GetCore(trip_core_name)
    trip_mtx.AddCores({trip_core_name + "_topark"})
    topark_core = trip_mtx.GetCore(trip_core_name + "_topark")
    topark_core := result_cur
    mh = null
    temp_mtx = null
    result_cur = null
    DeleteFile(topark_mtx_file)

    // Calculate Parking-to-Destination matrix
    frompark_core_name = trip_core_name + "_frompark"
    trip_mtx.AddCores({frompark_core_name})
    frompark_core = trip_mtx.GetCore(frompark_core_name)
    trip_rowsum = trip_mtx.GetVector({
        Core: trip_core_name,
        Marginal: "Column Sum"
    })
    trip_rowsum.rowbased = false
    frompark_core := prk_core * trip_rowsum

    v_zeros = Vector(trip_rowsum.length, "Float", {Constant: 0})
    trip_mtx.SetVector({
        Core: frompark_core_name,
        Vector: v_zeros,
        Diagonal: true
    })    
    {drive, path, name, ext} = SplitPath(trip_mtx_file)    
    trans_mtx_file = drive + path + name + "_transposed.mtx"
    trip_mtx.Transpose({
        OutputFile: trans_mtx_file,
        Cores: {frompark_core_name}
    })
    trans_mtx = CreateObject("Matrix", trans_mtx_file)
    trans_core = trans_mtx.GetCore(frompark_core_name)
    frompark_core := trans_core
    trans_mtx = null
    trans_core = null
    DeleteFile(trans_mtx_file)
endmacro