/*

*/

Macro "Time of Day" (Args)

    RunMacro("Resident TOD", Args)

    return(1)
endmacro

/*

*/

Macro "Resident TOD" (Args)

    per_file = Args.Persons
    tod_file = Args.ResTODFactors

    per_vw = OpenTable("per", "FFB", {per_file})
    fac_vw = OpenTable("tod_fac", "CSV", {tod_file})
    v_type = GetDataVector(fac_vw + "|", "trip_type", )
    v_tod = GetDataVector(fac_vw + "|", "tod", )
    v_fac = GetDataVector(fac_vw + "|", "factor", )

    prev_type = ""
    for i = 1 to v_type.length do
        type = v_type[i]
        tod = v_tod[i]
        fac = v_fac[i]

        if type <> prev_type then v_daily = GetDataVector(per_vw + "|", type, )
        v_result = v_daily * fac
        field_name = type + "_" + tod
        a_fields_to_add = a_fields_to_add + {
            {field_name, "Real", 10, 2,,,, "Resident productions by TOD"}
        }
        data.(field_name) = v_result

        prev_type = type
    end
    RunMacro("Add Fields", {view: per_vw, a_fields: a_fields_to_add})
    SetDataVectors(per_vw + "|", data, )        
endmacro