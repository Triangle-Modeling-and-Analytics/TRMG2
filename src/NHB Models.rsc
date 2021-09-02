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

    param_dir = Args.[Input Folder] + "/nhb/generation"
    out_dir = Args.[Output Folder]
    trip_dir = out_dir + "/resident/trip_tables"
    periods = Args.periods
    trip_types = RunMacro("Get NHB Trip Types", Args)
    modes = {"sov", "hov2", "hov3", "auto_pay", "walkbike", "lb"}

    out_file = out_dir + "/resident/nhb/generation.bin"
    out_vw = CreateTable("out", out_file, "FFB", {
        {"TAZ", "Integer", 10, , , "Zone ID"}
    })

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
            params.alpha = null
            params.gamma = null
            params.r_sq = null

            // Create period-specific generation fields
            for period in periods do
                field_name = trip_type + "_" + mode + "_" + period
                fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, ""}}
                

                // The remaining params are generation coefficients
                for i = 1 to params.length do
                    param = params[i][1]
                    coef = params.(param)

                    {hb_trip_type, hb_mode} = RunMacro("Separate type and mode", param)
// TODO: remove after testing
hb_trip_type = "W_HB_W_All"
hb_mode = "sov"

                    hb_mtx_file = trip_dir + "/pa_per_trips_" + hb_trip_type + "_" + period + ".mtx"
                    hb_mtx = CreateObject("Matrix", hb_mtx_file)
                    if data = null then do
                        data.TAZ = hb_mtx.GetVector(hb_mode, {Index: "Row"})
                        AddRecords(out_vw, , , {"empty records": data.TAZ.length})
                    end
                    v = hb_mtx.GetVector(hb_mode, {Marginal: "Column Sum"})
                    v.rowbased = "true"
                    data.(field_name) = nz(data.(field_name)) + nz(v) * coef
// TODO: add alpha/gamma
Throw()
                end
            end
        end
    end
    
    RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
    SetDataVectors(out_vw + "|", data, )
    CreateEditor('ed', out_vw + "|", , )

    CloseView(out_vw)
endmacro