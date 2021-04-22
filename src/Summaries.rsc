/*
After the model is finished, these macros summarize the results into maps
and tables.
*/

Macro "Summaries" (Args)

    RunMacro("Load Link Layer", Args)
    return(1)
endmacro

/*
This loads the final assignment results onto the link layer.
*/

Macro "Load Link Layer" (Args)

    hwy_dbd = Args.Links
    feedback_iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)
    periods = Args.periods

    {nlyr, llyr} = GetDBLayers(hwy_dbd)

    for period in periods do
        assn_file = assn_dir + "\\roadway_assignment_" + period + ".bin"
        assn_dcb = Substitute(assn_file, ".bin", ".dcb", )

        vw = OpenTable("temp", "FFB", {assn_file})
        {field_names, } = GetFields(vw, "All")
        CloseView(vw)
        RunMacro("Join Table To Layer", hwy_dbd, "ID", assn_file, "ID1")
        {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
        for field_name in field_names do
            if field_name = "ID1" then continue
            RunMacro("Rename Field", llyr, field_name, field_name + "_" + period)
        end
        CloseMap(map)
    end
endmacro