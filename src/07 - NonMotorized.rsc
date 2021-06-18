/*

*/

Macro "NonMotorized" (Args)

    // RunMacro("Create NonMotorized Features", Args)
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

*/

Macro "Apply NM Choice Model" (Args)

    hh_file = Args.Households
    per_file = Args.Persons
    se_file = Args.SE
    mdl_dir = Args.[Input Folder] + "\\nonmotorized"
    out_dir = Args.[Output Folder]

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("per", "FFB", {per_file})
    se_vw = OpenTable("se", "FFB", {per_file})
    jv = JoinViews("per+hh", per_vw + ".HouseholdID", hh_vw + ".HouseholdID", )

    a_mdl_files = RunMacro("Catalog Files", mdl_dir, "mdl")
    for model_file in a_mdl_files do
        {dir, path, model_name, ext} = SplitPath(model_file)
        model_name = model_name + "_walk"

        // Apply mc model
        o = CreateObject("Choice.Mode")
        o.ModelFile = model_file
        // o.AddTableSource({Label: "perdata", FileName: per_file})
        o.DropModeIfMissing = true
        o.SkipValuesBelow = 0.001
        out_file = out_dir + "/resident/mode/nm_probabilities.bin"
        o.OutputProbabilityFile = out_file
        o.AggregateModel = false
        ok = o.Run()
        
        // // Transfer results to the person table
        // a_fields =  {{model_name, "Real", 10, 2,,,, "Walk trips for this trip type"}}
        // RunMacro("Add Fields", {view: per_vw, a_fields: a_fields})

        // out_vw = OpenTable("output", "FFB", {out_file})
        // {, out_specs} = RunMacro("Get Fields", {view_name: out_vw})
        // {, se_specs} = RunMacro("Get Fields", {view_name: per_vw})
        // jv = JoinViews("jv", se_specs.TAZ, out_specs.ID, )
        // v = GetDataVector(jv + "|", "walk Probability", )
        // SetDataVector(jv + "|", model_name, v, )
        // CloseView(jv)
        // CloseView(out_vw)
        // CloseView(per_vw)
    end

    CloseView(hh_vw)
    CloseView(per_vw)
    CloseView(se_vw)
    CloseView(jv)
endmacro