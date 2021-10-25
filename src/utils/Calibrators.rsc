Macro "Calibrate NM" (Args)
    
    base_dir = Args.[Base Folder]
    param_dir = Args.[Input Folder] + "/resident/nonmotorized"
    obs_share_file = base_dir + "/docs/data/output/nonmotorized/calibration_targets.csv"
    obs_share_field = "nonmotorized"
    summary_dir = Args.[Output Folder] + "/_summaries"
    est_share_file = summary_dir + "/nm_summary.csv"
    est_share_field = "nm_share"

    max_iterations = 3
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