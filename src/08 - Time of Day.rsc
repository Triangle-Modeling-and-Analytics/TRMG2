/*

*/

Macro "Time of Day Split" (Args)

    RunMacro("Resident HB TOD", Args)
    return(1)
endmacro

/*

*/

Macro "Resident HB TOD" (Args)

    se_file = Args.SE
    tod_file = Args.ResTODFactors

    se_vw = OpenTable("per", "FFB", {se_file})
    fac_vw = OpenTable("tod_fac", "CSV", {tod_file})
    v_type = GetDataVector(fac_vw + "|", "trip_type", )
    v_tod = GetDataVector(fac_vw + "|", "tod", )
    v_fac = GetDataVector(fac_vw + "|", "factor", )

    for i = 1 to v_type.length do
        type = v_type[i]
        tod = v_tod[i]
        fac = v_fac[i]

        if type = "W_HB_W_All"
            then segments = {"v0", "ilvi", "ilvs", "ihvi", "ihvs"}
            else segments = {"v0", "vi", "vs"}

        for segment in segments do
            daily_name = type + "_" + segment
            v_daily = GetDataVector(se_vw + "|", daily_name, )
            v_result = v_daily * fac
            field_name = daily_name + "_" + tod
            a_fields_to_add = a_fields_to_add + {
                {field_name, "Real", 10, 2,,,, "Resident HB productions by TOD"}
            }
            data.(field_name) = v_result
        end
    end
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields_to_add})
    SetDataVectors(se_vw + "|", data, )    
    CloseView(se_vw)
    CloseView(fac_vw)
endmacro