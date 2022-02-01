Macro "Calibrate NM" (Args)
    
    base_dir = Args.[Base Folder]
    param_dir = Args.[Input Folder] + "/resident/nonmotorized"
    obs_share_file = base_dir + "/docs/data/output/nonmotorized/calibration_targets.csv"
    obs_share_field = "nonmotorized"
    summary_dir = Args.[Output Folder] + "/_summaries"
    est_share_file = summary_dir + "/nm_summary.csv"
    est_share_field = "nm_share"

    max_iterations = 6
    gap_target = .1

    trip_types = RunMacro("Get HB Trip Types", Args)
    for trip_type in trip_types do
        if trip_type = "W_HB_EK12_All" then continue

        iter = 1
        while iter <= max_iterations do

            // Use the model's macros to run NM for this trip_type
            RunMacro("Calculate NM Probabilities", Args, {trip_type})
            RunMacro("Separate NM Trips", Args, {trip_type})
            RunMacro("Aggregate HB NonMotorized Walk Trips", Args, {trip_type})
            RunMacro("Summarize NM", Args, {trip_type})

            // Get observed and estimated shares
            obs_share = RunMacro("Get Share", {
                file: obs_share_file,
                trip_type: trip_type,
                col_name: obs_share_field
            })
            est_share = RunMacro("Get Share", {
                file: est_share_file,
                trip_type: trip_type,
                col_name: est_share_field
            })

            gap = abs(est_share - obs_share)

            constant = round(Log(obs_share/est_share) * .75, 4)
            param_file = param_dir + "/" + trip_type + ".csv"
            line = "nonmotorized,Constant,," + String(constant) + ",Added by calibrator routine. gap = " + String(gap)
            RunMacro("Append Line", {file: param_file, line: line})

            if gap <= gap_target then break
            iter = iter + 1
        end
    end

    ShowMessage("Nonmotorized calibration complete")
endmacro

Macro "Get Share" (MacroOpts)

    file = MacroOpts.file
    trip_type = MacroOpts.trip_type
    col_name = MacroOpts.col_name

    vw = OpenTable("vw", "CSV", {file})
    trip_types = GetDataVector(vw + "|", "trip_type", )
    pos = trip_types.position(trip_type)
    shares = GetDataVector(vw + "|", col_name, )
    share = shares[pos]
    CloseView(vw)
    return(share)
endmacro

Macro "Append Line" (MacroOpts)
    file = MacroOpts.file
    line = MacroOpts.line

    f = OpenFile(file, "a")
    WriteLine(f, line)
    CloseFile(f)
endmacro

/*

*/

Macro "Calibrate AO" (Args)
    
    base_dir = Args.[Base Folder]
    param_dir = Args.[Input Folder] + "/resident/auto_ownership"
    param_file = param_dir + "/ao_coefficients.csv"
    obs_share_file = base_dir + "/docs/data/output/auto_ownership/ao_calib_targets.csv"
    hh_file = Args.Households

    // Get observed percentages
    obs_vw = OpenTable("obs", "CSV", {obs_share_file})
    v_obs = GetDataVector(obs_vw + "|", "pct", )
    CloseView(obs_vw)

    max_iterations = 6
    iter = 1
    gap_target = .02

    while iter <= max_iterations do
        
        // Run model
        RunMacro("Calculate Auto Ownership", Args)

        // Calculate deltas and gaps
        hh_vw = OpenTable("hh", "FFB", {hh_file})
        agg_vw = SelfAggregate(hh_vw, hh_vw + ".Autos", )
        v_count = GetDataVector(agg_vw + "|", "Count(hh)", )
        CloseView(agg_vw)
        CloseView(hh_vw)
        if v_count.length <> v_obs.length then Throw("Observed and model vector are different lenghts")
        total = VectorStatistic(v_count, "Sum", )
        v_est = v_count / total
        v_delta = round(log(v_obs / v_est) * .9, 4)
        v_gap = abs(v_obs - v_est)

        // Write out calibration constants
        for i = 2 to v_obs.length do
            delta = v_delta[i]
            gap = v_gap[i]
            line = "v" + String(i - 1) + ",Constant,," + String(delta) + ",Added by calibrator routine. gap = " + String(gap)
            RunMacro("Append Line", {file: param_file, line: line})
        end
        
        // Check convergence
        max_gap = VectorStatistic(v_gap, "Max", )
        if max_gap <= gap_target then break
        iter = iter + 1
    end
    

    ShowMessage("Auto ownership calibration complete")
