/*

*/

Macro "NonMotorized" (Args)

    // RunMacro("Create NonMotorized Features")
    // RunMacro("Apply NM Choice Model", Args)

    return(1)
endmacro

/*

*/

Macro "Create NonMotorized Features" (Args)

    hh_file = Args.[Synthesized HHs]
    per_file = Args.[Synthesized Persons]

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    per_vw = OpenTable("per", "FFB", {per_file})
    se_vw = OpenTable("per", "FFB", {se_file})
    hh_fields = {
        {"veh_per_adult", "Real", 10, 2,,,, "Vehicles per Adult"}
    }
    per_fields =  {
        {"veh_per_adult", "Real", 10, 2,,,, "Vehicles per Adult"}
    }
    RunMacro("Add Fields", {view: per_vw, a_fields: per_fields})
    {, hh_specs} = RunMacro("Get Fields", {view_name: hh_vw})
    {, per_specs} = RunMacro("Get Fields", {view_name: per_vw})
    {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})

    {v_size, v_kids, v_autos} = GetDataVectors(hh_vw + "|", {"HHSize", "HHKids", })

    jv = JoinViews("per+hh", per_specs.HouseholdID, hh_specs.HouseholdID, )

endmacro

/*

*/

Macro "Apply NM Choice Model" (Args)

    per_file = Args.[Synthesized Persons]
    se_file = Args.SE
    mdl_dir = Args.[Input Folder] + "\\nonmotorized"

    a_mdl_files = RunMacro("Catalog Files", mdl_dir, "mdl")
    per_vw = OpenTable("per_vw", "FFB", {per_file})

    for model_file in a_mdl_files do
        {dir, path, model_name, ext} = SplitPath(model_file)
        model_name = model_name + "-walk"

        // Apply mc model
        o = CreateObject("Choice.Mode")
        o.ModelFile = model_file
        o.AddTableSource({Label: "perdata", FileName: per_file})
        o.DropModeIfMissing = true
        o.SkipValuesBelow = 0.001
        out_file = GetTempFileName("*.bin")
        o.OutputProbabilityFile = out_file
        o.AggregateModel = false
        ok = o.Run()
        
        // Transfer results to the person table
        a_fields =  {{model_name, "Real", 10, 2,,,, "Walk trips for this trip type"}}
        RunMacro("Add Fields", {view: per_vw, a_fields: a_fields})

        out_vw = OpenTable("output", "FFB", {out_file})
        {, out_specs} = RunMacro("Get Fields", {view_name: out_vw})
        {, se_specs} = RunMacro("Get Fields", {view_name: per_vw})
        jv = JoinViews("jv", se_specs.TAZ, out_specs.ID, )
        v = GetDataVector(jv + "|", "walk Probability", )
        SetDataVector(jv + "|", model_name, v, )
        CloseView(jv)
        CloseView(out_vw)
        CloseView(per_vw)
    end
endmacro