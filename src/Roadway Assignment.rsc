/*
TODO: These functions are written and tested on interim data (for initial cong
skims), but have not been officially put into the model stream. Still need to
tie them in.
*/

Macro "Roadway Assignment" (Args)

    RunMacro("Run Roadway Assignment", Args)
    // TODO: uncomment when feeding back
    // RunMacro("Update Link Congested Times", Args)
    return(1)
endmacro



/*
Runs highway assignment.

Early in the model run, this macro is called in testing mode to check the
validity of the highway network and prevent wasted run time.
*/

Macro "Run Roadway Assignment" (Args, OtherOpts)

    hwy_dbd = Args.Links
    net_dir = Args.[Output Folder] + "\\networks\\"
    periods = Args.periods
    feedback_iter = Args.FeedbackIteration
    assign_iters = Args.AssignIterations
    assn_dir = Args.[Output Folder] + "/assignment/roadway"
    vot_params = Args.[Input Folder] + "/assignment/vot_params.csv"
    test_opts = OtherOpts.test_opts
    
    vot_params = RunMacro("Read Parameter File", {file: vot_params})

    // Check if HOV links exist. If so, they will be excluded from sov/truck
    // assignment.
    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    SetLayer(llyr)
    n = SelectByQuery(
        "hov", "several", 
        "Select * where HOV <> 'None' and HOV <> null"
    )
    if n > 0 then hov_exists = "true"
    CloseMap(map)

    for period in periods do
        od_mtx = assn_dir + "/od_veh_trips_" + period + ".mtx"
        net_file = net_dir + "net_" + period + "_hov.net"

        // If doing a test assignment, use the dummy OD matrix provided
        if test_opts <> null then do
            od_mtx = test_opts.od_mtx
            assign_iters = 1
        end

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
        o.DemandMatrix({
            MatrixFile: od_mtx,
            Matrix: "SOV"
        })
        o.MSAFeedback({
            Flow: "MSAFlow",
            Time: "MSATime",
            Iteration: feedback_iter
        })
        o.FlowTable = assn_dir + "\\roadway_assignment_" + period + ".bin"
        // Add classes for each combination of vehicle type and VOT
        // If doing a test assignment, just create a single class from the
        // dummy matrix
        if test_opts <> null then do
            o.AddClass({
                Demand: "TAZ",
                PCE: 1,
                VOI: 1
            })
        end else do

            if period = "AM" or period = "PM"
                then pkop = "pk"
                else pkop = "op"

            // The 5 auto value of time bins are collapsed to 1->2<-3, 4, 5
            auto_vot_ints = {2, 4, 5}

            // sov
            for i in auto_vot_ints do
                sov_opts = {
                    Demand: "sov_VOT" + String(i),
                    PCE: 1,
                    VOI: vot_params.(pkop + "_auto_vot" + String(i)) / 60 * 100,
                    LinkTollField: "TollCostSOV"
                }
                if hov_exists then sov_opts = sov_opts + {ExclusionFilter: "HOV <> 'None'"}
                o.AddClass(sov_opts)
            end
            // hov2
            for i in auto_vot_ints do
                o.AddClass({
                    Demand: "hov2_VOT" + String(i),
                    PCE: 1,
                    VOI: vot_params.(pkop + "_auto_vot" + String(i)) / 60 * 100,
                    LinkTollField: "TollCostHOV"
                })
            end
            // hov3
            for i in auto_vot_ints do
                o.AddClass({
                    Demand: "hov3_VOT" + String(i),
                    PCE: 1,
                    VOI: vot_params.(pkop + "_auto_vot" + String(i)) / 60 * 100,
                    LinkTollField: "TollCostHOV"
                })
            end
            // CV
            for i in auto_vot_ints do
                cv_opts = {
                    Demand: "CV_VOT" + String(i),
                    PCE: 1,
                    VOI: vot_params.(pkop + "_auto_vot" + String(i)) / 60 * 100,
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
                    VOI: vot_params.("sut_vot" + String(i)) / 60 * 100,
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
                    VOI: vot_params.("mut_vot" + String(i)) / 60 * 100,
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
        etc.
        */
    end
endmacro

/*
After assignment, this macro updates the link layer congested time fields.
*/

Macro "Update Link Congested Times" (Args)

    hwy_dbd = Args.Links
    periods = Args.periods
    feedback_iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)

    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    
    dirs = {"AB", "BA"}

    for period in periods do
        assn_file = assn_dir + "\\roadway_assignment_" + period + ".bin"
        assn_vw = OpenTable("assn", "FFB", {assn_file})
        jv = JoinViews("jv", llyr + ".ID", assn_vw + ".ID1", )

        for dir in dirs do
            old_field = llyr + ".AB" + period + "Time"
            new_field = assn_vw + "." + dir + "_Time"
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
endmacro