endmacro

/* 
    Generic MC Calibrator
    Runs loop over trip types and market segments and adjusts model ASCs
    Finally writes the results to the model csv files, if chosen
*/
Macro "Calibrate HB MC"(Args)
    trip_types = RunMacro("Get HB Trip Types", Args)
    //pbar1 = CreateObject("G30 Progress Bar", "Calibrating MC models for each trip type ...", true, trip_types.length)
    for trip_type in trip_types do
        if Lower(trip_type) = "w_hb_ek12_all" then
            continue

        if Lower(trip_type) = "w_hb_w_all" then 
            segments = {"v0", "ilvi", "ilvs", "ihvi", "ihvs"}
        else 
            segments = {"v0", "vi", "vs"}

        pbar2 = CreateObject("G30 Progress Bar", "Calibrating segment specific MC models for " + trip_type, true, segments.length)
        for segment in segments do
            if Lower(trip_type) = "n_hb_omed_all" and segment <> "v0" then
                dampingFactor = 0.1
            else if Lower(trip_type) = "n_hb_od_short" and segment <> "v0" then
                dampingFactor = 0.25
            else
                dampingFactor = 0.5

            converged = RunMacro("Calibrate MC", Args, {TripType: trip_type, Segment: segment, Iterations: 50, UpdateCSVSpec: 1, AdjustmentScale: dampingFactor})
            AppendToReportFile(0, "MC Calibration Convergence for Trip Type '" + trip_type + "' and Segment '" + segment + "': " + String(converged))

            if pbar2.Step() then
                Return() 
        end
        pbar2.Destroy()

        //if pbar1.Step() then
            //Return() 
    end
    //pbar1.Destroy()
    ShowMessage("Calibration Complete")
endMacro


Macro "Calibrate MC"(Args, Opts)
    // Check presence of MC Files (after running the flowchart)
    RunMacro("Setup MC Model Files", Args, Opts)

    // Update the DC totals matrix using the DC probabilities
    RunMacro("Update DC Totals", Args, Opts)

    // Main Calibration Loop begins
    // Get array of alternatives and targets
    {altNames, targets} = RunMacro("Get Targets", Args, Opts)

    // A 2.0 % share threshold for convergence.
    // For example if target value is 75, then the bounds for successful convergence are [75 - 0.02*75, 75 + 0.02*75] or [73.5 76.5]
    thresholds = targets.map(do (f) Return(0.02*f) end)

    // Get array of initial ASCs from the AM model file, corresponding to the altNames
    initialASCs = RunMacro("Get ASCs", Args, Opts, altNames)

    converged = 0
    iters = 0
    maxIters = Opts.Iterations
    pbar = CreateObject("G30 Progress Bar", "Calibration Iterations...", true, maxIters)
    while (converged = 0 and iters <= maxIters) do
        // Evaluate Model
        RunMacro("MC Eval for Calibration", Args, Opts)

        // Compute Shares
        shares = RunMacro("Get Mode Shares", Args, Opts, altNames)
        //return(1)

        // Check convergence
        converged = RunMacro("ASC Adjustment Convergence", shares, targets, thresholds)
        if converged = null then
            Throw("Error in checking convergence for mode choice calibration")
            
        // Modify Model ASCs for next loop
        if converged = 0 then do
            modified = RunMacro("Modify MC Models", Args, Opts, altNames, shares, targets)
            if modified = 0 then // Did not modify model since model share of some alternative is trending to 0.
                Return(0)
        end

        iters = iters + 1

        if pbar.Step() then
            Return()
    end
    pbar.Destroy()

    // Update spec files if requested
    if Opts.UpdateCSVSpec then do
        finalASCs = RunMacro("Get ASCs", Args, Opts, altNames)
        RunMacro("Update MC CSV Spec Files", Args, Opts, altNames, initialASCs, finalASCs)
    end     
    Return(converged)
endMacro


