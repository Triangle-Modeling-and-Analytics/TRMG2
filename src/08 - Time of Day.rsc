/*

*/

Macro "Time of Day Split" (Args)

    RunMacro("Resident HB TOD", Args)

    // For the disaggregate approach, create trip tables for each trip type.
    // Then, run disaggregate TOD to determine the period of each trip.
    RunMacro("Create Trip Tables", Args)
    RunMacro("Resident HB TOD Disaggregate", Args)
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

/*
Expand the trip rates from the synthetic person table into trip tables for each 
trip type.
*/

Macro "Create Trip Tables" (Args)
    
    per_file = Args.Persons
    out_dir = Args.[Output Folder] + "/resident/trip_tables"

    if GetDirectoryInfo(out_dir, "All") = null then CreateDirectory(out_dir)

    {drive, folder, name, ext} = SplitPath(per_file)
    trip_file = drive + folder + "/temp.bin"
    CopyFile(per_file, trip_file)
    CopyFile(
        Substitute(per_file, ".bin", ".dcb", ), 
        Substitute(trip_file, ".bin", ".dcb", )
    )
    trips = CreateObject("Table", trip_file)

    // Integerize Trips
    trip_types = RunMacro("Get HB Trip Types", Args)
    field_names = trips.GetFieldNames()
    SetRandomSeed(199999)
    // for field in field_names do
    for trip_type in trip_types do
        
        // The original trip type field (e.g. W_HB_EK12_All) is split into two
        // additional fields: motorized ("_m") and non-motorized ("_nm"). Drop 
        // the original and non-motorized fields.
        fields_to_drop = fields_to_drop + {trip_type, trip_type + "_nm"}

        // The trips will look like 1.5. Integerize them by rounding down
        // and then randomly adding 1 based on the decimal value.
        field = trip_type + "_m"
        v = trips.(field)
        v_floor = floor(v)
        v_mod = mod(v, 1)
        v_rand = RandomSamples(v_mod.length, "Uniform")
        v_extra_trip = if v_rand < v_mod then 1 else 0
        v_trips = v_floor + v_extra_trip
        field_data.(field) = v_trips
    end
    trips.DropFields({FieldNames: fields_to_drop})
    trips.SetDataVectors({FieldData: field_data})

    // Export a trip table for each trip type
    for trip_type in trip_types do
        field = trip_type + "_m"
        exp_tbl = trips.Expand({
            FrequencyField: field,
            OutputFile: out_dir + "/" + trip_type + ".bin"
        })
    end

    // Delete the temporary trip file
    trips = null
    DeleteFile(trip_file)
    DeleteFile(Substitute(trip_file, ".bin", ".dcb", ))
endmacro

/*
Disaggregate approach for determining the time of day of each trip.
*/

Macro "Resident HB TOD Disaggregate" (Args)

    tod_file = Args.ResTODFactors
    trip_dir = Args.[Output Folder] + "/resident/trip_tables"

    fac = CreateObject("Table", tod_file)
    trip_types = fac.trip_type
    trip_types = SortVector(trip_types, {Unique: true})


    for trip_type in trip_types do
        
        // Get factors only for this trip type
        fac.SelectByQuery({
            SetName: "selection",
            Filter: "trip_type = '" + trip_type + "'"
        })
        v_tod = fac.tod
        v_fac = fac.factor

        // Open the trip table for this trip type and assign TOD values
        trips = CreateObject("Table", trip_dir + "/" + trip_type + ".bin")
        trips.AddField({FieldName: "TOD", Type: "String", Description: "Time of Day"})
        n = trips.GetRecordCount()
        tods = RandSamples(n, "Discrete", {
            Population: v_tod,
            Weight: v_fac
        })
        trips.TOD = tods
        trips = null
    end

endmacro