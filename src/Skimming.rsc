/*

*/

Macro "Skimming" (Args)

    feedback_iteration = Args.FeedbackIteration

    // TODO: move this network updating into the feedback step when it exists
    if feedback_iteration > 1 then do
        RunMacro("Create Link Networks", Args)
        RunMacro("Create Route Networks", Args)
    end
    RunMacro("Roadway Skims", Args)
    //RunMacro("Transit Skims", Args)

    return(1)
endmacro

/*

*/

Macro "Roadway Skims" (Args)

    link_dbd = Args.Links
    periods = Args.periods
    net_dir = Args.[Output Folder] + "/networks"
    out_dir = Args.[Output Folder] + "/skims/roadway"

    modes = {"sov", "hov"}

    for period in periods do
        for mode in modes do
            obj = CreateObject("Network.Skims")
            obj.Network = output_dir + "/networks/net_" + period + "_" + mode + ".net"
            obj.LayerDB = link_dbd
            obj.Origins = "Centroid = 1" 
            obj.Destinations = "Centroid = 1"
            obj.Minimize = "CongTime"
            obj.AddSkimField({"Length", "All"})
            toll_field = "TollCost" + Upper(mode)
            obj.AddSkimField({toll_field, "All"})
            out_file = out_dir + "/skim_" + mode + "_" + period + ".mtx"
            obj.OutputMatrix({MatrixFile: out_file, Matrix: Upper(mode) + " Skim"})
            ret_value = obj.Run()
        end
    end
endmacro