/*
TODO: These functions are written and tested on interim data (for initial cong
skims), but have not been officially put into the model stream. Still need to
tie them in.
*/

Macro "Roadway Assignment" (Args)

    // RunMacro("VOT Split", Args)
    // RunMacro("Run Roadway Assignment", Args)
    // RunMacro("Update Link Congested Times", Args)
    return(1)
endmacro

/*
This borrows the NCSTM approach to split OD matrices into distinct values of
time. This is based both on the distance of the trip and the average HH incomes
in the origin and destination zones.
*/

Macro "VOT Split" (Args)

    se_file = Args.SE
    vot_params = Args.[Input Folder] + "/assignment/vot_params.csv"
    periods = Args.periods
    iter = Args.FeedbackIteration
    assn_dir = Args.[Output Folder] + "/assignment/roadway/iter_" + String(iter)
    skim_dir = Args.[Output Folder] + "/skims/roadway"

    p = RunMacro("Read Parameter File", {file: vot_params})

    se_vw = OpenTable("se", "FFB", {se_file})
    {v_hh, v_inc} = GetDataVectors(
        se_vw + "|", {"HH","Median_Inc"}, 
        {{"Sort Order",{{"TAZ","Ascending"}}}}
    )

    for period in periods do
        if period = "AM" or period = "PM"
            then pkop = "pk"
            else pkop = "op"
        // TODO: change to actual file name
        // input_file = assn_dir + "/TOT" + period + "_OD_conv_tod.mtx"
        input_file = assn_dir + "/TOT" + period + "_OD_conv_tod_full.mtx"
        output_file = Substitute(input_file, ".mtx", "_vot.mtx", )
        CopyFile(input_file, output_file)
        skim_file = skim_dir + "/skim_sov_" + period + ".mtx"
        
        skim = CreateObject("Matrix")
        skim.LoadMatrix(skim_file)
        length_skim = skim.data.cores.("Length (Skim)")

        // Calculate weighted income
        output = CreateObject("Matrix")
        output.LoadMatrix(output_file)
        veh_classes = output.CoreNames
        output.AddCores({"hh", "wgtinc", "otemp", "dtemp"})
        cores = output.data.cores
        cores.otemp := v_hh
        v_hh.rowbased = "false"
        cores.dtemp := v_hh
        v_hh.rowbased = true
        cores.hh := cores.otemp + cores.dtemp
        v_tothhinc = v_inc/100 * v_hh
		cores.otemp    := v_tothhinc
		v_tothhinc.rowbased = false
		cores.dtemp    := v_tothhinc
		v_tothhinc.rowbased = true
		cores.wgtinc    := (cores.otemp + cores.dtemp) / cores.hh
        output.DropCores({"hh", "otemp", "dtemp"})

        output.AddCores({"lognorm", "zscore"})
        for veh_class in veh_classes do
            
            // Auto classes
            if veh_class = "SOV" or veh_class = "HOV" then do
                meanvot = p.(pkop + "_meanvot")
                targetvot = p.(pkop + "_targetvot")
                costcoef = p.(pkop + "_costcoef")
                meantime = p.(pkop + "_meantime")
                sdtime = p.(pkop + "_sdtime")
                for i = 1 to 5 do
                    votcut = p.("votcut" + i2s(i))
                    out_core = veh_class + "_VOT" + i2s(i)
                    cumu_prob = veh_class + "_VOT" + i2s(i) + "_cumuprob"
                    prob_core = veh_class + "_VOT" + i2s(i) + "_prob"
                    output.AddCores({cumu_prob, prob_core, out_core})
                    cores = output.data.cores

                    // Calculate cumulative probability
                    cores.lognorm := (votcut * costcoef) / (log(cores.wgtinc) * log(10 * length_skim + 5) * 60 * (targetvot/meanvot))
                    cores.zscore := (log(-1 * cores.lognorm) - meantime) / sdtime
                    RunMacro("erf_normdist", output, cumu_prob)

                    // Convert cumulative probability to individual
                    if i = 1 then do
                        cores.(prob_core) := cores.(cumu_prob)
                    end else do
                        prev_cumu = veh_class + "_VOT" + i2s(i - 1) + "_cumuprob"
                        if i = 5 then cores.(prob_core) := 1 - cores.(prev_cumu)
                        else cores.(prob_core) := cores.(cumu_prob) - cores.(prev_cumu)
                    end

                    // Calculate final core
                    cores.(out_core) := cores.(veh_class) * cores.(prob_core)    
                end

                // Cleanup
                for i = 1 to 5 do
                    cumu_prob = veh_class + "_VOT" + i2s(i) + "_cumuprob"
                    prob_core = veh_class + "_VOT" + i2s(i) + "_prob"
                    output.DropCores({prob_core, cumu_prob})
                end
            end

            // Truck Classes
            if veh_class = "SUT" then truck_classes = 3
            else if veh_class = "MUT" then truck_classes = 5
            else truck_classes = 0
            for i = 1 to truck_classes do
                weight = p.(Lower(veh_class) + "wgt" + i2s(i))
                out_core = veh_class + "_VOT" + i2s(i)
                output.AddCores({out_core})
                cores = output.data.cores
                cores.(out_core) := cores.(veh_class) * weight
            end
        end
        output.DropCores({"lognorm", "zscore", "wgtinc"})
    end

    CloseView(se_vw)
endmacro

/*
Helper function for "VOT Split"

Calculates NORMDIST(z) by using an error function approximation (modified using Horner's method)
https://www.codeproject.com/Articles/408214/Excel-Function-NORMSDIST-z_score
*/

Macro "erf_normdist" (matrix, out_corename)

    matrix.AddCores({"sign", "x", "t", "erf", "normdist"})
    cores = matrix.data.cores

	//Calculate erf(x)
	cores.x := Abs(cores.zscore)/Sqrt(2)
	a1 = 0.254829592
	a2 = -0.284496736
	a3 = 1.421413741
	a4 = -1.453152027
	a5 = 1.061405429
	p = 0.3275911
	cores.x := Abs(cores.x)
	cores.t := 1 / (1 + p * cores.x)
	cores.erf := 1 - ((((((a5 * cores.t + a4) * cores.t) + a3) * cores.t + a2) * cores.t) + a1) * cores.t * Exp(-1 * cores.x * cores.x)
	//Calculate normdist(zscore)
	cores.sign := if cores.zscore < 0 then -1 else 1
	cores.normdist := 0.5 * (1.0 + cores.sign * cores.erf)
	cores.(out_corename) := cores.normdist

	//Cleanup
    matrix.DropCores({"sign", "x", "t", "erf", "normdist"})
endMacro

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
            LinkTollField: "TollCostSOV"
        }
        if hov_exists then class_opts = class_opts + {ExclusionFilter: "HOV <> 'None'"}
        o.AddClass(class_opts)
        o.AddClass({
            Demand: "HOV",
            PCE: 1,
            VOI: 1,
            LinkTollField: "TollCostHOV"
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