Macro "Setup MC Model Files"(Args, Opts)
    out_dir = Args.[Output Folder]
    periods = Args.periods
    mc_dir = out_dir + "/resident/mode"
    name = Opts.TripType + "_" + Opts.Segment

    // Check presence of initial model files
    for period in periods do
        mdlFile = mc_dir + "/model_files/" + name + "_" + period + ".mdl"
        if !GetFileInfo(mdlFile) then
            Throw("TransCAD output model file(s) not found for mode choice calibration. Please run the mode choice step from the flowchart first.")
        outMdl = mc_dir + "/model_files/" + name + "_" + period + "_Calib.mdl"
        CopyFile(mdlFile, outMdl)
    end        
endMacro


// Uses the DC choice probabilities and applies the production vectors to generate DC totals for the given trip type and segment
// Repeats for each period and adds the results together into a single core
Macro "Update DC Totals"(Args, Opts)
    se_file = Args.SE
    se_vw = OpenTable("se", "FFB", {se_file})

    out_dir = Args.[Output Folder]
    dc_dir = out_dir + "/resident/dc"
    periods = Args.periods
    trip_type = Opts.TripType
    segment = Opts.Segment
    name = Opts.TripType + "_" + Opts.Segment

    // Create output DC totals matrix
    dcFile = GetTempPath() + "DCTrips_" + name + ".mtx"
    mP = dc_dir + "/probabilities/probability_" + name + "_AM_zone.mtx"
    o = CreateObject("Matrix")
    cores = null
    for period in periods do
        cores = cores + {name + "_" + period}
    end
    mOut = o.CloneMatrixStructure({MatrixLabel: "DCTrips", CloneSource: {mP}, MatrixFile: dcFile, Matrices: cores})
    mDCObj = CreateObject("Matrix", mOut)
    out_cores = mDCObj.GetCores()

    for period in periods do
        tag = name + "_" + period
        dc_mtx_file = dc_dir + "/probabilities/probability_" + tag + "_zone.mtx"
        dc_mtx = CreateObject("Matrix", dc_mtx_file)
        dc_cores = dc_mtx.GetCores()
        
        v_prods = nz(GetDataVector(se_vw + "|", tag, ))
        v_prods.rowbased = "false"

        out_cores.(tag) := nz(out_cores.(tag)) + nz(v_prods) * nz(dc_cores.final_prob)
    end

    CloseView(se_vw)
endMacro


Macro "Get Targets"(Args, Opts)
    trip_type = Opts.TripType
    segment = Opts.Segment

    // Check for targets file
    targetsFile = Args.[Input Folder] + "/resident/mode/Target_HB_MCShares.csv"
    if !GetFileInfo(targetsFile) then
        Throw("Missing target shares files for mode choice calibration")

    vw = OpenTable("Targets", "CSV", {targetsFile})
    {flds, specs} = GetFields(vw,)
    SetView(vw)
    n = SelectByQuery("Selection", "several", "Select * where Lower(Purpose) = '" + Lower(trip_type) + "' and Lower(Segment) = '" + Lower(segment) + "'", )
    if n <> 1 then
        Throw("Error in mode choice targets file. File does not have exactly one record for '" + trip_type + "' and '" + segment +"'")
    vecs = GetDataVectors(vw + "|Selection", flds, {OptArray: 1})
    CloseView(vw)
    
    altNames = null
    targets = null
    for v in vecs do
        if Lower(v[1]) = "segment" or Lower(v[1]) = "purpose" then 
            continue

        if v[2][1] > 0.0 then do // Adjust only those alteratives with positive shares
            altNames = altNames + {v[1]}
            targets = targets + {v[2][1]}
        end
    end
    Return({altNames, targets})
endMacro


Macro "Get ASCs"(Args, Opts, altNames)
    trip_type = Opts.TripType
    segment = Opts.Segment
    mc_dir = Args.[Output Folder] + "/resident/mode"
    mdlFile = mc_dir + "/model_files/" + trip_type + "_" + segment + "_AM_Calib.mdl"

    model = CreateObject("NLM.Model")
    model.Read(mdlFile, true)
    seg = model.GetSegment("*")

    dim ascs[altNames.length]
    for i = 1 to altNames.length do
        alt = seg.GetAlternative(altNames[i])
        ascs[i] = alt.ASC.Coeff
    end

    model.Clear()
    Return(ascs)
