/*

*/

Macro "Roadway Skims" (Args)
    RunMacro("Create Roadway Skims", Args)
    RunMacro("Create Average Roadway Skims", Args)
    return(1)
endmacro

Macro "Transit Skims" (Args)
    RunMacro("Create Transit Skims", Args)
    return(1)
endmacro

/*

*/

Macro "Update Link Networks" (Args)

    net_dir = Args.[Output Folder] + "/networks"
    hwy_dbd = Args.Links

    files = RunMacro("Catalog Files", {dir: net_dir, ext: "net"})
    for file in files do
        {, , name, } = SplitPath(file)
        {, period, mode} = ParseString(name, "_")
        if Lower(period) = "bike" or Lower(period) = "walk" or Lower(period) = "pmpk" then continue

        obj = CreateObject("Network.Update")
        obj.LayerDB = hwy_dbd
        obj.Network = file
        obj.UpdateLinkField({Name: "CongTime", Field: {"AB" + period + "Time", "BA" + period + "Time"}})
        obj.Run()
    end
endmacro

/*
Creates the roadway skims for sov/hov.
Note: walk/bike skims are created once during accessibility calculations.

Inputs
    * Args
        * Standard Args array used throughout the model
    * OtherOpts
        * optional options array used to modify default looping behavior
            * period
                * String
                * Single period to run (instead of running multiple)
            * mode
                * String
                * either 'sov' or 'hov' (instead of running both)
            * out_file
                * String
                * File path for output skim

*/

Macro "Create Roadway Skims" (Args, OtherOpts)

    link_dbd = Args.Links
    periods = RunMacro("Get Unconverged Periods", Args)
    net_dir = Args.[Output Folder] + "/networks"
    out_dir = Args.[Output Folder] + "/skims/roadway"
    feedback_iteration = Args.FeedbackIteration
    taz_dbd = Args.TAZs
    se_file = Args.SE
    modes = {"sov", "hov"}

    // Overwrite default arguments if these are passed
    if OtherOpts.period <> null then periods = {OtherOpts.period}
    if OtherOpts.mode <> null then modes = {OtherOpts.mode}

    // Calculate intrazonal travel times
    objLyrs = CreateObject("AddDBLayers", {FileName: taz_dbd})
    {tlyr} = objLyrs.Layers
    v_area = GetDataVector(tlyr + "|", "Area", {{"Sort Order",{{"ID","Ascending"}}}})
    //       {diagonal of a square } / 3  * {30 mph = 2 minutes per mile}
    v_time = (sqrt(v_area) * sqrt(2) / 3) * (60 / 30) 
    // Create a vector of the correct length
    se_vw = OpenTable("se", "FFB", {se_file})
    n = GetRecordCount(se_vw, )
    CloseView(se_vw)
    v_iz = Vector(n, "Float", )
    for i = 1 to v_time.length do
        v_iz[i] = v_time[i]
    end

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
            if OtherOpts.out_file <> null then out_file = OtherOpts.out_file
            label = "Roadway skim " + period + " " + Upper(mode)
            obj.OutputMatrix({
                MatrixFile: out_file, 
                Matrix: label
            })
            ret_value = obj.Run()

            // intrazonals
            obj = CreateObject("Distribution.Intrazonal")
            obj.OperationType = "Replace"
            obj.TreatMissingAsZero = false
            obj.Neighbours = 3
            obj.Factor = .75
            m = CreateObject("Matrix", out_file)
            corenames = m.GetCoreNames()
            for core in corenames do
                obj.SetMatrix({MatrixFile: out_file, Matrix: core})
                ok = obj.Run()
            end
            m.SetVector({Core: corenames[1], Vector: v_iz, Diagonal: "true"})

            // Auto pay fare
            m.AddCores({"auto_pay_fare"})
            m.auto_pay_fare := 4 + .7 * m.[Length (Skim)] + .25 * m.CongTime
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
            out_m = CreateObject("Matrix", out_skim)
            TransposeMatrix(out_m.GetMatrixHandle(), {"File Name": trans_skim, Label: "transposed"})
            t_m = CreateObject("Matrix", trans_skim)

            cores = out_m.GetCoreNames()
            for core in cores do
                out_m.(core) := pa_fac * out_m.(core) + ap_fac * t_m.(core)
            end
            t_m = null
            DeleteFile(trans_skim)
        end

        rh = GetNextRecord(factor_vw + "|", , )
    end
    CloseView(factor_vw)

    // Add a dummy intrazonal core that will be used by DC later
    a_mtx_files = RunMacro("Catalog Files", {dir: skim_dir, ext: "mtx"})
    for file in a_mtx_files do
        {drive, folder, name, ext} = SplitPath(file)
        if Left(name, 3) <> "avg" then continue
        mtx = CreateObject("Matrix", file)
        mtx.AddCores("IZ")
        mtx.IZ := 0
        v = Vector(mtx.IZ.Rows, "Float", {Constant: 1})
        SetMatrixVector(mtx.IZ, v, {Diagonal: "true"})
    end
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

Macro "Create Transit Skims" (Args, overrides)

    rts_file = Args.Routes
    periods = RunMacro("Get Unconverged Periods", Args)
    TransModeTable = Args.TransModeTable
    access_modes = Args.access_modes
    net_dir = Args.[Output Folder] + "/networks"
    out_dir = Args.[Output Folder] + "/skims/transit"

    transit_modes = RunMacro("Get Transit Modes", TransModeTable)
    transit_modes = {"all"} + transit_modes
  
    // overrides
    if overrides.periods <> null then periods = overrides.periods
    if overrides.transit_modes <> null then transit_modes = overrides.transit_modes
    if overrides.access_modes <> null then access_modes = overrides.access_modes

    for period in periods do
        for mode in transit_modes do

            if mode = "all" 
                then access_mode_subset = {"w"}
                else access_mode_subset = access_modes

            for access in access_mode_subset do
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