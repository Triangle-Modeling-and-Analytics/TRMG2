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
    periods = Args.periods
    se_file = Args.SE
    trip_types = RunMacro("Get NHB Trip Types", Args)
    modes = {"sov", "hov2", "hov3", "auto_pay", "walkbike", "lb"}

    // Create the output table with initial fields
    out_file = out_dir + "/resident/nhb/generation.bin"
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

    for trip_type in trip_types do
        for mode in modes do
            
            // Get the generation parameters for this type+mode combo
            file = param_dir + "/" + trip_type + "_" + mode + ".csv"
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
// TODO: remove after testing
hb_trip_type = "W_HB_W_All"
hb_mode = "sov"
i = params.length + 1

                    hb_mtx_file = trip_dir + "/pa_per_trips_" + hb_trip_type + "_" + period + ".mtx"
                    hb_mtx = CreateObject("Matrix", hb_mtx_file)
                    v = hb_mtx.GetVector(hb_mode, {Marginal: "Column Sum"})
                    v.rowbased = "true"
                    data.(field_name) = nz(data.(field_name)) + nz(v) * coef
                end

                // Boosting
                if alpha <> null then do
                    access_field = if mode = "walkbike" then "access_walk"
                        else if mode = "lb" then "access_transit"
                        else "access_nearby_sov"
                    boost_factor = pow(access.(access_field), gamma) * alpha
                    data.(field_name) = data.(field_name) * boost_factor
                end
            end
        end
    end

    RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
    SetDataVectors(out_vw + "|", data, )
    CloseView(out_vw)
endmacro