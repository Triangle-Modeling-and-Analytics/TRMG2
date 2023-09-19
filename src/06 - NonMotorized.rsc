/*

*/
Macro "NonMotorized Choice" (Args)
    RunMacro("Create NonMotorized Features", Args)
    RunMacro("Calculate NM Probabilities", Args)
    RunMacro("Separate NM Trips", Args)
    RunMacro("Aggregate HB NonMotorized Walk Trips", Args)
    return(1)
endmacro

Macro "NM Distribution" (Args)
    RunMacro("NM Gravity", Args)
    return(1)
endmacro

Macro "NM Time-of-Day" (Args)
    RunMacro("NM TOD", Args)
    return(1)
endmacro

/*
This macro creates features on the synthetic household and person tables
needed by the non-motorized model.
*/

Macro "Create NonMotorized Features" (Args)

    hh_file = Args.Households
    per_file = Args.Persons

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("per", "FFB", {per_file})
    hh_fields = {
        {"veh_per_adult", "Real", 10, 2,,,, "Vehicles per Adult"},
        {"inc_per_capita", "Real", 10, 2,,,, "Income per person in household"}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: hh_fields})
    per_fields = {
        {"age_16_18", "Integer", 10, ,,,, "If person's age is 16-18"}
    }
    RunMacro("Add Fields", {view: per_vw, a_fields: per_fields})

    {v_size, v_kids, v_autos, v_inc} = GetDataVectors(
        hh_vw + "|", {"HHSize", "HHKids", "Autos", "HHInc"},
    )

    v_adult = v_size - v_kids
    v_vpa = v_autos / v_adult
    SetDataVector(hh_vw + "|", "veh_per_adult", v_vpa, )
    v_ipc = v_inc / v_size
    SetDataVector(hh_vw + "|", "inc_per_capita", v_ipc, )
    v_age = GetDataVector(per_vw + "|", "Age", )
    v_age_flag = if v_age >= 16 and v_age <= 18 then 1 else 0
    SetDataVector(per_vw + "|", "age_16_18", v_age_flag, )
endmacro

/*
Loops over each trip type and applies the binary choice model to split
trips into a "motorized" or "nonmotorized" mode.

Inputs
    * trip_types
        * Optional Array
        * Specific trip types to run this macro for
        * If null, will run for all HB trip types
        * Used by calibration macros
*/

Macro "Calculate NM Probabilities" (Args, trip_types)

    scen_dir = Args.[Scenario Folder]
    input_dir = Args.[Input Folder]
    input_nm_dir = Args.NMInputFolder
    output_dir = Args.[Output Folder] + "/resident/nonmotorized"
    households = Args.Households
    persons = Args.Persons

    if trip_types = null then trip_types = RunMacro("Get HB Trip Types", Args)
    primary_spec = {Name: "person", OField: "ZoneID"}
    for trip_type in trip_types do
        // All escort-k12 trips are motorized so skip
        if trip_type = "W_HB_EK12_All" then continue

        obj = CreateObject("PMEChoiceModel", {ModelName: trip_type})
        obj.OutputModelFile = output_dir + "\\" + trip_type + ".mdl"
        obj.AddTableSource({
            SourceName: "se",
            File: scen_dir + "\\output\\sedata\\scenario_se.bin",
            IDField: "TAZ"
        })
        obj.AddTableSource({
            SourceName: "person",
            IDField: "PersonID",
            JoinSpec: {
                LeftFile: persons,
                LeftID: "HouseholdID",
                RightFile: households,
                RightID: "HouseholdID"
            }
        })
        util = RunMacro("Import MC Spec", input_nm_dir + "/" + trip_type + ".csv")
        obj.AddUtility({UtilityFunction: util})
        obj.AddPrimarySpec(primary_spec)
        nm_table = output_dir + "\\" + trip_type + ".bin"
        obj.AddOutputSpec({ProbabilityTable: nm_table})
        obj.RandomSeed = 199999
        obj.Evaluate()
    end
endmacro

/*
This creates new, motorized-only fields on the person table

Inputs
    * trip_types
        * Optional Array
        * Specific trip types to run this macro for
        * If null, will run for all HB trip types
        * Used by calibration macros
*/

