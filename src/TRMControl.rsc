Macro "TRM"
    scen_dir = "C:\\projects\\TRM\\Repo\\scenarios\\base_2016"

    Args = null
    
    // Folder definitions
    Args.[Scenario Folder] = scen_dir
    Args.[Input Folder] = scen_dir + "\\input"      // This parameter will be a derived parameter in the flowchart
    Args.[Output Folder] = scen_dir + "\\output"    // This parameter will be a derived parameter in the flowchart
    
    // Input SE Data and Disagg Curves
    Args.SEData = Args.[Input Folder] + "\\se_data\\se_2016.bin"
    Args.IncomeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\income_curves.csv"
    Args.SizeCurves = Args.[Input Folder] + "\\resident\\disagg_model\\size_curves.csv"
    Args.WorkerCurves = Args.[Input Folder] + "\\resident\\disagg_model\\worker_curves.csv"
    Args.RegionalMedianIncome = 65317

    // Output Marginals File after disagg
    Args.SEDMarginals = Args.[Output Folder] + "\\resident\\disagg_model\\SEDMarginals.bin"

    // Run Macro to disaggegate curves
    ret = RunMacro("DisaggregateSED", Args)
endMacro
