/*

*/

Macro "NonMotorized" (Args)

    RunMacro("Create NonMotorized Features", Args)
    RunMacro("Calculate NM Probabilities", Args)
    RunMacro("Separate NM Trips", Args)

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
    SetDataVector(hh_vw + "|", "inc_per_capita", v_vpa, )
    v_age = GetDataVector(per_vw + "|", "Age", )
    v_age_flag = if v_age >= 16 and v_age <= 18 then 1 else 0
    SetDataVector(per_vw + "|", "age_16_18", v_age_flag, )
endmacro

/*
Loops over each trip type and applies the binary choice model to split
trips into a "motorized" or "nonmotorized" mode.
*/

Macro "Calculate NM Probabilities" (Args)

    scen_dir = Args.[Scenario Folder]
    input_dir = Args.[Input Folder]
    input_nm_dir = input_dir + "/resident/nonmotorized"
    output_dir = Args.[Output Folder] + "/resident/nonmotorized"
    households = Args.Households
    persons = Args.Persons

    trip_types = RunMacro("Get Trip Types", Args)
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
        obj.Evaluate()
    end
endmacro

/*
This reduces the trip counts on the synthetic persons tables to represent
only the motorized person trips. The non-motorized person trips are stored
in separate tables in output/resident/nonmotorized.

TODO: This step spends a lot of time reading/writing. Not sure if it can
be improved.
*/

Macro "Separate NM Trips" (Args)
    
    output_dir = Args.[Output Folder] + "/resident/nonmotorized"
    per_file = Args.Persons
    periods = Args.periods
    
    per_vw = OpenTable("persons", "FFB", {per_file})

    trip_types = RunMacro("Get Trip Types", Args)

    for trip_type in trip_types do
        // All escort-k12 trips are motorized so skip
        if trip_type = "W_HB_EK12_All" then continue
        
        nm_file = output_dir + "/" + trip_type + ".bin"
        nm_vw = OpenTable("nm", "FFB", {nm_file})
        
        // Add fields to the NM table before joining
        a_fields_to_add = null
        output = null
        for period in periods do
            a_fields_to_add = a_fields_to_add + {
                {trip_type + "_" + period, "Real", 10, 2,,,, "Non-motorized person trips in the " + period + "period"}
            }
        end
        RunMacro("Add Fields", {view: nm_vw, a_fields: a_fields_to_add})

        // Join tables and calculate results
        jv = JoinViews("jv", per_vw + ".PersonID", nm_vw + ".ID", )
        v_pct_nm = GetDataVector(jv + "|", "nonmotorized Probability", )
        nmoto_data = null
        per_fields = null
        for period in periods do
            per_fields = per_fields + {per_vw + "." + trip_type + "_" + period}
        end
        person_data = GetDataVectors(jv + "|", per_fields, {OptArray: "true"})
        for period in periods do
            field_name = trip_type + "_" + period
            nmoto_data.(nm_vw + "." + field_name) = person_data.(per_vw + "." + field_name) * v_pct_nm
            person_data.(per_vw + "." + field_name) = person_data.(per_vw + "." + field_name) * (1 - v_pct_nm)
        end
        SetDataVectors(jv + "|", nmoto_data, )
        SetDataVectors(jv + "|", person_data, )
        CloseView(jv)
        CloseView(nm_vw)
    end

    CloseView(per_vw)
endmacro