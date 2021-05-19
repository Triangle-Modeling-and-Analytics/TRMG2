/*

*/

Macro "NonMotorized" (Args)

    // RunMacro("Apply NM Choice Model", Args)

    return(1)
endmacro

/*

*/

Macro "Apply NM Choice Model" (Args)

    se_file = Args.SE
    mdl_dir = Args.[Input Folder] + "\\nonmotorized"

    a_mdl_files = RunMacro("Catalog Files", mdl_dir, "mdl")
    se_vw = OpenTable("se", "FFB", {se_file})


    for model_file in a_mdl_files do
        {dir, path, model_name, ext} = SplitPath(model_file)

        // Apply mc model
        o = CreateObject("Choice.Mode")
        o.ModelFile = model_file
        o.AddTableSource({Label: "sedata", Filter: "Type = 'Internal'", FileName: se_file})
        o.DropModeIfMissing = true
        o.SkipValuesBelow = 0.001
        out_file = GetTempFileName("*.bin")
        o.OutputProbabilityFile = out_file
        o.AggregateModel = false
        ok = o.Run()
        
        // Transfer results to SE data

        a_fields =  {
            {"Walkability", "Real", 10, 2,,,, "Probability of walk trips. Result of simple choice model."}
        }
        RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

        out_vw = OpenTable("output", "FFB", {out_file})
        {, out_specs} = RunMacro("Get Fields", {view_name: out_vw})
        {, se_specs} = RunMacro("Get Fields", {view_name: se_vw})
        jv = JoinViews("jv", se_specs.TAZ, out_specs.ID, )
        v = GetDataVector(jv + "|", "walk Probability", )
        SetDataVector(jv + "|", "Walkability", v, )
        CloseView(jv)
        CloseView(out_vw)
        CloseView(se_vw)
    end
endmacro