endMacro


Macro "MC Eval for Calibration"(Args, Opts)
    trip_type = Opts.TripType
    segment = Opts.Segment
    periods = Args.periods

    mc_dir = Args.[Output Folder] + "/resident/mode"
    skims_dir = Args.[Output Folder] + "/skims"

    // Run model for each period and write temporary applied totals matrices
    for period in periods do
        tag = trip_type + "_" + segment + "_" + period
        mdlFile = mc_dir + "/model_files/" + tag + "_Calib.mdl"

        // Get list of model sources
        model = CreateObject("NLM.Model")
        model.Read(mdlFile, true)
        modelSources = null
        for src in model.Sources.Items do
            modelSources = modelSources + {src[1]}
        end
        model.Clear()

        if period = "MD" or period = "NT" then do
            tour_type = "All"
            homebased = "All"
        end
        else do
            tour_type = Upper(Left(trip_type, 1))
            homebased = "HB"
        end

        mtxSources = null
        mtxSources.sov_skim = skims_dir + "/roadway/avg_skim_" + period + "_" + tour_type + "_" + homebased + "_sov.mtx"
        mtxSources.hov_skim = skims_dir + "/roadway/avg_skim_" + period + "_" + tour_type + "_" + homebased + "_hov.mtx"
        mtxSources.w_lb_skim = skims_dir + "/transit/skim_" + period + "_w_lb.mtx"
        mtxSources.w_eb_skim = skims_dir + "/transit/skim_" + period + "_w_eb.mtx"
        mtxSources.pnr_lb_skim = skims_dir + "/transit/skim_" + period + "_pnr_lb.mtx"
        mtxSources.pnr_eb_skim = skims_dir + "/transit/skim_" + period + "_pnr_eb.mtx"
        mtxSources.knr_lb_skim = skims_dir + "/transit/skim_" + period + "_knr_lb.mtx"
        mtxSources.knr_eb_skim = skims_dir + "/transit/skim_" + period + "_knr_eb.mtx"
        
        o = CreateObject("Choice.Mode")
        o.ModelFile = mdlFile
        if ArrayPosition(modelSources, {"se"},) > 0 then
            o.OpenTableSource({SourceName: "se", FileName: Args.SE})
        if ArrayPosition(modelSources, {"parking"},) > 0 then
            o.OpenTableSource({SourceName: "parking", FileName: Args.[Parking Logsums Table], ViewName: "parking"})
        for src in mtxSources do
            if ArrayPosition(modelSources, {src[1]},) > 0 then
                o.OpenMatrixSource({SourceName: src[1], FileName: src[2]})
        end
        probMtx = mc_dir + "/probabilities/probability_" + tag + ".mtx"
        o.AddMatrixOutput( "*",  {Probability: probMtx})
        o.UtilityScaling = "By Parent Theta"
        ok = o.Run()
        o = null
    end
endMacro


Macro "Get Mode Shares"(Args, Opts, altNames)
    mc_dir = Args.[Output Folder] + "/resident/mode/"
    name = Opts.TripType + "_" + Opts.Segment
    trModes = {"w_lb", "w_eb", "pnr_lb", "pnr_eb", "knr_lb", "knr_eb"}

    // Create temporary output matrix (In-Memory) and initialize to 0
    mP = mc_dir + "/probabilities/probability_" + name + "_AM.mtx"
    o = CreateObject("Matrix")
    
    mOut = o.CloneMatrixStructure({MatrixLabel: "MCTrips", CloneSource: {mP}, MemoryOnly: true, Matrices: altNames})
    mMCObj = CreateObject("Matrix", mOut)
    out_cores = mMCObj.GetCores()
    for alt in altNames do
        out_cores.(alt) := 0
    end

    // Loop over periods. Multiply DC matrix with MC probabilities to generate trips by mode. Add across periods
    dcMtx = GetTempPath() + "DCTrips_" + name + ".mtx"
    mDC = CreateObject("Matrix", dcMtx)
    dc_cores = mDC.GetCores()
    periods = Args.periods
    for period in periods do
        tag = name + "_" + period
        periodProbMtx = mc_dir + "/probabilities/probability_" + tag + ".mtx"
        mP = CreateObject("Matrix", periodProbMtx)
        alts = mP.GetCoreNames()
        for alt in alts do
            if ArrayPosition(trModes, {alt},) > 0 then
                outMode = "Transit"
            else
                outMode = alt
            
            if ArrayPosition(altNames, {outMode},) > 0 then
                out_cores.(outMode) := out_cores.(outMode) + nz(mP.GetCore(alt)) * dc_cores.(tag)     
        end
        mP = null
    end

    // Perform Matrix Statistics and return array of model shares corresponding to the altNames array
    dim shares[altNames.length]
    stats = MatrixStatistics(mOut,)
    for i = 1 to altNames.length do
        shares[i] = nz(stats.(altNames[i]).Sum)
    end
    total = Sum(shares)
    shares = shares.Map(do (f) Return (100.0*f/total) end)
    mOut = null
    Return(shares)
