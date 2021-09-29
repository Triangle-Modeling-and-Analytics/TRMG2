/*
These models generate and distribute NHB trips based on the results of the HB
models.
*/

Macro "NonHomeBased" (Args)

    RunMacro("NHB Generation", Args)
    return(1)
endmacro

/*

*/

Macro "NHB Generation" (Args)

    param_dir = Args.[Input Folder] + "/resident/nhb/generation"
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_tables"
    periods = RunMacro("Get Unconverged Periods", Args)
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