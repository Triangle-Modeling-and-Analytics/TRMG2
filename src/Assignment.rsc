/*

*/

Macro "Roadway Assignment" (Args)

    RunMacro("Run Roadway Assignment", Args)
    // RunMacro("Update Link Congested Times", Args)
    return(1)
endmacro

/*

*/

Macro "Run Roadway Assignment" (Args)

    hwy_dbd = Args.Links
    net_dir = Args.[Output Folder] + "\\networks\\"
    periods = Args.periods
    feedback_iter = Args.FeedbackIteration
    prev_assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter - 1)
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)
    RunMacro("Create Directory", assn_dir)
    // TODO: Use actual OD matrices
    od_dir = "C:\\projects\\TRM\\trm_project\\working_files\\initial_cong_skims"

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
        od_mtx = od_dir + "\\TOT" + period + "_OD_conv_tod.mtx"
        net_file = net_dir + "net_" + period + "_hov.net"

        o = CreateObject("Network.Assignment")
        o.Network = net_file
        o.LayerDB = hwy_dbd
        o.ResetClasses()
        o.Iterations = Args.AssignIterations
        // TODO: move back to the official number (10e-5)
        // o.Convergence = Args.AssignConvergence
        o.Convergence = .0003
        o.Method = "CUE"
        o.DelayFunction = {
            Function: "bpr.vdf",
            Fields: {"FFTime", "Capacity", "Alpha", "Beta", "None"}
        }
        o.OutPathFile = assn_dir + "\\assn_paths_" + period + ".path"
        If Args.Iteraion > 1 then o.UsePathFile(
            prev_assn_dir + "\\assn_paths_" + period + ".path"
        )
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
        class_opts = {
            Demand: "SOV",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCost"
        }
        if hov_exists then class_opts = class_opts + {ExclusionFilter: "HOV <> 'None'"}
        o.AddClass(class_opts)
        o.AddClass({
            Demand: "HOV",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCost"
        })
        class_opts = {
            Demand: "SUT",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCostSUT"
        }
        if hov_exists then class_opts = class_opts + {ExclusionFilter: "HOV <> 'None'"}
        o.AddClass(class_opts)
        class_opts = {
            Demand: "MUT",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCostMUT"
        }
        if hov_exists then class_opts = class_opts + {ExclusionFilter: "HOV <> 'None'"}
        o.AddClass(class_opts)
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

// Macro "Update Link Congested Times" (Args)

//     hwy_dbd = Args.Links
//     periods = Args.periods
//     feedback_iter = Args.FeedbackIteration
//     assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)

//     {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    
//     for period in periods do
//         assn_dir + "\\roadway_assignment_" + period + ".bin"
//     end

//     CloseMap(map)
// endmacro