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
        * `od_mtx`
            * String
            * File path of OD matrix to use
            * used by "Check Highway Networks" macro
        * `assign_iters`
            * Integer
            * Number of max assignment iterations
            * used by "Check Highway Networks" macro
        * `period`
            * String
            * Used to run a single period instead of all
            * used by the TOD assignment macros
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

        o = CreateObject("Network.Assignment")
        o.Network = net_file
        o.LayerDB = hwy_dbd
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
        o.FlowTable = assn_dir + "\\roadway_assignment_" + period + ".bin"
        // Add classes for each combination of vehicle type and VOT
        // If doing a test assignment, just create a single class from the
        // dummy matrix
        if OtherOpts.od_mtx <> null then do
            o.AddClass({
                Demand: "TAZ",
                PCE: 1,
                VOI: 1
            })
        end else do

            if period = "AM" or period = "PM"
                then pkop = "pk"
                else pkop = "op"

            // // The 5 auto value of time bins are collapsed to 1->2<-3, 4, 5
            // auto_vot_ints = {2, 4, 5}

            // Auto VOT 1 and 2 are collapsed into 2
            auto_vot_ints = {2, 3, 4, 5}

            // sov
            for i in auto_vot_ints do
                voi = vot_params.auto_calib_factor * vot_params.(pkop + "_auto_vot" + String(i)) / 60 // ($/min)
                sov_opts = {
                    Demand: "sov_VOT" + String(i),
                    PCE: 1,
                    VOI: voi,
                    LinkTollField: "TollCostSOV"
                }
                if hov_exists then sov_opts = sov_opts + {ExclusionFilter: "HOV <> 'None'"}
                o.AddClass(sov_opts)
            end
            // hov2
            for i in auto_vot_ints do
                voi = vot_params.auto_calib_factor * vot_params.(pkop + "_auto_vot" + String(i)) / 60 // ($/min)
                o.AddClass({
                    Demand: "hov2_VOT" + String(i),
                    PCE: 1,
                    VOI: voi,
                    LinkTollField: "TollCostHOV"
                })
            end
            // hov3
            for i in auto_vot_ints do
                voi = vot_params.auto_calib_factor * vot_params.(pkop + "_auto_vot" + String(i)) / 60 // ($/min)
                o.AddClass({
                    Demand: "hov3_VOT" + String(i),
                    PCE: 1,
                    VOI: voi,
                    LinkTollField: "TollCostHOV"
                })
            end
            // CV
            for i in auto_vot_ints do
                voi = vot_params.auto_calib_factor * vot_params.(pkop + "_auto_vot" + String(i)) / 60 // ($/min)
                cv_opts = {
                    Demand: "CV_VOT" + String(i),
                    PCE: 1,
                    VOI: voi,
                    LinkTollField: "TollCostSOV"
                }
                if hov_exists then cv_opts = cv_opts + {ExclusionFilter: "HOV <> 'None'"}
                o.AddClass(cv_opts)
            end
            // SUT
            for i = 1 to 3 do
                sut_opts = {
                    Demand: "SUT_VOT" + String(i),
                    PCE: 1.5,
                    VOI: vot_params.("sut_vot" + String(i)) / 60, // ($/min)
                    LinkTollField: "TollCostSUT"
                }
                if hov_exists then sut_opts = sut_opts + {ExclusionFilter: "HOV <> 'None'"}
                o.AddClass(sut_opts)
            end
            // MUT
            for i = 1 to 5 do
                mut_opts = {
                    Demand: "MUT_VOT" + String(i),
                    PCE: 2.5,
                    VOI: vot_params.("mut_vot" + String(i)) / 60, // ($/min)
                    LinkTollField: "TollCostMUT"
                }
                if hov_exists then mut_opts = mut_opts + {ExclusionFilter: "HOV <> 'None'"}
                o.AddClass(mut_opts)
            end
        end
        ret_value = o.Run()
        results = o.GetResults()
        /*
        Use results.data to get rmse and other metrics:
        results.data.[Relative Gap]
        results.data.[Maximum Flow Change]
        results.data.[MSA RMSE]
        results.data.[MSA PERCENT RMSE]
        etc.
        */

        Args.(period + "_PRMSE") = results.Data.[MSA PERCENT RMSE]
        RunMacro("Write PRMSE", Args, period)
    end
endmacro

/*
After assignment, this macro updates the link layer congested time fields.
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
            SetDataVector(jv + "|", old_field, v_new, )
        end

        CloseView(jv)
        CloseView(assn_vw)
    end

    CloseMap(map)
    return(1)
endmacro