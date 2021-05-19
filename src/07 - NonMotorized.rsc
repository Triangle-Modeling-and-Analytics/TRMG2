/*

*/

Macro "NonMotorized" (Args)

    RunMacro("Calculate NM Interaction Fields", Args)
    RunMacro("Calculate NM Logsum Accessibilities", Args)

    return(1)
endmacro

/*

*/

Macro "Calculate NM Interaction Fields" (Args)

    se_file = Args.SE
    rate_file = Args.[NM Attr Rates]

    se_vw = OpenTable("se", "FFB", {se_file})

    // Calculate the interaction fields needed for NM attractions
    a_fields = {
        "HH",
        "K12",
        "StudGQ_NCSU",
        "StudGQ_UNC",
        "StudGQ_DUKE",
        "StudGQ_NCCU",
        "CollegeOn",
        "Retail",
        "TotalEmp"
    }
    v_walkability = GetDataVector(se_vw + "|", "Walkability", )
    for field in a_fields do
        new_name = "w" + field
        a_fields_to_add = a_fields_to_add + {
            {new_name, "Real", 10, 2, , , , field + " * Walkability|~'Walkable attractors'|Used in NM choice model"}            
        }
        v = GetDataVector(se_vw + "|", field, )
        data.(new_name) = v * v_walkability
    end
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields_to_add})
    SetDataVectors(se_vw + "|", data, )

    CloseView(se_vw)
endmacro

/*

*/

Macro "Calculate NM Logsum Accessibilities" (Args)

    se_file = Args.SE
    param_file = Args.[NM Accessibilities]
    skim_dir = Args.[Output Folder] + "\\skims"
    sov_skim = skim_dir + "\\roadway\\skim_sov_AM.mtx"
    walk_skim = skim_dir + "\\nonmotorized\\walk_skim.mtx"

    RunMacro("Accessibility Calculator", {
        table: se_file,
        params: param_file,
        skims: {sov: sov_skim, walk: walk_skim}
    })
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