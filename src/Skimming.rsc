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
Creates the roadway skims for sov/hov.
Note: walk/bike skims are created once during accessibility calculations.
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
            obj.Network = net_dir + "/net_" + period + "_" + mode + ".net"
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

            // intrazonals
            obj = CreateObject("Distribution.Intrazonal")
            obj.OperationType = "Replace"
            obj.TreatMissingAsZero = true
            obj.Neighbours = 3
            obj.Factor = .75
            m = CreateObject("Matrix")
            m.LoadMatrix(out_file)
            for core in m.CoreNames do
                obj.SetMatrix({MatrixFile: out_file, Matrix: core})
                ok = obj.Run()
            end
        end
    end
endmacro