endMacro


Macro "Modify MC Models"(Args, Opts, altNames, shares, targets)
    out_dir = Args.[Output Folder]
    periods = Args.periods
    mc_dir = out_dir + "/resident/mode"
    name = Opts.TripType + "_" + Opts.Segment
    dampingFactor = Opts.AdjustmentScale

    // Update the model files for each period (same adjustment for each period)
    for period in periods do
        outMdl = mc_dir + "/model_files/" + name + "_" + period + "_Calib.mdl"
        model = CreateObject("NLM.Model")
        model.Read(outMdl, true)
        seg = model.GetSegment("*")
        for i = 1 to altNames.length do
            alt = seg.GetAlternative(altNames[i])
            if shares[i] > 0.0 then do // If shares[i] = 0 and targets[i] > 0, then the calibration has to be redone with a smaller damping factor.
                alt.ASC.Coeff = nz(alt.ASC.Coeff) + dampingFactor*log(targets[i]/shares[i])
                model.Write(outMdl)
            end
            else do
                AppendToReportFile(0, "Purpose: " + name + ". Model share of " + altnames[i] + " trending to 0.")
                AppendToReportFile(0, "Re-run with smaller damping (adjustment) factor")
                model.Clear()
                Return(0)
            end
        end
        model.Clear()
    end
    Return(1)
endMacro


// Returns 1 if all of the current model shares are within the target range.
Macro "ASC Adjustment Convergence"(shares, targets, thresholds)
    if shares.length <> targets.length or shares.length <> thresholds.length then
        Return()
        
    for i = 1 to shares.length do
        if shares[i] > (targets[i] + thresholds[i]) or shares[i] < (targets[i] - thresholds[i]) then // Out of bounds. Not Converged.
            Return(0)  
    end
    
    Return(1)    
endmacro


Macro "Update MC CSV Spec Files"(Args, Opts, altNames, initialASCs, finalASCs)
    in_dir = Args.[Input Folder] + "/resident/mode"
    out_dir = Args.[Output Folder] + "/resident/mode/model_files"
    trip_type = Opts.TripType
    segment = Opts.Segment
    name = trip_type + "_" + segment

    param_file = in_dir + "/" + trip_type + ".csv"
    
    mdlFile = out_dir + "/" + name + "_AM_Calib.mdl"
    model = CreateObject("NLM.Model")
    model.Read(mdlFile, true)
    seg = model.GetSegment("*")
    for i = 1 to altNames.length do
        val = nz(finalASCs[i]) - nz(initialASCs[i]) // The delta ASC
        if abs(val) < 1e-4 then 
            continue
        
        alt = altNames[i]
        modelAlt = seg.GetAlternative(alt)
        nestedAlts = modelAlt.Nested    // Returns nested altenative objects if there are alternatives below this

        if nestedAlts = null then do    // A leaf alternative
            line = alt + ",Constant," + segment + "," + String(val) + ",Additional Calibration Constant"
            RunMacro("Append Line", {file: param_file, line: line})
        end
        else do                         // Add one record for each nested alternative just below this alternative in the tree
            for z in nestedAlts do
                line = z.Name + ",Constant," + segment + "," + String(val) + ",Additional Calibration Constant"
                RunMacro("Append Line", {file: param_file, line: line})
            end
        end
    end
    model.Clear()
endMacro

