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
    RunMacro("Transit Skims", Args)

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
            label = "Roadway skim " + period + " " + Upper(mode)
            obj.OutputMatrix({
                MatrixFile: out_file, 
                Matrix: label
            })
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
        
            // Flip to AP format in the PM period
            if period = "PM" then do
                m = null
                label = label + " transposed to AP"
                RunMacro("Transpose Matrix", out_file, label)
            end
        end
    end
endmacro

/*

*/

Macro "Transit Skims" (Args)

    rts_file = Args.Routes
    periods = Args.periods
    tmode_table = Args.tmode_table
    access_modes = Args.access_modes
    net_dir = Args.[Output Folder] + "/networks"
    out_dir = Args.[Output Folder] + "/skims/transit"

    transit_modes = RunMacro("Get Transit Modes", tmode_table)

    for period in periods do
        for mode in transit_modes do
            for access in access_modes do
                net_file = net_dir + "/tnet_" + period + "_" + access + "_" + mode + ".tnw"
                out_file = out_dir + "/skim_" + period + "_" + access + "_" + mode + ".mtx"

                obj = CreateObject("Network.TransitSkims")
                obj.Method = "PF"
                obj.LayerRS = rts_file
                obj.Network = net_file
                obj.OriginFilter = "Centroid = 1"
                obj.DestinationFilter = "Centroid = 1"
                obj.SkimVariables = {
                    "Generalized Cost",
                    "Total Time",
                    "Fare",
                    "In-Vehicle Time",
                    "Initial Wait Time",
                    "Transfer Wait Time",
                    "Transfer Penalty Time",
                    "Transfer Walk Time",
                    "Access Walk Time",
                    "Egress Walk Time",
                    "Access Drive Time",
                    "Dwelling Time",
                    // "In-Vehicle Cost",
                    // "Initial Wait Cost",
                    // "Transfer Wait Cost",
                    // "Transfer Penalty Cost",
                    // "Transfer Walk Cost",
                    // "Access Walk Cost",
                    // "Egress Walk Cost",
                    // "Access Drive Cost",
                    // "Dwelling Cost",
                    "Number of Transfers",
                    "In-Vehicle Distance",
                    "Drive Distance"
                }
                label = "Transit skim " + period + "_" + access + "_" + mode
                obj.OutputMatrix({
                    MatrixFile: out_file,
                    MatrixLabel : label, 
                    Compression: true, ColumnMajor: false
                })   
                ok = obj.Run()

                // Flip to AP format in the PM period
                if period = "PM" then do
                    label = label + " transposed to AP"
                    RunMacro("Transpose Matrix", out_file, label)
                end
            end
        end
    end
endmacro
