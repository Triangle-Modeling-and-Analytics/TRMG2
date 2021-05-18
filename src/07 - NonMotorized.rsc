/*

*/

Macro "NonMotorized" (Args)

    RunMacro("Calculate NM Attractions", Args)
    // RunMacro("Calculate NM Logsums", Args)

    return(1)
endmacro

/*

*/

Macro "Calculate NM Attractions" (Args)

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

    // Calculate non-motorized attractions
    RunMacro("Create Sum Product Fields", {view: se_vw, factor_file: rate_file})

    fields = "nm_Oth_attr"
    descriptions = "NM choice model attractions"
    RunMacro("Add Field Description", se_vw, fields, descriptions)

    CloseView(se_vw)
endmacro

/*

*/

Macro "Calculate NM Logsums" (Args)

    output_dir = Args.[Output Folder]
    se_file = Args.SE

    skim_file = output_dir + "/accessibility/walk_skim.mtx"

    // Calculate logsums
    // a_types = {"NHBODS", "Oth"}
    a_types = {"Oth"}
    a_modes = {"walk"}
    // alphas.NHBODS = -.4629
    // betas.NHBODS = -.1085
    alphas.Oth = .5630
    betas.Oth = -.1896
    for type in a_types do
        size_field = "nm_" + type + "_attr"
        alpha = alphas.(type)
        beta = betas.(type)

        for mode in a_modes do
            output_field = type + "_access_" + mode
            matrix = skim_file
            time_field = "WalkTime"
            
            m = CreateObject("Matrix")
            m.LoadMatrix(matrix)
            m.AddCores({"size", "util"})
            cores = m.data.cores
            se_vw = OpenTable("se", "FFB", {se_file})
            a_fields =  {{output_field, "Real", 10, 2,,,, "logsum of a simple gravity model"}}
            RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
            size = GetDataVector(se_vw + "|", size_field, )
            cores.size := size
            cores.util := cores.size * pow(cores.(time_field), alpha) * exp(beta * cores.(time_field))
            cores.util := if cores.size = 0 then 0 else cores.util
            rowsum = GetMatrixVector(cores.util, {Marginal: "Row Sum"})
            logsum = Max(0, log(rowsum))
            SetDataVector(se_vw + "|", output_field, logsum, )
        end
    end
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