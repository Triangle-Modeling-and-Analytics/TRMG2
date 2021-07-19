/*

*/

Macro "NonMotorized" (Args)

    RunMacro("Create NonMotorized Features", Args)
    RunMacro("Apply NM Choice Model", Args)

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

    v_autos = S2I(v_autos)
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

Macro "Apply NM Choice Model" (Args)

    scen_dir = Args.[Scenario Folder]
    input_dir = Args.[Input Folder]
    input_nm_dir = input_dir + "/resident/nonmotorized"
    output_dir = Args.[Output Folder] + "/resident/nonmotorized"
    periods = Args.periods
    households = Args.Households
    persons = Args.Persons

    // Determine trip purposes
    prod_rate_file = input_dir + "/resident/generation/production_rates.csv"
    rate_vw = OpenTable("rate_vw", "CSV", {prod_rate_file})
    trip_types = GetDataVector(rate_vw + "|", "trip_type", )
    trip_types = SortVector(trip_types, {Unique: "true"})
    CloseView(rate_vw)

    opts = null
    opts.segments = null
    opts.primary_spec = {Name: "person", OField: "ZoneID"}
    for trip_type in trip_types do

        // All escort-k12 trips are motorized, so just skip
        if trip_type = "W_HB_EK12_All" then continue

        opts.trip_type = trip_type
        opts.util_file = input_nm_dir + "/" + trip_type + ".csv"

        for period in periods do
            opts.period = period
            
            // Set sources
            opts.tables = {
                se: {
                    File: scen_dir + "\\output\\sedata\\scenario_se.bin",
                    IDField: "TAZ"
                },
                person: {
                    IDField: "PersonID",
                    JoinSpec: {
                        LeftFile: persons,
                        LeftID: "HouseholdID",
                        RightFile: households,
                        RightID: "HouseholdID"
                    }
                }
            }
            opts.output_dir = output_dir
            RunMacro("MC", Args, opts)
        end
    end
endmacro