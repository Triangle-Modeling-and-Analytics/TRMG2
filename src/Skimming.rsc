/*
temp macro to get congested skims. called from menu.
TODO: delete
*/

Macro "get cong skims" (Args)
    
    RunMacro("Initial Processing", Args)
    RunMacro("Roadway Assignment", Args)
    RunMacro("Create Link Networks", Args)
    RunMacro("Create Route Networks", Args)
    RunMacro("Skimming", Args)
    RunMacro("Summaries", Args)

    ShowMessage("Done")
endmacro

/*

*/

Macro "Skimming" (Args)

    feedback_iteration = Args.FeedbackIteration

    // TODO: move this network updating into the feedback step when it exists
    if feedback_iteration > 1 then do
        RunMacro("Calculate Bus Speeds", Args)
        RunMacro("Create Link Networks", Args)
        RunMacro("Create Route Networks", Args)
    end
    RunMacro("Roadway Skims", Args)
    RunMacro("Create Average Roadway Skims", Args)
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

            // Auto pay fare
            m.AddCores({"auto_pay_fare"})
            cores = m.data.cores
            cores.auto_pay_fare := 4 + .7 * cores.[Length (Skim)] + .25 * cores.CongTime
        end
    end
endmacro

/*
This macro uses directionality factors to create skims that are a weighted
average of the PA and AP travel time. It also calculates auto pay fare price.
*/

Macro "Create Average Roadway Skims" (Args)

    factor_tbl = Args.DirectionFactorsSkims
    skim_dir = Args.[Output Folder] + "/skims/roadway"
    modes = {"sov", "hov"}

    factor_vw = OpenTable("factor_vw", "CSV", {factor_tbl})
    rh = GetFirstRecord(factor_vw + "|", )
    while rh <> null do
        tod = factor_vw.period
        hb = factor_vw.homebased
        tour_type = factor_vw.tour_type
        pa_fac = factor_vw.pa
        ap_fac = factor_vw.ap

        for mode in modes do
            in_skim = skim_dir + "/skim_" + mode + "_" + tod + ".mtx"
            trans_skim = Substitute(in_skim, ".mtx", "_t.mtx", )
            out_skim = skim_dir + "/avg_skim_" + tod + "_" + tour_type + "_" + hb + "_" + mode + ".mtx"

            CopyFile(in_skim, out_skim)
            out_m = CreateObject("Matrix")
            out_m.LoadMatrix(out_skim)
            out_cores = out_m.data.cores
            TransposeMatrix(out_m.MatrixHandle, {"File Name": trans_skim, Label: "transposed"})
            t_m = CreateObject("Matrix")
            t_m.LoadMatrix(trans_skim)
            t_cores = t_m.data.cores

            for core in out_m.CoreNames do
                out_cores.(core) := pa_fac * out_cores.(core) + ap_fac * t_cores.(core)
            end
            t_m = null
            t_cores = null
            DeleteFile(trans_skim)
        end

        rh = GetNextRecord(factor_vw + "|", , )
    end
    CloseView(factor_vw)
endmacro

/*
Creates the various transit skims needed by the model. The `override` argument
allows only some skims to be created. This is useful for earlier model steps
like accessibility calculations.

Inputs
  * Args: standard args array
  * overrides
    * named array containing overrides for the following:
      * periods
      * transit_modes
      * access_modes
    * If provided, only these skims will be created. Used by accessibility.
*/

Macro "Transit Skims" (Args, overrides)

    rts_file = Args.Routes
    periods = Args.periods
    TransModeTable = Args.TransModeTable
    access_modes = Args.access_modes
    net_dir = Args.[Output Folder] + "/networks"
    out_dir = Args.[Output Folder] + "/skims/transit"

    transit_modes = RunMacro("Get Transit Modes", TransModeTable)
    
    // overrides
    if overrides.periods <> null then periods = overrides.periods
    if overrides.transit_modes <> null then transit_modes = overrides.transit_modes
    if overrides.access_modes <> null then access_modes = overrides.access_modes

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
                obj.Run()
                obj = null

                // Flip to AP format in the PM period
                if period = "PM" then do
                    label = label + " transposed to AP"
                    RunMacro("Transpose Matrix", out_file, label)
                end
            end
        end
    end
endmacro