Macro "Separate NM Trips" (Args, trip_types)
    
    output_dir = Args.[Output Folder] + "/resident/nonmotorized"
    per_file = Args.Persons
    
    per_vw = OpenTable("persons", "FFB", {per_file})

    if trip_types = null then trip_types = RunMacro("Get HB Trip Types", Args)

    for trip_type in trip_types do
        
        // Add field to person table
        per_out_field = trip_type + "_m"
        nm_field = trip_type + "_nm"
        per_fields_to_add = per_fields_to_add + {
            {per_out_field, "Real", 10, 2,,,, "Motorized " + trip_type + " person trips"},
            {nm_field, "Real", 10, 2,,,, "NonMotorized " + trip_type + " person trips"}
        }
        RunMacro("Add Fields", {view: per_vw, a_fields: per_fields_to_add})
        
        // All escort-k12 trips are motorized
        if trip_type = "W_HB_EK12_All" then do
            v = GetDataVector(per_vw + "|", trip_type, )
            SetDataVector(per_vw + "|", per_out_field, v, )
            v2 = Vector(v.length, "Long", {Constant: 0})
            SetDataVector(per_vw + "|", nm_field, v2, )
            continue
        end
        
        nm_file = output_dir + "/" + trip_type + ".bin"
        nm_vw = OpenTable("nm", "FFB", {nm_file})
        
        // Add field to nm table
        nm_fields_to_add = {
            {trip_type, "Real", 10, 2,,,, "Non-motorized person trips"}
        }
        RunMacro("Add Fields", {view: nm_vw, a_fields: nm_fields_to_add})

        // Join tables and calculate results
        jv = JoinViews("jv", per_vw + ".PersonID", nm_vw + ".ID", )
        v_pct_nm = GetDataVector(jv + "|", "nonmotorized Probability", )
        v_person = GetDataVector(jv + "|", per_vw + "." + trip_type, )
        v_nm = v_person * v_pct_nm
        v_person = v_person * (1 - v_pct_nm)
        
        SetDataVector(jv + "|", nm_vw + "." + trip_type, v_nm, )
        SetDataVector(jv + "|", per_vw + "." + per_out_field, v_person, )
        SetDataVector(jv + "|", per_vw + "." + nm_field, v_nm, )
        CloseView(jv)
        CloseView(nm_vw)
    end

    CloseView(per_vw)
endmacro


/*
Aggregates the non-motorized trips to TAZ

Inputs
    * trip_types
        * Optional Array
        * Specific trip types to run this macro for
        * If null, will run for all HB trip types
        * Used by calibration macros
*/

Macro "Aggregate HB NonMotorized Walk Trips" (Args, trip_types)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE
    nm_dir = Args.[Output Folder] + "/resident/nonmotorized"

    per_df = CreateObject("df", per_file)
    per_df.select({"PersonID", "HouseholdID"})
    hh_df = CreateObject("df", hh_file)
    hh_df.select({"HouseholdID", "ZoneID"})
    per_df.left_join(hh_df, "HouseholdID", "HouseholdID")

    if trip_types = null then trip_types = RunMacro("Get HB Trip Types", Args)
    // Remove W_HB_EK12_All because it is all motorized by definition
    pos = trip_types.position("W_HB_EK12_All")
    if pos > 0 then trip_types = ExcludeArrayElements(trip_types, pos, 1)
    for trip_type in trip_types do
        file = nm_dir + "/" + trip_type + ".bin"
        vw = OpenTable("temp", "FFB", {file})
        v = GetDataVector(vw + "|", trip_type, {{"Sort Order",{{"ID","Ascending"}}}})
        CloseView(vw)
        per_df.tbl.(trip_type) = v
    end
    per_df.group_by("ZoneID")
    per_df.summarize(trip_types, "sum")
    for trip_type in trip_types do
        per_df.rename("sum_" + trip_type, trip_type)
    end
    
    // Add the walk accessibility attractions from the SE bin file, which will
    // be used in the gravity application.
    se_df = CreateObject("df", se_file)
    se_df.select({"TAZ", "access_walk_attr"})
    se_df.left_join(per_df, "TAZ", "ZoneID")

    se_df.write_bin(nm_dir + "/_agg_nm_trips_daily.bin")
endmacro

/*

*/

Macro "NM Gravity" (Args)

    grav_params = Args.[Input Folder] + "/resident/nonmotorized/distribution/nm_gravity.csv"
    out_dir = Args.[Output Folder] 
    nm_dir = out_dir + "/resident/nonmotorized"
    prod_file = nm_dir + "/_agg_nm_trips_daily.bin"

    RunMacro("Gravity", {
        se_file: prod_file,
        skim_file: out_dir + "/skims/nonmotorized/walk_skim.mtx",
        param_file: grav_params,
        output_matrix: nm_dir + "/nm_gravity.mtx"
    })
endmacro

/*
Split the non-motorized trips up by time of day using the same factors as
the motorized trips.
*/

Macro "NM TOD" (Args)

    nm_file = Args.[Output Folder] + "/resident/nonmotorized/nm_gravity.mtx"
    tod_file = Args.ResTODFactors
    
    nm_mtx = CreateObject("Matrix", nm_file)
    fac_vw = OpenTable("tod_fac", "CSV", {tod_file})
    v_type = GetDataVector(fac_vw + "|", "trip_type", )
    v_tod = GetDataVector(fac_vw + "|", "tod", )
    v_fac = GetDataVector(fac_vw + "|", "factor", )

    for i = 1 to v_type.length do
        type = v_type[i]
        tod = v_tod[i]
        fac = v_fac[i]

        core_name = type + "_" + tod
        nm_mtx.AddCores({core_name})
        if type = "W_HB_EK12_All" then continue
        cores = nm_mtx.GetCores()
        cores.(core_name) := cores.(type) * fac
    end
endmacro