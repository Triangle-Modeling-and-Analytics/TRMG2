/*

*/

Macro "Roadway Assignment" (Args)

    RunMacro("Run Roadway Assignment", Args)
    return(1)
endmacro

/*

*/

Macro "Run Roadway Assignment" (Args)

    net_dir = Args.[Output Folder] + "\\networks\\"
    periods = Args.periods
    feedback_iter = Args.Iteration
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\iter_" + String(feedback_iter)
    RunMacro("Create Directory", assn_dir)
    // TODO: Use actual OD matrices
    od_dir = "C:\\projects\\TRM\\trm_project\\working_files\\initial_cong_skims"

    for period in periods do
        od_mtx = od_dir + "\\TOT" + period + "_OD_conv_tod.mtx"
        net_file = net_dir + "net_" + period + "_sov.net"

        o = CreateObject("Network.Assignment")
        o.Network = net_file
        o.LayerDB = Args.Links
        o.ResetClasses()
        o.Iterations = Args.AssignIterations
        o.Convergence = Args.AssignConvergence
        o.Method = "CUE"
        o.DelayFunction = {
            Function: "bpr.vdf",
            Fields: {"FFTime", "Capacity", "Alpha", "Beta", "None"}
        }
        // TODO: wait for Andres to add InputPathFile and use that to warm start
        // from previous path files.
        o.OutPathFile = assn_dir + "\\assn_paths_" + period + ".path"
        o.DemandMatrix({
            MatrixFile: od_mtx,
            Matrix: "SOV"
        })
        o.AddClass({
            Demand: "SOV",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCost",
            ExclusionFilter: "D = 1 and HOV = 'None'"
        })
        o.AddClass({
            Demand: "HOV",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCost",
            ExclusionFilter: "D = 1"
        })
        o.AddClass({
            Demand: "SUT",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCostSUT",
            ExclusionFilter: "D = 1 and HOV = 'None'"
        })
        o.AddClass({
            Demand: "MUT",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCostSUT",
            ExclusionFilter: "D = 1 and HOV = 'None'"
        })
        o.MSAFeedback({
            Flow: "MSAFlow",
            Time: "MSATime",
            Iteration: Args.FeedbackIterations
        })
        o.FlowTable = assn_dir + "\\roadway_assignment_" + period + ".bin"
        ret_value = o.Run()
        results = o.GetResults()
Throw()        
    end

endmacro