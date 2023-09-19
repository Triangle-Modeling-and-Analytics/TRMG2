/*
Macros running in parallel cannot access the same files at the same time.
This macro performs a few tasks and stashes the data in Args. This allows it
to be referenced in parallel.
*/

Macro "Pre Assignment" (Args)
    hwy_dbd = Args.Links
    vot_param_file = Args.[Input Folder] + "/assignment/vot_params.csv"

    // Check if HOV links exist. If so, they will be excluded from sov/truck
    // assignment.
    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    SetLayer(llyr)
    n = SelectByQuery(
        "hov", "several", 
        "Select * where HOV <> 'None' and HOV <> null"
    )
    if n > 0 then hov_exists = "true" else hov_exists = "false"
    CloseMap(map)
    Args.hov_exists = hov_exists

    vot_params = RunMacro("Read Parameter File", {file: vot_param_file})
    Args.vot_params = vot_params

    return(1)
endmacro

/*
The following macro are used by the flowchart to run the roadway assignment
macro in parallel across time periods rather than in sequence. Each macro
checks to see if it's period needs to run.
*/
Macro "AM Roadway Assignment" (Args)
    periods = RunMacro("Get Unconverged Periods", Args)
    if periods.position("AM") = 0 then return(1)
    RunMacro("Run Roadway Assignment", Args, {period: "AM"})
    return(1)
endmacro
Macro "MD Roadway Assignment" (Args)
    periods = RunMacro("Get Unconverged Periods", Args)
    if periods.position("MD") = 0 then return(1)
    RunMacro("Run Roadway Assignment", Args, {period: "MD"})
    return(1)
endmacro
Macro "PM Roadway Assignment" (Args)
    periods = RunMacro("Get Unconverged Periods", Args)
    if periods.position("PM") = 0 then return(1)
    RunMacro("Run Roadway Assignment", Args, {period: "PM"})
    return(1)
endmacro
Macro "NT Roadway Assignment" (Args)
    periods = RunMacro("Get Unconverged Periods", Args)
    if periods.position("NT") = 0 then return(1)
    RunMacro("Run Roadway Assignment", Args, {period: "NT"})
    return(1)
endmacro

/*
Runs highway assignment.

Early in the model run, this macro is called in testing mode to check the
validity of the highway network and prevent wasted run time.

For actual assignment, this macro can run all periods in series or be provided
with a specific period to run (if running in parallel).

Inputs
    * OtherOpts
        * Optional named array
        * Can be used to override defaults
        * `test`
            * true/false
            * If this is just a test assignment call used by "Check Highway Networks" macro 
        * `od_mtx`
            * String
            * File path of OD matrix to use
        * `assign_iters`
            * Integer
            * Number of max assignment iterations
            * used by "Check Highway Networks" macro
        * `period`
            * String
            * Used to run a single period instead of all
            * used by the TOD assignment macros
        * 'net_file'
            * String
            * File path of the .net file to use
            * Used by the PM PK hour assignment macro
        * 'flow_table'
            * String
            * File path of the output assignment bin file
*/

Macro "Run Roadway Assignment" (Args, OtherOpts)

    hwy_dbd = Args.Links
    net_dir = Args.[Output Folder] + "\\networks\\"
    feedback_iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    vot_param_file = Args.[Input Folder] + "/assignment/vot_params.csv"
    assign_iters = Args.AssignIterations
    if OtherOpts.assign_iters <> null then assign_iters = OtherOpts.assign_iters
    periods = RunMacro("Get Unconverged Periods", Args)
    if OtherOpts.period <> null then periods = {OtherOpts.period}
    hov_exists = Args.hov_exists
    vot_params = Args.vot_params
    sl_query = Args.sl_query
    saveturns = Args.SaveTurns

    // If this macro is called without the pre-assignment step, then fill in
    // these variables.
    if vot_params = null then do
        vot_params = RunMacro("Read Parameter File", {file: vot_param_file})    
        Args.vot_params = vot_params
    end
    if hov_exists = null then do
        {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
        SetLayer(llyr)
        n = SelectByQuery(
            "hov", "several", 
            "Select * where HOV <> 'None' and HOV <> null"
        )
        if n > 0 then hov_exists = "true" else hov_exists = "false"
        CloseMap(map)
        Args.hov_exists = hov_exists
    end

    for period in periods do
        od_mtx = assn_dir + "/od_veh_trips_" + period + ".mtx"
        if OtherOpts.od_mtx <> null then od_mtx = OtherOpts.od_mtx
        net_file = net_dir + "net_" + period + "_hov.net"
        if OtherOpts.net_file <> null then net_file = OtherOpts.net_file

        o = CreateObject("Network.Assignment")
        o.Network = net_file
        o.LayerDB = hwy_dbd
        if sl_query <> null then do
            o.CriticalQueryFile = sl_query
            o.CriticalMatrix(assn_dir + "\\critical_matrix_" + period + ".mtx")
        end
        o.ResetClasses()
        o.Iterations = assign_iters
        o.Convergence = Args.AssignConvergence
        o.Method = "CUE"
        o.Conjugates = 3
        o.DelayFunction = {
            Function: "bpr.vdf",
            Fields: {"FFTime", "Capacity", "Alpha", "Beta", "None"}
        }
        o.DemandMatrix({MatrixFile: od_mtx})
        o.MSAFeedback({
            Flow: "MSAFlow",
            Time: "MSATime",
            Iteration: feedback_iter
        })

        if OtherOpts.flow_table <> null then 
            o.FlowTable = OtherOpts.flow_table
        else
            o.FlowTable = assn_dir + "\\roadway_assignment_" + period + ".bin"   
        
        // Add classes for each combination of vehicle type and VOT
        // If doing a test assignment, just create a single class from the
        // dummy matrix
        if OtherOpts.test <> null then do
            mtx = CreateObject("Matrix", od_mtx)
            core_names = mtx.GetCoreNames()
            mtx = null
            o.AddClass({
                Demand: core_names[1],
                PCE: 1,
                VOI: 1
            })
        end else do

            if period = "AM" or period = "PM"
                then pkop = "pk"
                else pkop = "op"

            if saveturns = 1 then do
                if period = "AM" or period = "PM" then do
                    o.TurnMovements({
                        Filter: "drive_node = 1",
                        FileName: assn_dir + "\\roadway_assignment_" + period + "_turns.bin"
                    })
                end
            end

            // sov
            voi = vot_params.calib_factor * vot_params.(pkop + "_auto") / 60 // ($/min)
            sov_opts = {
                Demand: "sov",
                PCE: 1,
                VOI: voi,
                LinkTollField: "TollCostSOV"
            }
            if hov_exists then sov_opts = sov_opts + {ExclusionFilter: "HOV <> 'None'"}
            o.AddClass(sov_opts)
            // hov2
            o.AddClass({
                Demand: "hov2",
                PCE: 1,
                VOI: voi,
                LinkTollField: "TollCostHOV"
            })
            // hov3
            o.AddClass({
                Demand: "hov3",
                PCE: 1,
                VOI: voi,
                LinkTollField: "TollCostHOV"
            })
            // CV
            cv_opts = {
                Demand: "CV",
                PCE: 1,
                VOI: voi,
                LinkTollField: "TollCostSOV"
            }
            if hov_exists then cv_opts = cv_opts + {ExclusionFilter: "HOV <> 'None'"}
            o.AddClass(cv_opts)
            // SUT
            voi = vot_params.calib_factor * vot_params.("sut") / 60 // ($/min)
            sut_opts = {
                Demand: "SUT",
                PCE: 1.5,
                VOI: voi,
                LinkTollField: "TollCostSUT"
            }
            if hov_exists then sut_opts = sut_opts + {ExclusionFilter: "HOV <> 'None'"}
            o.AddClass(sut_opts)
            // MUT
            voi = vot_params.calib_factor * vot_params.("mut") / 60 // ($/min)
            mut_opts = {
                Demand: "MUT",
                PCE: 2.5,
                VOI: voi,
                LinkTollField: "TollCostMUT"
            }
            if hov_exists then mut_opts = mut_opts + {ExclusionFilter: "HOV <> 'None'"}
            o.AddClass(mut_opts)
        end
        ret_value = o.Run()
        results = o.GetResults()
        /*
        Use results.data to get flow rmse and other metrics:
        results.data.[Relative Gap]
        results.data.[Maximum Flow Change]
        results.data.[MSA RMSE]
        results.data.[MSA PERCENT RMSE]
        etc.
        */
    end
endmacro

/*
After assignment, update congested times and networks. Updating the route networks
and bus speeds ensures that transit is assigned using the final/converged bus speeds.
This macro also uses the updated roadway network to check convergence based on skims.

*/

Macro "Post Assignment" (Args)
    RunMacro("Update Link Congested Times", Args)
    RunMacro("Calculate Bus Speeds", Args)
    RunMacro("Update Link Networks", Args)
    RunMacro("Create Route Networks", Args)
    RunMacro("Calculate Skim PRMSEs", Args)
    return(1)
endmacro

/*
After assignment, this macro updates the link layer congested time fields.
Called by the Post Assignment flowchart box.
*/

Macro "Update Link Congested Times" (Args)

    hwy_dbd = Args.Links
    periods = RunMacro("Get Unconverged Periods", Args)
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway"

    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    
    dirs = {"AB", "BA"}

    for period in periods do
        assn_file = assn_dir + "\\roadway_assignment_" + period + ".bin"
        assn_vw = OpenTable("assn", "FFB", {assn_file})
        jv = JoinViews("jv", llyr + ".ID", assn_vw + ".ID1", )
        data = null

        for dir in dirs do
            old_field = llyr + "." + dir + period + "Time"
            new_field = assn_vw + "." + dir + "_MSA_Time"
            v_old = GetDataVector(jv + "|", old_field, )
            v_new = GetDataVector(jv + "|", new_field, )
            // This check keeps TransitOnly links and any others not included
            // in assignment from having their times replaced with nulls.
            v_new = if v_new = null
                then v_old
                else v_new
            data.(old_field) = v_new
        end
        SetDataVectors(jv + "|", data, )

        CloseView(jv)
        CloseView(assn_vw)
    end

    CloseMap(map)
    return(1)
endmacro

/*

*/

Macro "Calculate Skim PRMSEs" (Args)
    
    periods = RunMacro("Get Unconverged Periods", Args)
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    mode = "sov"

    for period in periods do
        // create a new sov skim for the current period
        opts = null
        opts.period = period
        opts.mode = mode
        opts.out_file = assn_dir + "\\post_assignment_skim_" + period + ".mtx"
        RunMacro("Create Roadway Skims", Args, opts)

        // Calculate matrix %RMSE
        old_skim_file = Args.[Output Folder] + "/skims/roadway/skim_" + mode + "_" + period + ".mtx"
        old_skim = CreateObject("Matrix", old_skim_file)
        old_core = old_skim.GetCore("CongTime")
        new_skim_file = opts.out_file
        new_skim = CreateObject("Matrix", new_skim_file)
        new_core = new_skim.GetCore("CongTime")
        results = MatrixRMSE(old_core, new_core)

        // // This is testing/research code for alternative convergence approaches.
        // flow_mtx_file = assn_dir + "/od_veh_trips_" + period + ".mtx"
        // flow_mtx = CreateObject("Matrix", flow_mtx_file)
        // weight_core = flow_mtx.GetCore("sov_VOT2")
        // results2 = RunMacro("Matrix RMSE", {mc1: old_core, mc2: new_core, mc_weight: weight_core})

        old_skim = null
        old_core = null
        new_skim = null
        new_core = null      
        DeleteFile(new_skim_file)
        Args.(period + "_PRMSE") = results.RelRMSE
        RunMacro("Write PRMSE", Args, period)
    end
endmacro

/*
Similar to the GISDK function MatrixRMSE(), but allows for
a weight matrix (usually a flow matrix). This means differnces
in ij pair travel times with little to no flow do not influence
the %RMSE calculation.
*/

Macro "Matrix RMSE" (MacroOpts)

    mc1 = MacroOpts.mc1
    mc2 = MacroOpts.mc2
    mc_weight = MacroOpts.mc_weight

    mtx1 = CreateObject("Matrix", mc1)
    mtx2 = CreateObject("Matrix", mc2)

    // Calculate squared errors
    mtx2.AddCores({"sqerr"})
    sqerr_core = mtx2.GetCore("sqerr")
    sqerr_core := pow(mc2 - mc1, 2)
    
    // Calculate total weight
    mtx_weight = CreateObject("Matrix", mc_weight)
    weight_mh = mtx_weight.GetMatrixHandle()
    stats = MatrixStatistics(weight_mh, {Tables: {mc_weight.core}})
    tot_weight = stats.(mc_weight.core).Sum

    // Weight the squared errors
    sqerr_core := sqerr_core * mc_weight / tot_weight

    // Finish rmse calc (prmse numerator)
    temp_stats = MatrixStatistics(mtx2.GetMatrixHandle(), {Tables: {sqerr_core.core}})
    rmse = Pow(temp_stats.(sqerr_core.core).Sum, .5)

    // Calculate the average weighted skim (prmse denominator)
    mtx2.AddCores({"weighted_skim"})
    wskim_core = mtx2.GetCore("weighted_skim")
    wskim_core := mc1 * mc_weight / tot_weight
    wskim_stats = MatrixStatistics(mtx2.GetMatrixHandle(), {Tables: {wskim_core.core}})
    prmse = rmse / wskim_stats.(wskim_core.core).Sum * 100

    sqerr_core = null
    wskim_core = null
    mtx2.DropCores({"temp", "weighted_skim"})
    return({rmse: rmse, prmse: prmse})
endmacro

/*
Called by the flowchart to run peak hour assignment
*/

Macro "Peak Hour Roadway Assignment" (Args)
    RunMacro("Peak Hour Assignment", Args)
    return(1)
endmacro

/*
This macro runs after feedback is complete. It assigns the peak hour
of the PM period against one hour of capacity.
*/

Macro "Peak Hour Assignment" (Args)
    pkhr_factor = .39
    links = Args.Links
    net_dir = Args.[Output Folder] + "/networks"
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    pm_mtx = assn_dir + "/od_veh_trips_PM.mtx"

    // Create peak hour demand matrix
    pm_pk_mtx_file = assn_dir + "/od_veh_trips_PM_PKHR.mtx"
    CopyFile(pm_mtx, pm_pk_mtx_file)
    mtx = CreateObject("Matrix", pm_pk_mtx_file)
    core_names = mtx.GetCoreNames()
    cores = mtx.GetCores()
    for core_name in core_names do
        cores.(core_name) := cores.(core_name) * pkhr_factor
    end
    cores = null
    mtx = null

    // Create peak hour network
    pm_net_file = net_dir + "/net_PM_sov.net"
    pmpk_net_file = net_dir + "/net_PMPK_sov.net"
    CopyFile(pm_net_file, pmpk_net_file)
    o = CreateObject("Network.Update", {Network: pmpk_net_file})
    o.LayerDB = links
    o.Network = pmpk_net_file
    o.UpdateLinkField({Name: "Capacity", Field: {"ABPMCapE_h", "BAPMCapE_h"}})

    // Run assignment
    RunMacro("Run Roadway Assignment", Args, {
        od_mtx: pm_pk_mtx_file,
        period: "PM",
        net_file: pmpk_net_file,
        flow_table: assn_dir + "/pmpk_hr_assn.bin"
    })
endmacro